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
  type PutResult,
  type StoredObservation,
} from "./dynamo.js";
import { tripSeqKey, getSeq, guardedIncr } from "./seq.js";

export const SCOPE = "shared"; // v1: one shared pool; later "trip#<uuid>" / "user#<sub>"
const PULL_LIMIT = 200;
const MAX_RENUMBER_ATTEMPTS = 5;

/**
 * Settle horizon for pulls (ms). A record allocated its number (or its serverUpdatedAt stamp)
 * less than this long ago is held back, and the cursor stops before it. Writes from concurrent
 * syncs can land, and propagate to the GSIs, out of allocation order; a reader that advanced
 * past a later number would otherwise skip the earlier one forever. Holding back the recent
 * tail closes that unless a single write takes longer than the horizon to land and propagate.
 * See docs/hwm-gsi-race-analysis.md. Read per call so tests can override it.
 */
export function pullSettleMs(): number {
  return Number(process.env.PULL_SETTLE_MS ?? 10_000);
}

/** Leading run of items whose stamp is at or before horizon; stops at the first unsettled one. */
export function settledPrefix<T>(items: T[], stampOf: (item: T) => number, horizon: number): T[] {
  const end = items.findIndex((item) => stampOf(item) > horizon);
  return end === -1 ? items : items.slice(0, end);
}

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
  observationNumber: number,
  numberedAt: number,
): StoredObservation {
  // Client-supplied observationNumber is ignored — it is server-assigned only.
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
    observationNumber,
    numberedAt,
  };
}

export function toWire(item: StoredObservation): ObservationRecordDTO {
  const { pk, sk, observerSub, serverUpdatedAt, createdAt, schemaVersion, numberedAt, ...wire } =
    item;
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
 * Both stop at the settle horizon (pullSettleMs): unsettled records are omitted, the cursor
 * does not pass them, and hasMore is false — the next pull picks them up once settled.
 * Clients advance their HWM from the returned records, so omitting them is what holds it back.
 */
export async function pull(
  doc: DynamoDBDocumentClient,
  cursor: string | undefined,
  hwm: number | undefined,
  limit = PULL_LIMIT,
): Promise<PullResult> {
  const horizon = Date.now() - pullSettleMs();
  if (hwm !== undefined) {
    const page = await queryByNumber(doc, SCOPE, hwm, limit);
    // Items numbered by the pre-numberedAt two-phase path count as settled.
    const items = settledPrefix(page.items, (i) => i.numberedAt ?? 0, horizon);
    let maxSeen = hwm;
    for (const item of items) {
      if ((item.observationNumber ?? 0) > maxSeen) maxSeen = item.observationNumber!;
    }
    // Fetch tripSequenceHighWater from the seq counter for the client's catch-up check.
    let tripSequenceHighWater: number | undefined;
    try {
      tripSequenceHighWater = (await getSeq(doc, tripSeqKey(SCOPE))) ?? undefined;
    } catch {
      // Non-fatal: omit the field rather than failing the pull.
    }
    return {
      changes: items.map(toWire),
      cursor: String(maxSeen),
      hasMore: page.hasMore && items.length === page.items.length,
      tripSequenceHighWater,
    };
  }

  // Legacy timestamp-cursor pull.
  const since = Number(cursor ?? "0") || 0;
  const page = await queryChanges(doc, SCOPE, since, limit);
  const items = settledPrefix(page.items, (i) => i.serverUpdatedAt, horizon);
  let maxSeen = since;
  for (const item of items) {
    if (item.serverUpdatedAt > maxSeen) maxSeen = item.serverUpdatedAt;
  }
  return {
    changes: items.map(toWire),
    cursor: String(maxSeen),
    hasMore: page.hasMore && items.length === page.items.length,
  };
}

export async function sync(
  doc: DynamoDBDocumentClient,
  request: SyncRequest,
  observerSub: string,
): Promise<SyncResponse> {
  const serverTime = Date.now();
  const seqKey = tripSeqKey(SCOPE);

  const allocate = async (): Promise<{ n: number; numberedAt: number }> => {
    const n = await guardedIncr(doc, seqKey);
    if (n === -1) throw new SeqUnavailableError("sequence counter not seeded");
    return { n, numberedAt: Date.now() };
  };

  const applied: SyncResponse["applied"] = [];
  // Unique, increasing serverUpdatedAt within the batch so a page boundary
  // can never split records sharing a millisecond.
  let stamp = Date.now();
  for (const change of request.changes) {
    stamp = Math.max(Date.now(), stamp + 1);

    // Allocate first and write the number with the record (single-phase), so the item is
    // never visible without its number. A stale or noop put burns the number (a gap, which
    // readers tolerate). "renumber" means a concurrent newer-numbered write landed first.
    let putResult: PutResult;
    let alloc: { n: number; numberedAt: number };
    let attempts = 0;
    do {
      if (++attempts > MAX_RENUMBER_ATTEMPTS) {
        throw new Error(`renumber did not converge for ${change.id}`);
      }
      alloc = await allocate();
      const stored = toStored(
        change, observerSub, stamp, request.schemaVersion, alloc.n, alloc.numberedAt,
      );
      putResult = await putObservation(doc, stored);
    } while (putResult === "renumber");

    if (putResult === "written") {
      applied.push({ id: change.id, result: "applied", observationNumber: alloc.n });
    } else if (putResult === "stale") {
      applied.push({ id: change.id, result: "stale" });
    } else if (putResult.observationNumber !== undefined) {
      // Equal-updatedAt re-upload (e.g. recovery sync) of a numbered record: return the
      // known number so the client doesn't need a pull round-trip.
      applied.push({ id: change.id, result: "applied", observationNumber: putResult.observationNumber });
    } else {
      // Legacy item whose two-phase number stamp failed: repair with the number just allocated.
      await setObservationNumber(doc, SCOPE, `obs#${change.id}`, alloc.n, alloc.numberedAt);
      applied.push({ id: change.id, result: "applied", observationNumber: alloc.n });
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
