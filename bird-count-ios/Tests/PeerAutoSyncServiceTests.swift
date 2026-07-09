import Foundation
import Testing
@testable import BirdCount

/// Lifecycle edge cases for the paired-device auto sync service: backgrounding,
/// manual-sheet suspension, and stop/start churn.
@MainActor
@Suite(.serialized)
struct PeerAutoSyncServiceTests {

    private let peerKey = Data(repeating: 7, count: 32)

    private func makeDefaults() -> UserDefaults {
        let suite = "PeerAutoSyncServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeWorld() -> (
        service: PeerAutoSyncService,
        transport: MockSyncTransport,
        store: ObservationStore,
        peers: PairedPeersStore,
        peerID: UUID
    ) {
        let store = ObservationStore(testing: true)
        store.addObservation("amecro")

        let peerID = PeerIdentity.peerID(forPublicKey: peerKey)
        let peers = PairedPeersStore(defaults: makeDefaults())
        peers.pair(id: peerID, displayName: "Field Phone", publicKey: peerKey, store: store)

        let transport = MockSyncTransport()
        transport.simulatePeerVerified = true
        transport.discoveryDelay = .milliseconds(20)
        transport.simulatedPeerHello = SyncHelloMessage(
            displayName: "Field Phone",
            peerID: peerID,
            rolePreference: .sendAndReceive,
            sendSummary: nil,
            publicKey: peerKey
        )

        let service = PeerAutoSyncService(
            observationStore: store,
            settingsStore: SettingsStore(),
            pairedPeers: peers,
            transport: transport
        )
        return (service, transport, store, peers, peerID)
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test
    func completedAutoSyncClearsQueue() async {
        let world = makeWorld()
        #expect(!world.peers.pendingIds(for: world.peerID).isEmpty)

        world.service.setScenePhaseActive(true)
        await waitUntil { world.peers.pendingIds(for: world.peerID).isEmpty }

        #expect(world.peers.pendingIds(for: world.peerID).isEmpty)
        #expect(world.service.lastAutoSyncDate != nil)
        #expect(world.transport.capturedSentPayload?.observations.count == 1)
        world.service.setScenePhaseActive(false)
    }

    @Test
    func backgroundingMidTransferKeepsQueue() async {
        let world = makeWorld()
        let queued = world.peers.pendingIds(for: world.peerID)

        world.service.setScenePhaseActive(true)
        await waitUntil {
            if case .transferring = world.transport.state { return true }
            return false
        }

        // App goes to background while the transfer is in flight.
        world.service.setScenePhaseActive(false)
        #expect(!world.service.isRunning)

        // Give the mock's transfer task time to finish; the completion must
        // NOT clear the queue — the session was torn down before completion
        // was observed, so delivery is unconfirmed and the records resend.
        try? await Task.sleep(for: .milliseconds(300))
        #expect(world.peers.pendingIds(for: world.peerID) == queued)
        #expect(world.service.lastAutoSyncDate == nil)
    }

    @Test
    func duplicateSheetAppearanceIsIdempotent() async {
        let world = makeWorld()
        world.service.setScenePhaseActive(true)

        // SwiftUI can deliver onAppear twice with a single onDisappear; the
        // single matching deactivation must still resume the service.
        world.service.setManualSyncActive(true)
        world.service.setManualSyncActive(true)
        #expect(!world.service.isRunning)

        world.service.setManualSyncActive(false)
        #expect(world.service.isRunning)
        world.service.setScenePhaseActive(false)
    }

    @Test
    func inactiveFlickerDoesNotRestartDiscovery() async {
        let world = makeWorld()
        // Drive the service the way the app does: scenePhase != .background.
        // A Control-Center-style .active -> .inactive -> .active flicker maps
        // to repeated `true` and must not churn the transport session.
        world.service.setScenePhaseActive(true)
        await waitUntil { world.transport.startDiscoveryCallCount >= 1 }
        let sessionsBefore = world.transport.startDiscoveryCallCount

        world.service.setScenePhaseActive(true)  // .inactive
        world.service.setScenePhaseActive(true)  // .active again
        #expect(world.transport.startDiscoveryCallCount == sessionsBefore)
        world.service.setScenePhaseActive(false)
    }

    @Test
    func stopStartChurnHandlesEachChangeOnce() async {
        let world = makeWorld()

        // Several background/foreground cycles, some mid-session: stale
        // tracking callbacks from torn-down sessions must not stack up.
        for _ in 0..<3 {
            world.service.setScenePhaseActive(true)
            try? await Task.sleep(for: .milliseconds(10))
            world.service.setScenePhaseActive(false)
        }
        world.service.setScenePhaseActive(true)

        // The full exchange still works exactly once after the churn.
        await waitUntil { world.peers.pendingIds(for: world.peerID).isEmpty }
        #expect(world.peers.pendingIds(for: world.peerID).isEmpty)

        // Exactly one payload capture per completed session; duplicated
        // tracking loops would have initiated extra sessions immediately.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(world.transport.capturedSentPayload?.observations.count == 1)
        world.service.setScenePhaseActive(false)
    }

    @Test
    func unpairedPeerIsNeverServed() async {
        let world = makeWorld()
        world.peers.unpair(world.peerID)

        // With no paired peers the service must not even start.
        world.service.setScenePhaseActive(true)
        #expect(!world.service.isRunning)
        #expect(world.transport.startDiscoveryCallCount == 0)
    }
}
