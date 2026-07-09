import Foundation
import Observation

/// A device the user has paired with for automatic P2P sync.
public struct PairedPeer: Codable, Equatable, Identifiable {
    /// Stable identity id: the fingerprint of the peer's public key.
    public let id: UUID
    public var displayName: String
    /// The peer's identity public key, captured at pairing time. Auto-sync
    /// only proceeds when a connection proves possession of this exact key.
    public let publicKey: Data
    public let pairedAt: Date
    /// Records queued for delivery to this peer; cleared on confirmed send.
    /// Same store-and-forward role as the cloud's dirtyIds, but per peer.
    public var pendingIds: Set<UUID>
}

/// Persistent list of paired devices plus a per-peer outbound queue.
///
/// Queueing mirrors the cloud dirty-tracking design: pairing marks every
/// existing record pending (the peer starts from zero, like a first cloud
/// sync), and any subsequently created or updated record — local edit, cloud
/// pull, or P2P import — is queued for every paired peer via the store's
/// didChangeRecords notification. Records a peer sent us are echoed back once
/// on the next sync; the idempotent merge skips them and, because skipped
/// duplicates are not re-queued, the echo settles immediately.
@Observable
public final class PairedPeersStore {
    public private(set) var peers: [PairedPeer] = []

    private let defaults: UserDefaults
    private static let storageKey = "PairedPeers_v1"
    private var changeObserver: NSObjectProtocol?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    /// Start queueing record changes for paired peers. Call once at app start.
    public func activate(store: ObservationStore) {
        guard changeObserver == nil else { return }
        // queue nil = synchronous delivery on the posting thread. Store
        // mutations happen on the main thread, so the queue update lands
        // before anything can snapshot a stale pending set.
        changeObserver = NotificationCenter.default.addObserver(
            forName: ObservationStore.didChangeRecordsNotification,
            object: store,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let ids = notification.userInfo?[ObservationStore.changedIdsUserInfoKey] as? [UUID]
            else { return }
            self.addPending(ids)
        }
    }

    // MARK: - Pairing

    public func isPaired(_ id: UUID) -> Bool {
        peers.contains { $0.id == id }
    }

    public func peer(for id: UUID) -> PairedPeer? {
        peers.first { $0.id == id }
    }

    /// Pair a verified peer. Everything this device currently has is queued
    /// for them (the P2P analog of the cloud's first-sync markAllDirty).
    public func pair(id: UUID, displayName: String, publicKey: Data, store: ObservationStore) {
        guard !isPaired(id) else { return }
        peers.append(PairedPeer(
            id: id,
            displayName: displayName,
            publicKey: publicKey,
            pairedAt: Date(),
            pendingIds: Set(store.allRecordIds)
        ))
        persist()
    }

    public func unpair(_ id: UUID) {
        peers.removeAll { $0.id == id }
        persist()
    }

    /// Refresh the stored name when the peer's hello shows a new one.
    public func updateDisplayName(_ displayName: String, for id: UUID) {
        guard let index = peers.firstIndex(where: { $0.id == id }),
              peers[index].displayName != displayName else { return }
        peers[index].displayName = displayName
        persist()
    }

    // MARK: - Outbound queues

    /// Queue changed records for every paired peer. The source peer of a P2P
    /// import is intentionally not excluded — see the type comment.
    public func addPending(_ ids: some Sequence<UUID>) {
        guard !peers.isEmpty else { return }
        var changed = false
        for index in peers.indices {
            let before = peers[index].pendingIds.count
            peers[index].pendingIds.formUnion(ids)
            changed = changed || peers[index].pendingIds.count != before
        }
        if changed { persist() }
    }

    public func pendingIds(for id: UUID) -> Set<UUID> {
        peer(for: id)?.pendingIds ?? []
    }

    /// Confirm delivery: remove sent ids from the peer's queue — but only
    /// those whose record is unchanged since the send snapshot. A record
    /// edited while the transfer was in flight keeps its queue slot so the
    /// newer version goes out next time.
    public func clearPending(for peerId: UUID, sent: [UUID: Date], store: ObservationStore) {
        guard let index = peers.firstIndex(where: { $0.id == peerId }), !sent.isEmpty else { return }
        // One snapshot pass instead of a per-id tree walk: after a first
        // pairing sync `sent` is the whole ledger, and per-id lookups made
        // this quadratic on the main thread.
        let current = store.updatedAtById()
        let deliverable = sent.filter { id, sentVersion in
            current[id] == sentVersion
        }
        peers[index].pendingIds.subtract(deliverable.keys)
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([PairedPeer].self, from: data)
        else { return }
        peers = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(peers) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
