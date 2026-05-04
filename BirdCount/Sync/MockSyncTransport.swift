import Foundation
import Observation

/// In-memory sync transport for unit tests.
/// Does not use Network Framework, so it works in the simulator without DNS policy errors.
@Observable final class MockSyncTransport: SyncTransport {

    // MARK: - Configuration (set before calling startDiscovery)

    /// The hello the simulated remote peer will send after discovery.
    var simulatedPeerHello: SyncHelloMessage = MockSyncTransport.defaultPeerHello

    /// Delay before the simulated peer is "discovered". Defaults to 0.1s.
    var discoveryDelay: Duration = .milliseconds(100)

    /// Payload the simulated peer will send if role negotiation says we should receive.
    var simulatedIncomingPayload: PayloadV1?

    // MARK: - Observation capture (inspectable in tests)

    /// The payload passed to initiateSync, captured for assertions.
    private(set) var capturedSentPayload: PayloadV1?

    /// Number of times startDiscovery has been called. Useful for verifying restarts.
    private(set) var startDiscoveryCallCount: Int = 0

    // MARK: - SyncTransport

    private(set) var state: SyncState = .idle

    private var localHello: SyncHelloMessage?
    private var discoveryTask: Task<Void, Never>?

    func startDiscovery(localHello: SyncHelloMessage) {
        guard state == .idle else { return }
        self.localHello = localHello
        startDiscoveryCallCount += 1
        state = .discovering

        discoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: discoveryDelay)
            guard !Task.isCancelled else { return }
            self.handlePeerHello(self.simulatedPeerHello)
        }
    }

    func initiateSync(payload: PayloadV1?, receiveInto store: ObservationStore) async {
        guard case .readyToSync(let info) = state else { return }

        capturedSentPayload = payload
        await MainActor.run { state = .transferring }

        try? await Task.sleep(for: .milliseconds(100))

        var sentCount = 0
        var receivedCount = 0
        var duplicatesSkipped = 0

        if info.localWillSend, let p = payload {
            sentCount = p.observations.count
        }

        if info.peerWillSend != nil, let incoming = simulatedIncomingPayload {
            let stats = (try? ObservationImportService.importFromSync(incoming, into: store))
            receivedCount = stats?.newRecordsImported ?? 0
            duplicatesSkipped = stats?.duplicatesSkipped ?? 0
        }

        let completionStats = SyncCompletionStats(
            sentCount: sentCount,
            receivedCount: receivedCount,
            duplicatesSkipped: duplicatesSkipped
        )
        await MainActor.run { [completionStats] in
            self.state = .completed(stats: completionStats)
        }
    }

    func cancel() {
        discoveryTask?.cancel()
        discoveryTask = nil
        localHello = nil
        capturedSentPayload = nil
        state = .idle
    }

    // MARK: - Private

    @MainActor
    private func handlePeerHello(_ peerHello: SyncHelloMessage) {
        guard let localHello else { return }

        state = .handshaking(peerName: peerHello.displayName)

        if let info = SyncReadyInfo.negotiate(local: localHello, peer: peerHello) {
            state = .readyToSync(info: info)
        } else {
            state = .incompatible(reason: "Both devices have the same directional role")
        }
    }

    // MARK: - Default peer hello

    static let defaultPeerHello = SyncHelloMessage(
        displayName: "Test Peer",
        peerID: UUID(),
        rolePreference: .sendAndReceive,
        sendSummary: SyncSendSummary(
            observationCount: 5,
            speciesCount: 3,
            dateRangeBegin: Date().addingTimeInterval(-3600),
            dateRangeEnd: Date()
        )
    )
}
