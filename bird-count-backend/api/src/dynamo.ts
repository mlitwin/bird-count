import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  PutCommand,
  UpdateCommand,
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

if (!process.env.TABLE_NAME) {
  throw new Error("TABLE_NAME environment variable is not set");
}
const TABLE = process.env.TABLE_NAME;
const CHANGES_INDEX = "changes";
const OBS_NUMBER_INDEX = "gsi_observationNumber";

export function docClient(endpoint?: string): DynamoDBDocumentClient {
  const client = new DynamoDBClient(
    endpoint ? { endpoint, region: "local", credentials: { accessKeyId: "local", secretAccessKey: "local" } } : {},
  );
  return DynamoDBDocumentClient.from(client, {
    marshallOptions: { removeUndefinedValues: true },
  });
}

/** "noop" carries the stored observationNumber (may be absent if a prior setObservationNumber failed). */
export type PutResult = "written" | "stale" | { kind: "noop"; observationNumber?: number };

function extractNumber(raw: unknown): number | undefined {
  if (typeof raw === "number") return raw;
  if (raw !== null && typeof raw === "object" && "N" in (raw as object))
    return Number((raw as { N: string }).N);
  return undefined;
}

/**
 * Conditional upsert. Returns:
 *   "written"               — new record or strictly newer updatedAt (caller must assign a sequence number)
 *   { kind:"noop", ... }   — equal updatedAt re-upload; stored record is untouched.
 *                            observationNumber is the stored value if already set, or undefined if a
 *                            prior setObservationNumber failed and needs repair.
 *   "stale"                 — incoming updatedAt is older than stored; rejected
 *
 * Condition is strict (< not <=) so equal-updatedAt re-puts do not overwrite the stored
 * observationNumber.  ReturnValuesOnConditionCheckFailure surfaces the old item so we can
 * distinguish noop from stale and read back the existing number, without a GetItem round-trip.
 */
export async function putObservation(
  doc: DynamoDBDocumentClient,
  item: StoredObservation,
): Promise<PutResult> {
  try {
    await doc.send(
      new PutCommand({
        TableName: TABLE,
        Item: item,
        ConditionExpression: "attribute_not_exists(sk) OR updatedAt < :u",
        ExpressionAttributeValues: { ":u": item.updatedAt },
        ReturnValuesOnConditionCheckFailure: "ALL_OLD",
      }),
    );
    return "written";
  } catch (err) {
    if (err instanceof Error && err.name === "ConditionalCheckFailedException") {
      // DynamoDB returns the stored item either already unmarshalled (DocumentClient middleware)
      // or in AttributeValue format {N:"…"}; extractNumber handles both.
      const rawItem = (err as unknown as { Item?: Record<string, unknown> }).Item;
      const storedUpdatedAt = extractNumber(rawItem?.updatedAt);
      if (storedUpdatedAt !== undefined && storedUpdatedAt === item.updatedAt) {
        return { kind: "noop", observationNumber: extractNumber(rawItem?.observationNumber) };
      }
      return "stale";
    }
    throw err;
  }
}

/**
 * Stamp observationNumber onto a stored item, but only if it would raise the existing value.
 * Silently ignores ConditionalCheckFailedException — a concurrent write already set a higher number;
 * the skipped number is a gap (not corruption), which is explicitly allowed by the design.
 */
export async function setObservationNumber(
  doc: DynamoDBDocumentClient,
  pk: string,
  sk: string,
  n: number,
): Promise<void> {
  try {
    await doc.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: { pk, sk },
        UpdateExpression: "SET observationNumber = :n",
        ConditionExpression: "attribute_not_exists(observationNumber) OR observationNumber < :n",
        ExpressionAttributeValues: { ":n": n },
      }),
    );
  } catch (err) {
    if (err instanceof Error && err.name === "ConditionalCheckFailedException") return;
    throw err;
  }
}

export interface ChangesPage {
  items: StoredObservation[];
  hasMore: boolean;
}

/** Records in scope with serverUpdatedAt > since, ascending (legacy cursor path). */
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

/** Records in scope with observationNumber > hwm, ascending (HWM-primary path). */
export async function queryByNumber(
  doc: DynamoDBDocumentClient,
  scope: string,
  hwm: number,
  limit: number,
): Promise<ChangesPage> {
  const res = await doc.send(
    new QueryCommand({
      TableName: TABLE,
      IndexName: OBS_NUMBER_INDEX,
      KeyConditionExpression: "pk = :pk AND observationNumber > :hwm",
      ExpressionAttributeValues: { ":pk": scope, ":hwm": hwm },
      Limit: limit,
      ScanIndexForward: true,
    }),
  );
  return {
    items: (res.Items ?? []) as StoredObservation[],
    hasMore: res.LastEvaluatedKey !== undefined,
  };
}
