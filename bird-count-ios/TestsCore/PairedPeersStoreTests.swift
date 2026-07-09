import Foundation
import Testing
@testable import BirdCountCore

struct PairedPeersStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suite = "PairedPeersStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func dto(_ id: UUID = UUID(), updatedAt: Date? = nil) -> ObservationRecordDTO {
        let end = Date(timeIntervalSince1970: 1_782_900_000)
        return ObservationRecordDTO(
            id: id, taxonId: "amecro", begin: end, end: end, count: 1,
            observer: "test", updatedAt: updatedAt
        )
    }

    private let key = Data(repeating: 7, count: 32)

    @Test
    func pairingQueuesAllExistingRecords() {
        let store = ObservationStore(testing: true)
        store.addObservation("amecro")
        store.addObservation("norcar")

        let peers = PairedPeersStore(defaults: makeDefaults())
        let peerID = UUID()
        peers.pair(id: peerID, displayName: "Field Phone", publicKey: key, store: store)

        #expect(peers.isPaired(peerID))
        #expect(peers.pendingIds(for: peerID) == Set(store.allRecordIds))
    }

    @Test
    func recordChangesQueueForEveryPairedPeer() {
        let store = ObservationStore(testing: true)
        let peers = PairedPeersStore(defaults: makeDefaults())
        let a = UUID(), b = UUID()
        peers.pair(id: a, displayName: "A", publicKey: key, store: store)
        peers.pair(id: b, displayName: "B", publicKey: key, store: store)
        peers.activate(store: store)

        // Local mutation path: addObservation marks dirty, which posts
        // didChangeRecords.
        store.addObservation("amecro")
        let id = store.allRecordIds[0]
        #expect(peers.pendingIds(for: a).contains(id))
        #expect(peers.pendingIds(for: b).contains(id))

        // Merge path (cloud pull / P2P import) queues too.
        let merged = dto()
        store.mergeDTOs([merged], markDirty: false)
        #expect(peers.pendingIds(for: a).contains(merged.id))
        #expect(peers.pendingIds(for: b).contains(merged.id))
    }

    @Test
    func duplicateMergeDoesNotRequeue() {
        let store = ObservationStore(testing: true)
        let peers = PairedPeersStore(defaults: makeDefaults())
        let record = dto()
        store.mergeDTOs([record], markDirty: false)

        let peerID = UUID()
        peers.pair(id: peerID, displayName: "A", publicKey: key, store: store)
        peers.activate(store: store)
        peers.clearPending(
            for: peerID,
            sent: [record.id: store.updatedAt(for: record.id)!],
            store: store
        )

        // Same version arrives again (the echo case): skipped as duplicate,
        // must not land back in the queue.
        store.mergeDTOs([record], markDirty: false)
        #expect(!peers.pendingIds(for: peerID).contains(record.id))
    }

    @Test
    func clearPendingKeepsRecordEditedDuringTransfer() {
        let store = ObservationStore(testing: true)
        let base = Date(timeIntervalSince1970: 1_782_900_000)
        let record = dto(updatedAt: base)
        store.mergeDTOs([record], markDirty: false)

        let peers = PairedPeersStore(defaults: makeDefaults())
        let peerID = UUID()
        peers.pair(id: peerID, displayName: "A", publicKey: key, store: store)
        peers.activate(store: store)

        // Snapshot what was "sent", then simulate an edit landing while the
        // transfer was in flight (LWW update bumps updatedAt and re-queues).
        let sent = [record.id: base]
        var newer = record
        newer.updatedAt = base.addingTimeInterval(60)
        newer.location = ObservationLocation(latitude: 38.4, longitude: -122.7, horizontalAccuracy: 5)
        store.mergeDTOs([newer], markDirty: false)

        peers.clearPending(for: peerID, sent: sent, store: store)

        // The newer version was never delivered; it must stay queued.
        #expect(peers.pendingIds(for: peerID).contains(record.id))
    }

    @Test
    func clearPendingRemovesUnchangedRecords() {
        let store = ObservationStore(testing: true)
        let base = Date(timeIntervalSince1970: 1_782_900_000)
        let record = dto(updatedAt: base)
        store.mergeDTOs([record], markDirty: false)

        let peers = PairedPeersStore(defaults: makeDefaults())
        let peerID = UUID()
        peers.pair(id: peerID, displayName: "A", publicKey: key, store: store)

        peers.clearPending(for: peerID, sent: [record.id: base], store: store)
        #expect(!peers.pendingIds(for: peerID).contains(record.id))
    }

    @Test
    func persistenceRoundTrip() {
        let defaults = makeDefaults()
        let store = ObservationStore(testing: true)
        store.addObservation("amecro")

        let peers = PairedPeersStore(defaults: defaults)
        let peerID = UUID()
        peers.pair(id: peerID, displayName: "Field Phone", publicKey: key, store: store)

        let reloaded = PairedPeersStore(defaults: defaults)
        #expect(reloaded.isPaired(peerID))
        #expect(reloaded.peer(for: peerID)?.publicKey == key)
        #expect(reloaded.pendingIds(for: peerID) == Set(store.allRecordIds))
    }

    @Test
    func unpairRemovesPeer() {
        let store = ObservationStore(testing: true)
        let peers = PairedPeersStore(defaults: makeDefaults())
        let peerID = UUID()
        peers.pair(id: peerID, displayName: "A", publicKey: key, store: store)
        peers.unpair(peerID)
        #expect(!peers.isPaired(peerID))
        #expect(peers.pendingIds(for: peerID).isEmpty)
    }
}
