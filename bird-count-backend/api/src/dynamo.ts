import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  QueryCommand,
} from "@aws-sdk/lib-dynamodb";
import type { ObservationRecordDTO } from "./generated/types.js";

export interface StoredObservation extends ObservationRecordDTO {
  pk: string;
  sk: string;
  observerSub: string;
  updatedAt: number;
  serverUpdatedAt: number;
  createdAt: number;
  schemaVersion: number;
}

const TABLE = process.env.TABLE_NAME ?? "birdcount-data-dev";
const CHANGES_INDEX = "changes";

export function docClient(endpoint?: string): DynamoDBDocumentClient {
  const client = new DynamoDBClient(
    endpoint ? { endpoint, region: "local", credentials: { accessKeyId: "local", secretAccessKey: "local" } } : {},
  );
  return DynamoDBDocumentClient.from(client, {
    marshallOptions: { removeUndefinedValues: true },
  });
}

/**
 * Conditional upsert: applies when the item is new or the incoming updatedAt
 * is not older than the stored one (whole-record LWW; in practice only the
 * location backfill ever overwrites). Returns false when stale.
 */
export async function putObservation(
  doc: DynamoDBDocumentClient,
  item: StoredObservation,
): Promise<boolean> {
  try {
    await doc.send(
      new PutCommand({
        TableName: TABLE,
        Item: item,
        ConditionExpression: "attribute_not_exists(sk) OR updatedAt <= :u",
        ExpressionAttributeValues: { ":u": item.updatedAt },
      }),
    );
    return true;
  } catch (err) {
    if (err instanceof Error && err.name === "ConditionalCheckFailedException") return false;
    throw err;
  }
}

export interface ChangesPage {
  items: StoredObservation[];
  hasMore: boolean;
}

/** Records in scope with serverUpdatedAt > since (caller applies the overlap window). */
export async function queryChanges(
  doc: DynamoDBDocumentClient,
  scope: string,
  since: number,
  limit: number,
): Promise<ChangesPage> {
  const res = await doc.send(
    new QueryCommand({
      TableName: TABLE,
      IndexName: CHANGES_INDEX,
      KeyConditionExpression: "pk = :pk AND serverUpdatedAt > :since",
      ExpressionAttributeValues: { ":pk": scope, ":since": since },
      Limit: limit,
      ScanIndexForward: true,
    }),
  );
  return {
    items: (res.Items ?? []) as StoredObservation[],
    hasMore: res.LastEvaluatedKey !== undefined,
  };
}
