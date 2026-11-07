import { GetCommand, UpdateCommand, type DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";

// Per-trip observationNumber counter: one item per key in its own table, kept
// out of the append-only ledger table. Single-item conditional updates are
// atomic and serialized, so this is the system's one race-free sequence.

if (!process.env.SEQ_TABLE_NAME) {
  throw new Error("SEQ_TABLE_NAME environment variable is not set");
}
const SEQ_TABLE = process.env.SEQ_TABLE_NAME;

export function tripSeqKey(trip: string): string {
  return `trip:${trip}:seq`;
}

function isConditionFailure(err: unknown): boolean {
  return err instanceof Error && err.name === "ConditionalCheckFailedException";
}

/** Current counter value (strongly consistent), or null if the key was never seeded. */
export async function getSeq(doc: DynamoDBDocumentClient, key: string): Promise<number | null> {
  const res = await doc.send(
    new GetCommand({ TableName: SEQ_TABLE, Key: { pk: key }, ConsistentRead: true }),
  );
  return typeof res.Item?.seq === "number" ? res.Item.seq : null;
}

/** Increments key only if it already exists. Returns new value, or -1 if key is absent. */
export async function guardedIncr(doc: DynamoDBDocumentClient, key: string): Promise<number> {
  try {
    const res = await doc.send(
      new UpdateCommand({
        TableName: SEQ_TABLE,
        Key: { pk: key },
        UpdateExpression: "ADD seq :one",
        ConditionExpression: "attribute_exists(seq)",
        ExpressionAttributeValues: { ":one": 1 },
        ReturnValues: "UPDATED_NEW",
      }),
    );
    return res.Attributes!.seq as number;
  } catch (err) {
    if (isConditionFailure(err)) return -1;
    throw err;
  }
}

/** Sets key to value only when value > current (raise-only). Returns true if the write ran. */
export async function raiseOnlySet(
  doc: DynamoDBDocumentClient,
  key: string,
  value: number,
): Promise<boolean> {
  try {
    await doc.send(
      new UpdateCommand({
        TableName: SEQ_TABLE,
        Key: { pk: key },
        UpdateExpression: "SET seq = :v",
        ConditionExpression: "attribute_not_exists(seq) OR seq < :v",
        ExpressionAttributeValues: { ":v": value },
      }),
    );
    return true;
  } catch (err) {
    if (isConditionFailure(err)) return false;
    throw err;
  }
}
