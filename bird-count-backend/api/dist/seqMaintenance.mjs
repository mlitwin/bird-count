import { createRequire } from 'module'; const require = createRequire(import.meta.url);

// src/seqMaintenance.ts
import { QueryCommand as QueryCommand2, UpdateCommand as UpdateCommand3 } from "@aws-sdk/lib-dynamodb";

// src/dynamo.ts
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  UpdateCommand,
  QueryCommand
} from "@aws-sdk/lib-dynamodb";
if (!process.env.TABLE_NAME) {
  throw new Error("TABLE_NAME environment variable is not set");
}
var TABLE = process.env.TABLE_NAME;
function docClient(endpoint) {
  const client = new DynamoDBClient(
    endpoint ? { endpoint, region: "local", credentials: { accessKeyId: "local", secretAccessKey: "local" } } : {}
  );
  return DynamoDBDocumentClient.from(client, {
    marshallOptions: { removeUndefinedValues: true }
  });
}

// src/seq.ts
import { GetCommand, UpdateCommand as UpdateCommand2 } from "@aws-sdk/lib-dynamodb";
if (!process.env.SEQ_TABLE_NAME) {
  throw new Error("SEQ_TABLE_NAME environment variable is not set");
}
var SEQ_TABLE = process.env.SEQ_TABLE_NAME;
function tripSeqKey(trip) {
  return `trip:${trip}:seq`;
}
function isConditionFailure(err) {
  return err instanceof Error && err.name === "ConditionalCheckFailedException";
}
async function getSeq(doc, key) {
  const res = await doc.send(
    new GetCommand({ TableName: SEQ_TABLE, Key: { pk: key }, ConsistentRead: true })
  );
  return typeof res.Item?.seq === "number" ? res.Item.seq : null;
}
async function raiseOnlySet(doc, key, value) {
  try {
    await doc.send(
      new UpdateCommand2({
        TableName: SEQ_TABLE,
        Key: { pk: key },
        UpdateExpression: "SET seq = :v",
        ConditionExpression: "attribute_not_exists(seq) OR seq < :v",
        ExpressionAttributeValues: { ":v": value }
      })
    );
    return true;
  } catch (err) {
    if (isConditionFailure(err)) return false;
    throw err;
  }
}

// src/seqMaintenance.ts
var TABLE2 = process.env.TABLE_NAME;
var CHANGES_INDEX = "changes";
var OBS_NUMBER_INDEX = "gsi_observationNumber";
var PAGE_SIZE = 500;
async function* scanByUpdatedAt(doc, pk) {
  let lastKey;
  do {
    const res = await doc.send(
      new QueryCommand2({
        TableName: TABLE2,
        IndexName: CHANGES_INDEX,
        KeyConditionExpression: "pk = :pk",
        ExpressionAttributeValues: { ":pk": pk },
        ScanIndexForward: true,
        Limit: PAGE_SIZE,
        ExclusiveStartKey: lastKey
      })
    );
    for (const item of res.Items ?? []) yield item;
    lastKey = res.LastEvaluatedKey;
  } while (lastKey);
}
async function queryDynamoMax(doc, pk) {
  const res = await doc.send(
    new QueryCommand2({
      TableName: TABLE2,
      IndexName: OBS_NUMBER_INDEX,
      KeyConditionExpression: "pk = :pk",
      ExpressionAttributeValues: { ":pk": pk },
      ScanIndexForward: false,
      Limit: 1
    })
  );
  const items = res.Items ?? [];
  return items.length > 0 ? items[0].observationNumber : 0;
}
async function runStatus(doc, trip) {
  const [counterValue, dbMax] = await Promise.all([
    getSeq(doc, tripSeqKey(trip)),
    queryDynamoMax(doc, trip)
  ]);
  return {
    action: "status",
    trip,
    counterValue,
    dynamoMax: dbMax
  };
}
async function runSeed(doc, trip, dryRun, knownMax, floor = 0) {
  const key = tripSeqKey(trip);
  const [before, dbMax] = await Promise.all([
    getSeq(doc, key),
    knownMax !== void 0 ? Promise.resolve(knownMax) : queryDynamoMax(doc, trip)
  ]);
  const target = Math.max(dbMax, floor);
  if (dryRun) {
    return { action: "seed", trip, dryRun, before, dynamoMax: dbMax, floor, after: null, wrote: false };
  }
  const wrote = await raiseOnlySet(doc, key, target);
  const after = await getSeq(doc, key);
  return { action: "seed", trip, dryRun, before, dynamoMax: dbMax, floor, after, wrote };
}
async function runBackfill(doc, trip, dryRun) {
  const existingMax = await queryDynamoMax(doc, trip);
  let next = existingMax + 1;
  let assigned = 0;
  let skipped = 0;
  for await (const item of scanByUpdatedAt(doc, trip)) {
    if (item.observationNumber != null) {
      skipped++;
      continue;
    }
    if (!dryRun) {
      try {
        await doc.send(
          new UpdateCommand3({
            TableName: TABLE2,
            Key: { pk: item.pk, sk: item.sk },
            UpdateExpression: "SET observationNumber = :n",
            ConditionExpression: "attribute_not_exists(observationNumber)",
            ExpressionAttributeValues: { ":n": next }
          })
        );
      } catch (err) {
        if (err instanceof Error && err.name === "ConditionalCheckFailedException") {
          skipped++;
          continue;
        }
        throw err;
      }
    }
    next++;
    assigned++;
  }
  const maxAssigned = assigned > 0 ? next - 1 : existingMax;
  const seed = await runSeed(doc, trip, dryRun, maxAssigned);
  return { action: "backfill", trip, dryRun, assigned, skipped, seed };
}
async function handler(event) {
  if (!TABLE2) throw new Error("TABLE_NAME is not set");
  const trip = event.trip ?? "shared";
  const dryRun = event.dryRun ?? true;
  const doc = docClient();
  switch (event.action) {
    case "status":
      return runStatus(doc, trip);
    case "seed":
      return runSeed(doc, trip, dryRun, void 0, event.floor ?? 0);
    case "backfill":
      return runBackfill(doc, trip, dryRun);
    default:
      throw new Error(`Unknown action: ${event.action}`);
  }
}
export {
  handler
};
