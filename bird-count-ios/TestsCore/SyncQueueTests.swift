import Foundation
import Testing
@testable import BirdCountCore

/// Semantics of the header sync badge count: only observations queued for
/// destinations that are reachable right now.
struct SyncQueueTests {

    private let a = UUID(), b = UUID(), c = UUID()
    private let peer1 = UUID(), peer2 = UUID()

    @Test
    func unionAcrossReachableDestinations() {
        let result = SyncQueue.imminentUndeliveredIds(
            cloudDirty: [a, b],
            cloudReachable: true,
            peerPending: [peer1: [b, c]],
            presentPeers: [peer1]
        )
        #expect(result == [a, b, c])
    }

    @Test
    func absentPeerQueueIsLatentNotImminent() {
        // A paired phone out of range all day must not light the header.
        let result = SyncQueue.imminentUndeliveredIds(
            cloudDirty: [],
            cloudReachable: false,
            peerPending: [peer1: [a, b], peer2: [c]],
            presentPeers: [peer2]
        )
        #expect(result == [c])
    }

    @Test
    func unreachableCloudIsExcluded() {
        // Signed out / off Wi-Fi / auto-sync off: dirty ids are not imminent.
        let result = SyncQueue.imminentUndeliveredIds(
            cloudDirty: [a, b],
            cloudReachable: false,
            peerPending: [:],
            presentPeers: []
        )
        #expect(result.isEmpty)
    }

    @Test
    func overlapCountsOnce() {
        // Same observation queued for cloud AND a present peer is ONE
        // imminent observation, not two.
        let result = SyncQueue.imminentUndeliveredIds(
            cloudDirty: [a],
            cloudReachable: true,
            peerPending: [peer1: [a]],
            presentPeers: [peer1]
        )
        #expect(result.count == 1)
    }

    @Test
    func emptyWhenNothingQueued() {
        let result = SyncQueue.imminentUndeliveredIds(
            cloudDirty: [],
            cloudReachable: true,
            peerPending: [peer1: []],
            presentPeers: [peer1]
        )
        #expect(result.isEmpty)
    }
}
