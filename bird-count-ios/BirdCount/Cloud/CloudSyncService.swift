import Foundation

/// Manual cloud sync: gather dirty records -> chunked POST /v1/sync ->
/// LWW-apply pulled changes -> advance cursor -> clear pushed dirty ids.
///
/// Cursor semantics: the server's pull is strictly-after-cursor (so
/// pagination always advances). The clock-skew overlap is OUR job: rewind
/// the stored cursor a few seconds when a sync session starts. Re-delivered
/// records are absorbed by the store's idempotent LWW merge.
@Observable
@MainActor
public final class CloudSyncService {
    public enum SyncState: Equatable {
        case idle
        case syncing(String)
        case failure(String)
    }

    public private(set) var state: SyncState = .idle
    public private(set) var lastSyncDate: Date?
    public private(set) var lastStats: ObservationStore.MergeStatistics?

    public let auth: CloudAuthService

    private static let pushChunkSize = 100 // sync.schema.json maxItems
    private static let cursorRewindMs: Int64 = 5000
    private static let lastSyncKey = "CloudLastSyncDate"
    private static let clientIdKey = "CloudClientId"

    public init(auth: CloudAuthService) {
        self.auth = auth
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    /// Stable per-install id sent as clientId on sync requests.
    private var clientId: String {
        if let existing = UserDefaults.standard.string(forKey: Self.clientIdKey) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: Self.clientIdKey)
        return fresh
    }

    public var isSyncing: Bool {
        if case .syncing = state { return true }
        return false
    }

    public func syncNow(store: ObservationStore) async {
        guard auth.isSignedIn else {
            state = .failure("Sign in to sync")
            return
        }
        guard !isSyncing else { return }
        state = .syncing("Preparing…")

        do {
            let api = CloudAPIClient(auth: auth)

            // Never synced: everything this device has needs to upload.
            if store.cloudSyncCursor == nil {
                for id in store.allRecordIds { store.markDirty(id) }
            }

            // flatDTOs is parents-before-children; keep that order so the
            // server never pages a child ahead of its in-flight parent.
            let dirty = store.dirtyIds
            let toPush = store.flatDTOs().filter { dirty.contains($0.id) }

            var cursor = Self.rewound(store.cloudSyncCursor)
            var merged = ObservationStore.MergeStatistics()

            // Push in chunks; each round trip also pulls a delta page.
            var chunks = stride(from: 0, to: toPush.count, by: Self.pushChunkSize).map {
                Array(toPush[$0..<min($0 + Self.pushChunkSize, toPush.count)])
            }
            if chunks.isEmpty { chunks = [[]] } // pull-only sync

            for (index, chunk) in chunks.enumerated() {
                state = .syncing("Syncing \(index + 1)/\(chunks.count)…")
                let response = try await api.sync(SyncRequestBody(clientId: clientId, cursor: cursor, changes: chunk))
                let acknowledged = response.applied
                    .filter { $0.result == "applied" || $0.result == "stale" }
                    .map { $0.id }
                store.clearDirty(acknowledged)
                accumulate(&merged, store.mergeDTOs(response.changes, markDirty: false))
                cursor = response.cursor

                // Drain remaining delta pages on the last chunk.
                if index == chunks.count - 1 {
                    var hasMore = response.hasMore
                    while hasMore {
                        state = .syncing("Downloading…")
                        let page = try await api.observations(since: cursor)
                        accumulate(&merged, store.mergeDTOs(page.changes, markDirty: false))
                        cursor = page.cursor
                        hasMore = page.hasMore
                    }
                }
            }

            store.cloudSyncCursor = cursor
            lastStats = merged
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncKey)
            state = .idle
        } catch {
            state = .failure(error.localizedDescription)
        }
    }

    private func accumulate(_ total: inout ObservationStore.MergeStatistics, _ new: ObservationStore.MergeStatistics) {
        total.imported += new.imported
        total.updated += new.updated
        total.duplicatesSkipped += new.duplicatesSkipped
        total.orphansHeld = new.orphansHeld
    }

    private static func rewound(_ cursor: String?) -> String {
        guard let cursor, let value = Int64(cursor) else { return "0" }
        return String(max(0, value - cursorRewindMs))
    }
}
