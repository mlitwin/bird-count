// Materialized ledger + server-side aggregation for the query layer
// (GET /v1/summary, GET /v1/observations/query).
//
// The whole scope is held in module memory: a cold start pages the full
// partition off the changes GSI (small at this data volume); warm instances
// catch up with one cheap strictly-after-cursor delta Query per request.
// If volume ever outgrows this, swap the internals for date/parent indexes —
// the wire contract doesn't expose the strategy.
//
// Aggregation semantics mirror iOS ObservationStoreCache.countsInRange:
// the range filter applies to top-level records only (interval overlap);
// an in-range root contributes its entire recursive subtree; orphans are
// excluded; species with non-positive totals are dropped. Locked by
// bird-count-schema/fixtures/derived/summary-cases.json.

import type { DynamoDBDocumentClient } from "@aws-sdk/lib-dynamodb";
import { queryChanges, type StoredObservation } from "./dynamo.js";
import type {
  ObservationsQueryResponse,
  SummaryResponse,
  SummarySpeciesRow,
} from "./generated/types.js";
import { toWire } from "./sync.js";

const PAGE_LIMIT = 200;

export interface LedgerCache {
  records: Map<string, StoredObservation>;
  cursor: number;
}

const caches = new Map<string, LedgerCache>();

/** Catch the in-memory ledger up with the changes GSI and return it. */
export async function refreshLedger(
  doc: DynamoDBDocumentClient,
  scope: string,
): Promise<LedgerCache> {
  let cache = caches.get(scope);
  if (!cache) {
    cache = { records: new Map(), cursor: 0 };
    caches.set(scope, cache);
  }
  for (;;) {
    const page = await queryChanges(doc, scope, cache.cursor, PAGE_LIMIT);
    for (const item of page.items) {
      cache.records.set(item.id, item); // re-put (LWW backfill) replaces
      if (item.serverUpdatedAt > cache.cursor) cache.cursor = item.serverUpdatedAt;
    }
    if (!page.hasMore) break;
  }
  return cache;
}

/** Tests only: drop all cached ledger state. */
export function resetLedgerCache(): void {
  caches.clear();
}

// -- Aggregation (pure; unit-testable against the shared fixtures) --

/** The subset of the DTO the ledger math needs. */
export interface RecordLike {
  id: string;
  parentId?: string;
  taxonId: string;
  begin: string;
  end: string;
  count: number;
}

interface TreeIndex<T extends RecordLike> {
  roots: T[];
  childrenByParent: Map<string, T[]>;
}

function buildTree<T extends RecordLike>(records: Iterable<T>): TreeIndex<T> {
  const all = [...records];
  const ids = new Set(all.map((r) => r.id));
  const roots: T[] = [];
  const childrenByParent = new Map<string, T[]>();
  for (const r of all) {
    if (!r.parentId) {
      roots.push(r);
    } else if (ids.has(r.parentId)) {
      let siblings = childrenByParent.get(r.parentId);
      if (!siblings) {
        siblings = [];
        childrenByParent.set(r.parentId, siblings);
      }
      siblings.push(r);
    }
    // orphan (parentId set, parent absent): excluded, same as iOS/web
  }
  return { roots, childrenByParent };
}

/** Interval overlap on top-level records; passing roots carry their subtree. */
function inRangeRoots<T extends RecordLike>(
  roots: T[],
  beginMs: number,
  endMs: number,
): T[] {
  return roots.filter(
    (r) => Date.parse(r.end) >= beginMs && Date.parse(r.begin) <= endMs,
  );
}

export function computeSummary(
  records: Iterable<RecordLike>,
  begin: string,
  end: string,
): SummaryResponse {
  const { roots, childrenByParent } = buildTree(records);
  const perTaxon = new Map<string, { count: number; lastMs: number; lastIso: string }>();

  function process(r: RecordLike): void {
    let entry = perTaxon.get(r.taxonId);
    if (!entry) {
      entry = { count: 0, lastMs: -Infinity, lastIso: r.end };
      perTaxon.set(r.taxonId, entry);
    }
    entry.count += r.count;
    const endMs = Date.parse(r.end);
    if (endMs > entry.lastMs) {
      entry.lastMs = endMs;
      entry.lastIso = r.end;
    }
    for (const child of childrenByParent.get(r.id) ?? []) process(child);
  }

  for (const root of inRangeRoots(roots, Date.parse(begin), Date.parse(end))) {
    process(root);
  }

  const species: SummarySpeciesRow[] = [...perTaxon.entries()]
    .filter(([, e]) => e.count > 0)
    .map(([taxonId, e]) => ({ taxonId, count: e.count, lastObservedAt: e.lastIso }))
    .sort((a, b) => b.count - a.count || (a.taxonId < b.taxonId ? -1 : 1));

  return {
    begin,
    end,
    totalIndividuals: species.reduce((sum, s) => sum + s.count, 0),
    totalSpecies: species.length,
    species,
  };
}

// -- Paged observation query --

export interface QueryParams {
  begin: string;
  end: string;
  taxonId?: string;
  limit: number;
  cursor?: string;
}

interface CursorPos {
  b: number; // beginMs of the last-returned item
  i: string; // its id (tiebreak)
}

function encodeCursor(pos: CursorPos): string {
  return Buffer.from(JSON.stringify(pos)).toString("base64url");
}

function decodeCursor(cursor: string): CursorPos | undefined {
  try {
    const pos = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"));
    if (typeof pos.b === "number" && typeof pos.i === "string") return pos;
  } catch {
    /* fall through */
  }
  return undefined;
}

export function queryObservations(
  records: Iterable<StoredObservation>,
  params: QueryParams,
): ObservationsQueryResponse {
  const { roots, childrenByParent } = buildTree([...records]);

  function netCount(r: RecordLike): number {
    let total = r.count;
    for (const child of childrenByParent.get(r.id) ?? []) total += netCount(child);
    return total;
  }

  // Newest begin first; id ascending as a deterministic tiebreak.
  let matches = inRangeRoots(roots, Date.parse(params.begin), Date.parse(params.end))
    .filter((r) => !params.taxonId || r.taxonId === params.taxonId)
    .sort((a, b) => Date.parse(b.begin) - Date.parse(a.begin) || (a.id < b.id ? -1 : 1));

  const pos = params.cursor ? decodeCursor(params.cursor) : undefined;
  if (pos) {
    matches = matches.filter(
      (r) => Date.parse(r.begin) < pos.b || (Date.parse(r.begin) === pos.b && r.id > pos.i),
    );
  }

  const page = matches.slice(0, params.limit);
  const hasMore = matches.length > page.length;
  const last = page[page.length - 1];

  return {
    items: page.map((r) => ({ record: toWire(r), netCount: netCount(r) })),
    cursor: hasMore && last ? encodeCursor({ b: Date.parse(last.begin), i: last.id }) : "",
    hasMore,
  };
}

// -- Request validation (shared by both routes) --

/** Returns an error string for bad range params, or undefined when valid. */
export function validateRange(
  begin: string | undefined,
  end: string | undefined,
): string | undefined {
  if (!begin || !end) return "begin and end query parameters are required (ISO 8601)";
  const beginMs = Date.parse(begin);
  const endMs = Date.parse(end);
  if (Number.isNaN(beginMs)) return `begin is not a valid ISO 8601 date: ${begin}`;
  if (Number.isNaN(endMs)) return `end is not a valid ISO 8601 date: ${end}`;
  if (beginMs > endMs) return "begin must be <= end";
  return undefined;
}
