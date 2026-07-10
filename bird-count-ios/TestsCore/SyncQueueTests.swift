import Foundation
import Testing
@testable import BirdCountCore

/// Semantics of the header sync badge count.
struct SyncQueueTests {

    private let a = UUID(), b = UUID(), c = UUID()

    @Test
    func unionAcrossCloudAndPeers() {
        let result = SyncQueue.undeliveredIds(
            cloudDirty: [a, b],
            cloudIsDestination: true,
            peerPending: [[b, c], [c]]
        )
        #expect(result == [a, b, c])
    }

    @Test
    func cloudIgnoredWhenNotADestination() {
        // Signed out: dirty ids must not keep the badge lit forever.
        let result = SyncQueue.undeliveredIds(
            cloudDirty: [a, b],
            cloudIsDestination: false,
            peerPending: [[c]]
        )
        #expect(result == [c])
    }

    @Test
    func emptyWhenNothingQueued() {
        let result = SyncQueue.undeliveredIds(
            cloudDirty: [],
            cloudIsDestination: true,
            peerPending: [Set<UUID>()]
        )
        #expect(result.isEmpty)
    }

    @Test
    func overlapCountsOnce() {
        // Same observation queued for cloud AND two peers is ONE unsent
        // observation, not three.
        let result = SyncQueue.undeliveredIds(
            cloudDirty: [a],
            cloudIsDestination: true,
            peerPending: [[a], [a]]
        )
        #expect(result.count == 1)
    }
}
