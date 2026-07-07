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
 * P2P sync payload (Bonjour/TCP transport). v2 = observation items may carry updatedAt; receivers accept v1 items and backfill updatedAt from end.
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
