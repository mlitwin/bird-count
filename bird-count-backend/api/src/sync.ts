import type { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import type {
  ObservationRecordDTO,
  SyncRequest,
  SyncResponse,
} from "./generated/types.js";
import {
  putObservation,
  queryChanges,
  queryByNumber,
  setObservationNumber,
  type StoredObservation,
} from "./dynamo.js";
import { valkeyClient, tripSeqKey, guardedIncr } from "./valkey.js";

export const SCOPE = "shared"; // v1: one shared pool; later "trip#<uuid>" / "user#<sub>"
const PULL_LIMIT = 200;

export class SeqUnavailableError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = "SeqUnavailableError";
  }
}

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
  // Explicitly exclude observationNumber — it is server-assigned only.
  // Any client-supplied value is ignored here; the write path sets it via INCR + UpdateItem.
  const { observationNumber: _clientSupplied, ...rest } = o;
  return {
    ...rest,
    pk: SCOPE,
    sk: `obs#${o.id}`,
    observer: rest.observer ?? "",
    status: rest.status ?? "completed",
    updatedAt: effectiveUpdatedAt(o),
    observerSub,
    serverUpdatedAt,
    createdAt: Date.now(),
    schemaVersion,
  };
}

export function toWire(item: StoredObservation): ObservationRecordDTO {
  const { pk, sk, observerSub, serverUpdatedAt, createdAt, schemaVersion, ...wire } = item;
  return wire;
}

export interface PullResult {
  changes: ObservationRecordDTO[];
  cursor: string;
  hasMore: boolean;
  tripSequenceHighWater?: number;
}

/**
 * Pull a page of changes.
 *
 * When hwm is present: HWM-primary path — queries gsi_observationNumber in ascending order.
 * Otherwise: legacy timestamp-cursor path (clients that do not yet send the HWM field).
 */
export async function pull(
  doc: DynamoDBDocumentClient,
  cursor: string | undefined,
  hwm: number | undefined,
  limit = PULL_LIMIT,
): Promise<PullResult> {
  if (hwm !== undefined) {
    const page = await queryByNumber(doc, SCOPE, hwm, limit);
    let maxSeen = hwm;
    for (const item of page.items) {
      if ((item.observationNumber ?? 0) > maxSeen) maxSeen = item.observationNumber!;
    }
    // Fetch tripSequenceHighWater from Valkey for the client's catch-up check.
    let tripSequenceHighWater: number | undefined;
    try {
      const raw = await valkeyClient().get(tripSeqKey(SCOPE));
      if (raw !== null) tripSequenceHighWater = Number(raw);
    } catch {
      // Non-fatal: omit the field rather than failing the pull.
    }
    return {
      changes: page.items.map(toWire),
      cursor: String(maxSeen),
      hasMore: page.hasMore,
      tripSequenceHighWater,
    };
  }

  // Legacy timestamp-cursor pull (unchanged).
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
  const valkey = valkeyClient();
  const seqKey = tripSeqKey(SCOPE);

  const applied: SyncResponse["applied"] = [];
  // Unique, increasing serverUpdatedAt within the batch so a page boundary
  // can never split records sharing a millisecond.
  let stamp = Date.now();
  for (const change of request.changes) {
    stamp = Math.max(Date.now(), stamp + 1);
    const stored = toStored(change, observerSub, stamp, request.schemaVersion);

    const putResult = await putObservation(doc, stored);

    if (putResult === "written") {
      // Genuine new record or additive edit: assign a fresh sequence number.
      // INCR before UpdateItem; if UpdateItem fails the number is burned (gap, not corruption).
      const n = await guardedIncr(valkey, seqKey);
      if (n === -1) throw new SeqUnavailableError("sequence counter not seeded");
      await setObservationNumber(doc, stored.pk, stored.sk, n);
      applied.push({ id: change.id, result: "applied", observationNumber: n });
    } else if (putResult === "noop") {
      // Equal-updatedAt re-upload (e.g. recovery sync). The stored record is unchanged;
      // do not INCR so the ledger is not renumbered on recovery.
      applied.push({ id: change.id, result: "applied" });
    } else {
      applied.push({ id: change.id, result: "stale" });
    }
  }

  // Pull runs after push. Return the pull page's cursor untouched so this device's
  // own rows are part of the delta and the cursor advances once pagination drains them.
  const hwm = request.serverSyncedObservationNumberHWM;
  const pulled = await pull(doc, request.cursor, hwm);

  return {
    serverTime,
    cursor: pulled.cursor,
    applied,
    changes: pulled.changes,
    hasMore: pulled.hasMore,
    tripSequenceHighWater: pulled.tripSequenceHighWater,
  };
}
