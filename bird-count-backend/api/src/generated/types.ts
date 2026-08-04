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
  /**
   * Strictly increasing, server-assigned sequence number scoped to the trip. Reassigned on every accepted write (append or edit). Absent on legacy records that predate this feature. Clients must treat this field as read-only and must not upload it.
   */
  observationNumber?: number;
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
   * Highest observationNumber the client has pulled from the server (excludes P2P-only records). When present, the server pulls all records with observationNumber greater than this in ascending order. 0 or absent means the client has pulled nothing via the number-ordered path; the server falls back to the cursor-based pull.
   */
  serverSyncedObservationNumberHWM?: number;
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
    /**
     * Server-assigned sequence number for this write. Present only when result is "applied".
     */
    observationNumber?: number;
  }[];
  changes: ObservationRecordDTO[];
  hasMore: boolean;
  /**
   * Current value of the trip's sequence counter (the highest observationNumber assigned so far). Not a count of live observations — burned numbers and superseded record versions mean this can exceed the number of live records. Clients compare against their serverSyncedObservationNumberHWM to know when they are fully caught up.
   */
  tripSequenceHighWater?: number;
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
