import Foundation
import Network
import UIKit

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
    /// Path is satisfied and not expensive (wifi, not cellular/hotspot).
    public private(set) var isOnWifi = false

    /// User preference: sync automatically (on wifi, when signed in).
    public var autoSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncEnabled, forKey: Self.autoSyncKey)
            if autoSyncEnabled { requestSync(after: Self.triggerDebounce) }
        }
    }

    public let auth: CloudAuthService

    private static let pushChunkSize = 100 // sync.schema.json maxItems
    private static let cursorRewindMs: Int64 = 5000
    private static let lastSyncKey = "CloudLastSyncDate"
    private static let clientIdKey = "CloudClientId"
    private static let autoSyncKey = "CloudAutoSyncEnabled"
    /// Wifi-restored / foregrounded: sync soon.
    static let triggerDebounce: TimeInterval = 3
    /// After a local mutation: let a counting session settle first.
    static let mutationDebounce: TimeInterval = 30

    private var pathMonitor: NWPathMonitor?
    private var pendingSyncTask: Task<Void, Never>?
    private weak var autoSyncStore: ObservationStore?
    private var dirtyObserver: NSObjectProtocol?

    public init(auth: CloudAuthService) {
        self.auth = auth
        autoSyncEnabled = UserDefaults.standard.object(forKey: Self.autoSyncKey) as? Bool ?? true
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

    // MARK: Auto sync

    /// Start the auto-sync triggers: wifi restoration (NWPathMonitor) and
    /// local mutations (store notification, long debounce). The foreground
    /// trigger calls requestSync from the scenePhase observer in the app.
    public func activateAutoSync(store: ObservationStore) {
        autoSyncStore = store

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let onWifi = path.status == .satisfied && !path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cameOnline = onWifi && !self.isOnWifi
                self.isOnWifi = onWifi
                if cameOnline { self.requestSync(after: Self.triggerDebounce) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "org.antoninus.birdcount.pathmonitor"))
        pathMonitor = monitor

        dirtyObserver = NotificationCenter.default.addObserver(
            forName: ObservationStore.didMarkDirtyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestSync(after: Self.mutationDebounce)
            }
        }
    }

    /// Debounced sync: coalesces bursts of triggers; a shorter-delay request
    /// supersedes a pending longer one. No-op unless signed in, auto-sync is
    /// on, and we are on wifi at fire time.
    public func requestSync(after delay: TimeInterval = 3) {
        guard autoSyncEnabled, auth.isSignedIn else { return }
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, let store = self.autoSyncStore else { return }
            guard self.autoSyncEnabled, self.auth.isSignedIn, self.isOnWifi, !self.isSyncing else { return }
            await self.syncNow(store: store)
        }
    }

    /// Recovery sync: forget the cursor so the next sync re-uploads every
    /// local record and re-pulls the entire cloud pool from zero. Both sides
    /// merge idempotently, so this is always safe — just chatty. For devices
    /// whose cursor has advanced past records they never received.
    public func resyncAll(store: ObservationStore) async {
        guard !isSyncing else { return }
        store.cloudSyncCursor = nil
        await syncNow(store: store)
    }

    public func syncNow(store: ObservationStore) async {
        guard auth.isSignedIn else {
            state = .failure("Sign in to sync")
            return
        }
        guard !isSyncing else { return }
        state = .syncing("Preparing…")

        // Keep the process alive if the user backgrounds the app mid-sync
        // (~30s grace). An interrupted sync is safe regardless — dirty ids
        // clear only on server ack — this just lets sessions finish cleanly.
        beginBackgroundAssertion()
        defer { endBackgroundAssertion() }

        do {
            let api = CloudAPIClient(auth: auth)

            // Never synced: everything this device has needs to upload.
            if store.cloudSyncCursor == nil {
                store.markAllDirty()
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
            // A failed token refresh signs the user out (see CloudAuthService);
            // surface that as a re-auth prompt rather than a raw error.
            if !auth.isSignedIn {
                state = .failure("Session expired — sign in again to sync")
            } else {
                state = .failure(error.localizedDescription)
            }
        }
    }

    // MARK: Background task assertion

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private func beginBackgroundAssertion() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "CloudSync") { [weak self] in
            // Expiration handler: the system requires endBackgroundTask
            // before it force-ends the assertion.
            Task { @MainActor [weak self] in self?.endBackgroundAssertion() }
        }
    }

    private func endBackgroundAssertion() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
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
