/* eslint-disable */
/**
 * GENERATED FILE — do not edit.
 * Source: bird-count-schema/schemas/ (version 2)
 * Regenerate: node bird-count-schema/scripts/generate-ts.mjs
 */
/**
 * Wire shape of one observation ledger entry (mirrors ObservationRecordDTO.swift). Records are immutable after creation except the location/status backfill on the originating device. Adjustment children carry a (possibly negative) count and a parentId; the ledger total is the recursive sum.
 */
export interface ObservationRecordDTO {
  id: string;
  parentId?: string;
  taxonId: string;
  begin: string;
  end: string;
  /**
   * May be negative: adjustment children zero out or reduce a parent's recursive total
   */
  count: number;
  location?: ObservationLocation;
  observer?: string;
  status?: 'pending' | 'completed';
  /**
   * Client-set ms epoch; whole-record LWW for the location backfill. Absent on legacy v1 records — consumers backfill with epoch-ms of `end` (same rule as the iOS decoder, convergent across devices).
   */
  updatedAt?: number;
}
/**
 * Location where an observation was recorded (mirrors ObservationLocation.swift)
 */
export interface ObservationLocation {
  latitude: number;
  longitude: number;
  /**
   * Meters; negative means invalid (matches CoreLocation semantics)
   */
  horizontalAccuracy: number;
  timestamp: string;
  altitude?: number;
  verticalAccuracy?: number;
  name?: string;
  notes?: string;
}

/**
 * POST /v1/sync request/response shapes
 */
export type SyncAPI = SyncRequest | SyncResponse;

export interface SyncRequest {
  schemaVersion: number;
  clientId: string;
  /**
   * Max serverUpdatedAt seen by this client, as decimal string; "0" or absent for first sync
   */
  cursor?: string;
  /**
   * @maxItems 100
   */
  changes: ObservationRecordDTO[];
}
/**
 * Wire shape of one observation ledger entry (mirrors ObservationRecordDTO.swift). Records are immutable after creation except the location/status backfill on the originating device. Adjustment children carry a (possibly negative) count and a parentId; the ledger total is the recursive sum.
 */
export interface SyncResponse {
  serverTime: number;
  cursor: string;
  applied: {
    id: string;
    result: 'applied' | 'stale' | 'invalid';
  }[];
  changes: ObservationRecordDTO[];
  hasMore: boolean;
}

/**
 * GET /v1/summary and GET /v1/observations/query response shapes (server-side query layer for the web viewer)
 */
export type QueryAPI = SummaryResponse | ObservationsQueryResponse;

/**
 * Ledger aggregation over [begin, end]. The range filter applies to top-level records only (interval overlap: record.end >= begin && record.begin <= end); an in-range root contributes its entire recursive subtree regardless of child dates; orphans (parentId present, parent absent) are excluded; species with non-positive totals are dropped. species is sorted by count desc, then taxonId asc.
 */
export interface SummaryResponse {
  begin: string;
  end: string;
  totalIndividuals: number;
  totalSpecies: number;
  species: SummarySpeciesRow[];
}
export interface SummarySpeciesRow {
  taxonId: string;
  count: number;
  /**
   * Max record `end` among this taxon's contributing records
   */
  lastObservedAt: string;
}
/**
 * Paged top-level records overlapping [begin, end], newest `begin` first. netCount is the record's recursive subtree total (adjustments applied).
 */
export interface ObservationsQueryResponse {
  items: QueriedObservation[];
  /**
   * Opaque continuation token; empty when hasMore is false
   */
  cursor: string;
  hasMore: boolean;
}
export interface QueriedObservation {
  record: ObservationRecordDTO;
  netCount: number;
}
/**
 * Wire shape of one observation ledger entry (mirrors ObservationRecordDTO.swift). Records are immutable after creation except the location/status backfill on the originating device. Adjustment children carry a (possibly negative) count and a parentId; the ledger total is the recursive sum.
 */
export interface PayloadV2 {
  schemaVersion: number;
  appVersion: string;
  senderDisplayName: string;
  rangeStart: string;
  rangeEnd: string;
  observations: ObservationRecordDTO[];
}
/**
 * Wire shape of one observation ledger entry (mirrors ObservationRecordDTO.swift). Records are immutable after creation except the location/status backfill on the originating device. Adjustment children carry a (possibly negative) count and a parentId; the ledger total is the recursive sum.
 */
