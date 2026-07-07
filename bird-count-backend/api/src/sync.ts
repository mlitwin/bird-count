import type { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type {
  ObservationRecordDTO,
  SyncRequest,
  SyncResponse,
} from "./generated/types.js";
import { putObservation, queryChanges, type StoredObservation } from "./dynamo.js";

const SCOPE = "shared"; // v1: one shared pool; later "trip#<uuid>" / "user#<sub>"
const PULL_LIMIT = 200;

/** Missing on legacy v1 records; the backfill rule matches the iOS decoder. */
function effectiveUpdatedAt(o: ObservationRecordDTO): number {
  return o.updatedAt ?? Date.parse(o.end);
}

function toStored(
  o: ObservationRecordDTO,
  observerSub: string,
  serverUpdatedAt: number,
  schemaVersion: number,
): StoredObservation {
  return {
    ...o,
    pk: SCOPE,
    sk: `obs#${o.id}`,
    observer: o.observer ?? "",
    status: o.status ?? "completed",
    updatedAt: effectiveUpdatedAt(o),
    observerSub,
    serverUpdatedAt,
    createdAt: Date.now(),
    schemaVersion,
  };
}

function toWire(item: StoredObservation): ObservationRecordDTO {
  const { pk, sk, observerSub, serverUpdatedAt, createdAt, schemaVersion, ...wire } = item;
  return wire;
}

export interface PullResult {
  changes: ObservationRecordDTO[];
  cursor: string;
  hasMore: boolean;
}

/**
 * Strictly-after-cursor delta. The query is exclusive so pagination always
 * advances; the clock-skew overlap is the CLIENT's job — rewind the stored
 * cursor ~5s when starting a sync session (apply is idempotent, so
 * re-delivery is harmless). A server-side overlap would break pagination
 * whenever more records fall in the window than the page limit.
 */
export async function pull(
  doc: DynamoDBDocumentClient,
  cursor: string | undefined,
  limit = PULL_LIMIT,
): Promise<PullResult> {
  const since = Number(cursor ?? "0") || 0;
  const page = await queryChanges(doc, SCOPE, since, limit);
  let maxSeen = since;
  for (const item of page.items) {
    if (item.serverUpdatedAt > maxSeen) maxSeen = item.serverUpdatedAt;
  }
  return {
    changes: page.items.map(toWire),
    cursor: String(maxSeen),
    hasMore: page.hasMore,
  };
}

export async function sync(
  doc: DynamoDBDocumentClient,
  request: SyncRequest,
  observerSub: string,
): Promise<SyncResponse> {
  const serverTime = Date.now();

  const applied: SyncResponse["applied"] = [];
  let maxPushed = 0;
  // Unique, increasing serverUpdatedAt within the batch so a page boundary
  // can never split records sharing a millisecond.
  let stamp = Date.now();
  for (const change of request.changes) {
    stamp = Math.max(Date.now(), stamp + 1);
    const ok = await putObservation(
      doc,
      toStored(change, observerSub, stamp, request.schemaVersion),
    );
    applied.push({ id: change.id, result: ok ? "applied" : "stale" });
    if (ok && stamp > maxPushed) maxPushed = stamp;
  }

  const pulled = await pull(doc, request.cursor);
  const cursor = String(Math.max(Number(pulled.cursor), maxPushed));

  return {
    serverTime,
    cursor,
    applied,
    changes: pulled.changes,
    hasMore: pulled.hasMore,
  };
}
