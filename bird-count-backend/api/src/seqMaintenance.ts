import { QueryCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { docClient } from "./dynamo.js";
import { valkeyClient, tripSeqKey, raiseOnlySet } from "./valkey.js";

const TABLE = process.env.TABLE_NAME!;
const CHANGES_INDEX = "changes";
const OBS_NUMBER_INDEX = "gsi_observationNumber";
const PAGE_SIZE = 500;

interface MaintenanceEvent {
  action: "status" | "seed" | "backfill";
  trip?: string;
  dryRun?: boolean;
}

// Yields all items for a trip from the changes GSI in serverUpdatedAt ascending order.
async function* scanByUpdatedAt(doc: ReturnType<typeof docClient>, pk: string) {
  let lastKey: Record<string, unknown> | undefined;
  do {
    const res = await doc.send(
      new QueryCommand({
        TableName: TABLE,
        IndexName: CHANGES_INDEX,
        KeyConditionExpression: "pk = :pk",
        ExpressionAttributeValues: { ":pk": pk },
        ScanIndexForward: true,
        Limit: PAGE_SIZE,
        ExclusiveStartKey: lastKey,
      }),
    );
    for (const item of res.Items ?? []) yield item;
    lastKey = res.LastEvaluatedKey as Record<string, unknown> | undefined;
  } while (lastKey);
}

// Returns the highest observationNumber for a trip, or 0 if none exist.
// Queries gsi_observationNumber DESC with Limit=1 — O(1).
async function queryDynamoMax(doc: ReturnType<typeof docClient>, pk: string): Promise<number> {
  const res = await doc.send(
    new QueryCommand({
      TableName: TABLE,
      IndexName: OBS_NUMBER_INDEX,
      KeyConditionExpression: "pk = :pk",
      ExpressionAttributeValues: { ":pk": pk },
      ScanIndexForward: false,
      Limit: 1,
    }),
  );
  const items = res.Items ?? [];
  return items.length > 0 ? (items[0].observationNumber as number) : 0;
}

async function runStatus(doc: ReturnType<typeof docClient>, trip: string) {
  const key = tripSeqKey(trip);
  const valkey = valkeyClient();
  const [raw, dbMax] = await Promise.all([valkey.get(key), queryDynamoMax(doc, trip)]);
  return {
    action: "status",
    trip,
    valkeyValue: raw !== null ? Number(raw) : null,
    dynamoMax: dbMax,
  };
}

async function runSeed(
  doc: ReturnType<typeof docClient>,
  trip: string,
  dryRun: boolean,
  knownMax?: number,
) {
  const key = tripSeqKey(trip);
  const valkey = valkeyClient();
  const [raw, dbMax] = await Promise.all([
    valkey.get(key),
    knownMax !== undefined ? Promise.resolve(knownMax) : queryDynamoMax(doc, trip),
  ]);
  const before = raw !== null ? Number(raw) : null;

  if (dryRun) {
    return { action: "seed", trip, dryRun, before, dynamoMax: dbMax, after: null, wrote: false };
  }

  const wrote = await raiseOnlySet(valkey, key, dbMax);
  const afterRaw = await valkey.get(key);
  return {
    action: "seed",
    trip,
    dryRun,
    before,
    dynamoMax: dbMax,
    after: afterRaw !== null ? Number(afterRaw) : null,
    wrote,
  };
}

async function runBackfill(doc: ReturnType<typeof docClient>, trip: string, dryRun: boolean) {
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
          new UpdateCommand({
            TableName: TABLE,
            Key: { pk: item.pk, sk: item.sk },
            UpdateExpression: "SET observationNumber = :n",
            ConditionExpression: "attribute_not_exists(observationNumber)",
            ExpressionAttributeValues: { ":n": next },
          }),
        );
      } catch (err) {
        // A concurrent backfill run numbered this item first; skip the slot.
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

export async function handler(event: MaintenanceEvent) {
  if (!TABLE) throw new Error("TABLE_NAME is not set");
  const trip = event.trip ?? "shared";
  const dryRun = event.dryRun ?? true;
  const doc = docClient();

  switch (event.action) {
    case "status":
      return runStatus(doc, trip);
    case "seed":
      return runSeed(doc, trip, dryRun);
    case "backfill":
      return runBackfill(doc, trip, dryRun);
    default:
      throw new Error(`Unknown action: ${(event as MaintenanceEvent).action}`);
  }
}
