import Foundation
import Testing
@testable import BirdCount

// MARK: - Test Helpers

private func makeStore(observations: [(taxonId: String, count: Int)] = []) -> ObservationStore {
    let store = ObservationStore()
    store.clearAll()
    for obs in observations {
        store.addObservation(obs.taxonId, begin: Date(), end: nil, count: obs.count)
    }
    return store
}

private func makeSettings(email: String = "") -> SettingsStore {
    let s = SettingsStore()
    s.loginEmail = email
    return s
}

private func makeFilter() -> DateRange {
    DateRange(begin: Date().addingTimeInterval(-7200), end: Date().addingTimeInterval(3600))
}

private func makeVM(
    transport: MockSyncTransport = MockSyncTransport(),
    observations: [(taxonId: String, count: Int)] = [],
    email: String = "birder@example.com"
) -> SyncViewModel {
    SyncViewModel(
        transport: transport,
        observationStore: makeStore(observations: observations),
        settingsStore: makeSettings(email: email),
        initialFilter: makeFilter()
    )
}

/// Build a payload with the given taxon IDs. Each observation gets a fresh UUID.
private func makeIncomingPayload(
    taxonIds: [String],
    observer: String = "peer@example.com"
) -> PayloadV1 {
    let obs = taxonIds.map { taxonId in
        ObservationRecordDTO(id: UUID(), taxonId: taxonId,
                             begin: Date(), end: Date(), count: 1, observer: observer)
    }
    return PayloadV1(
        schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
        rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
        observations: obs
    )
}

/// Asserts the VM is in `.completed` and returns the stats; records an issue and returns nil otherwise.
private func requireCompleted(
    _ state: SyncState,
    sourceLocation: SourceLocation = #_sourceLocation
) -> SyncCompletionStats? {
    guard case .completed(let stats) = state else {
        Issue.record("Expected .completed, got \(state)", sourceLocation: sourceLocation)
        return nil
    }
    return stats
}

// MARK: - Display Name

struct SyncDisplayNameTests {
    @Test func usesEmailWhenSet() {
        let name = SyncViewModel.resolveDisplayName(from: makeSettings(email: "matt@example.com"))
        #expect(name == "matt@example.com")
    }

    @Test func fallsBackToDeviceName_whenEmailEmpty() {
        let name = SyncViewModel.resolveDisplayName(from: makeSettings(email: ""))
        #expect(!name.isEmpty)
    }
}

// MARK: - Local Summary

struct SyncLocalSummaryTests {
    @Test func summaryReflectsObservations() {
        let vm = makeVM(observations: [("amecro", 2), ("norbla", 1)])
        #expect(vm.localSendSummary.observationCount == 2)
        #expect(vm.localSendSummary.speciesCount == 2)
    }

    @Test func summaryUpdatesWhenFilterChanges() {
        let vm = makeVM(observations: [("amecro", 2)])
        let pastRange = DateRange(begin: Date().addingTimeInterval(-86400 * 365),
                                  end: Date().addingTimeInterval(-86400 * 364))
        vm.syncFilter = pastRange
        #expect(vm.localSendSummary.observationCount == 0)
    }
}

// MARK: - State Transitions

struct SyncStateTransitionTests {
    @Test func startsDiscovering() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .seconds(9999)
        let vm = makeVM(transport: mock)
        vm.start()
        // 200ms gives the observation-tracking Task { @MainActor in } time to run
        // even under main actor load from parallel test suites.
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.state == .discovering)
    }

    @Test func transitionsToReadyAfterHandshake() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        if case .readyToSync = vm.state { } else {
            Issue.record("Expected .readyToSync, got \(vm.state)")
        }
    }

    @Test func incompatibleRoles_bothSendOnly() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Peer", peerID: UUID(), rolePreference: .sendOnly, sendSummary: nil
        )
        let vm = makeVM(transport: mock)
        vm.rolePreference = .sendOnly
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        if case .incompatible = vm.state { } else {
            Issue.record("Expected .incompatible, got \(vm.state)")
        }
    }

    @Test func incompatibleRoles_bothReceiveOnly() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Peer", peerID: UUID(), rolePreference: .receiveOnly, sendSummary: nil
        )
        let vm = makeVM(transport: mock)
        vm.rolePreference = .receiveOnly
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        if case .incompatible = vm.state { } else {
            Issue.record("Expected .incompatible, got \(vm.state)")
        }
    }

    @Test func cancelResetsToIdle() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.cancel()
        #expect(vm.state == .idle)
    }

    @Test func roleChangeWhileDiscovering_restartsDiscovery() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .seconds(9999)
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.state == .discovering)
        #expect(mock.startDiscoveryCallCount == 1)

        vm.rolePreference = .sendOnly
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.state == .discovering)
        #expect(mock.startDiscoveryCallCount == 2)
    }
}

// MARK: - Sync Execution (Initiator Path)

struct SyncExecutionTests {
    @Test func sendAndReceive_bothTransfer() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedIncomingPayload = makeIncomingPayload(taxonIds: ["redwin"])

        let vm = makeVM(transport: mock, observations: [("amecro", 1)])
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let stats = requireCompleted(vm.state) else { return }
        #expect(stats.sentCount == 1)
        #expect(stats.receivedCount == 1)
        #expect(mock.capturedSentPayload != nil)
    }

    @Test func sendOnly_noIncomingPayloadUsed() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Peer", peerID: UUID(), rolePreference: .receiveOnly, sendSummary: nil
        )

        let vm = makeVM(transport: mock, observations: [("amecro", 1)])
        vm.rolePreference = .sendOnly
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let stats = requireCompleted(vm.state) else { return }
        #expect(stats.sentCount == 1)
        #expect(stats.receivedCount == 0)
    }

    @Test func receiveOnly_nothingSent() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Peer", peerID: UUID(), rolePreference: .sendOnly,
            sendSummary: SyncSendSummary(observationCount: 1, speciesCount: 1,
                                         dateRangeBegin: Date().addingTimeInterval(-3600),
                                         dateRangeEnd: Date())
        )
        mock.simulatedIncomingPayload = makeIncomingPayload(taxonIds: ["blujay"])

        let vm = makeVM(transport: mock, observations: [("amecro", 1)])
        vm.rolePreference = .receiveOnly
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let stats = requireCompleted(vm.state) else { return }
        #expect(stats.sentCount == 0)
        #expect(stats.receivedCount == 1)
        #expect(mock.capturedSentPayload == nil)
    }

    @Test func completionStats_duplicatesSkipped() async throws {
        let store = makeStore()
        let duplicateID = UUID()
        // identical timestamps -> equal updatedAt -> deduplicated (not LWW-applied)
        let created = Date()
        store.importObservations([ObservationRecord(id: duplicateID, taxonId: "amecro",
                                                    begin: created, end: nil, count: 1, observer: "")])
        let payload = PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: [
                ObservationRecordDTO(id: duplicateID, taxonId: "amecro",
                                     begin: created, end: created, count: 1, observer: ""),
                ObservationRecordDTO(id: UUID(), taxonId: "norbla",
                                     begin: Date(), end: Date(), count: 1, observer: "p@e.com")
            ]
        )

        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedIncomingPayload = payload

        let vm = SyncViewModel(transport: mock, observationStore: store,
                               settingsStore: makeSettings(email: "local@example.com"),
                               initialFilter: makeFilter())
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let stats = requireCompleted(vm.state) else { return }
        #expect(stats.receivedCount == 1)
        #expect(stats.duplicatesSkipped == 1)
    }
}

// MARK: - Non-Initiator Path (Auto-Initiation)

/// These tests verify the non-initiator side: the VM auto-calls initiateSync() when the peer
/// signals .syncStart, without requiring a user tap on the second device.
/// .serialized prevents within-suite parallelism; these tests use Task.sleep for timing and
/// compete for the main actor with other async test suites.
@Suite("SyncNonInitiator", .serialized)
struct SyncNonInitiatorTests {

    @Test func autoInitiates_whenPeerSignals_whileReadyToSync() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        if case .readyToSync = vm.state { } else {
            Issue.record("Precondition: expected .readyToSync, got \(vm.state)"); return
        }

        mock.triggerPeerInitiatedSync()
        try await Task.sleep(for: .milliseconds(500))

        if case .completed = vm.state { } else {
            Issue.record("Expected .completed after peer-initiated sync, got \(vm.state)")
        }
    }

    @Test func autoInitiates_whenPeerSignals_beforeHandshake() async throws {
        // .syncStart arrives before the hello exchange finishes.
        // The VM should defer auto-initiation until it reaches .readyToSync.
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(200)
        let vm = makeVM(transport: mock)
        vm.start()

        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.state == .discovering, "Precondition: must still be discovering")

        mock.triggerPeerInitiatedSync()  // arrives before handshake

        // Let the handshake complete and auto-initiation fire
        try await Task.sleep(for: .milliseconds(800))
        if case .completed = vm.state { } else {
            Issue.record("Expected .completed; peerInitiatedSync before handshake should defer until readyToSync, got \(vm.state)")
        }
    }

    @Test func nonInitiator_receivesIncomingPayload() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedIncomingPayload = makeIncomingPayload(taxonIds: ["norbla", "blujay"])

        let vm = makeVM(transport: mock)
        vm.rolePreference = .receiveOnly
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        mock.triggerPeerInitiatedSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let stats = requireCompleted(vm.state) else { return }
        #expect(stats.sentCount == 0)
        #expect(stats.receivedCount == 2)
    }

    @Test func peerInitiatedSync_resetOnCancel() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .seconds(9999)
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(50))
        mock.triggerPeerInitiatedSync()
        #expect(mock.peerInitiatedSync == true)

        vm.cancel()
        #expect(mock.peerInitiatedSync == false)
    }
}

// MARK: - Bidirectional Sync Simulation

/// Exercises both sides of a bidirectional sync independently using separate VM + mock pairs.
/// In production both sides communicate over the network; here we simulate each side in isolation.
// .serialized prevents parallel execution; each test runs two full sync flows back-to-back
// and competes with scroll view tests for the main actor when run concurrently.
@Suite("SyncBidirectional", .serialized)
struct SyncBidirectionalTests {

    @Test func bothSides_completeWithCorrectStats() async throws {
        // Initiator side: user taps "Sync"
        let initiatorMock = MockSyncTransport()
        initiatorMock.discoveryDelay = .milliseconds(50)
        initiatorMock.simulatedIncomingPayload = makeIncomingPayload(taxonIds: ["norbla"])
        let initiatorVM = makeVM(transport: initiatorMock, observations: [("amecro", 1)])
        initiatorVM.start()
        try await Task.sleep(for: .milliseconds(300))
        initiatorVM.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let initiatorStats = requireCompleted(initiatorVM.state) else { return }
        #expect(initiatorStats.sentCount == 1)
        #expect(initiatorStats.receivedCount == 1)

        // Non-initiator side: peer signals .syncStart; VM auto-initiates
        let nonInitiatorMock = MockSyncTransport()
        nonInitiatorMock.discoveryDelay = .milliseconds(50)
        nonInitiatorMock.simulatedIncomingPayload = makeIncomingPayload(taxonIds: ["amecro"])
        let nonInitiatorVM = makeVM(transport: nonInitiatorMock, observations: [("norbla", 1)])
        nonInitiatorVM.start()
        try await Task.sleep(for: .milliseconds(300))
        nonInitiatorMock.triggerPeerInitiatedSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let nonInitiatorStats = requireCompleted(nonInitiatorVM.state) else { return }
        #expect(nonInitiatorStats.sentCount == 1)
        #expect(nonInitiatorStats.receivedCount == 1)
    }

    @Test func initiator_sendOnly_nonInitiator_receiveOnly() async throws {
        // A sends (sendOnly), B receives (receiveOnly).
        // A initiates; B auto-initiates via peerInitiatedSync.
        let senderMock = MockSyncTransport()
        senderMock.discoveryDelay = .milliseconds(50)
        senderMock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Receiver", peerID: UUID(), rolePreference: .receiveOnly, sendSummary: nil
        )
        // Each tuple is one ObservationRecord; sentCount == number of records exported.
        let senderVM = makeVM(transport: senderMock, observations: [("amecro", 1), ("norbla", 1)])
        senderVM.rolePreference = .sendOnly
        senderVM.start()
        try await Task.sleep(for: .milliseconds(300))
        senderVM.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let senderStats = requireCompleted(senderVM.state) else { return }
        #expect(senderStats.sentCount == 2)
        #expect(senderStats.receivedCount == 0)

        let receiverMock = MockSyncTransport()
        receiverMock.discoveryDelay = .milliseconds(50)
        receiverMock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Sender", peerID: UUID(), rolePreference: .sendOnly,
            sendSummary: SyncSendSummary(observationCount: 2, speciesCount: 2,
                                         dateRangeBegin: Date().addingTimeInterval(-3600),
                                         dateRangeEnd: Date())
        )
        receiverMock.simulatedIncomingPayload = makeIncomingPayload(taxonIds: ["amecro", "norbla"])
        let receiverVM = makeVM(transport: receiverMock)
        receiverVM.rolePreference = .receiveOnly
        receiverVM.start()
        try await Task.sleep(for: .milliseconds(300))
        receiverMock.triggerPeerInitiatedSync()
        try await Task.sleep(for: .milliseconds(500))

        guard let receiverStats = requireCompleted(receiverVM.state) else { return }
        #expect(receiverStats.sentCount == 0)
        #expect(receiverStats.receivedCount == 2)
    }
}

// MARK: - Restart

@Suite(.serialized)
struct SyncRestartTests {
    @Test func restart_fromCompleted_resumesDiscovery() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))
        guard case .completed = vm.state else {
            Issue.record("Precondition: expected .completed, got \(vm.state)"); return
        }

        mock.discoveryDelay = .seconds(9999)
        vm.restart()
        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.state == .discovering)
        #expect(mock.startDiscoveryCallCount == 2)
        #expect(mock.peerInitiatedSync == false)
    }

    @Test func restart_clearsNonInitiatorFlag() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        mock.triggerPeerInitiatedSync()
        try await Task.sleep(for: .milliseconds(700))
        guard case .completed = vm.state else {
            Issue.record("Precondition: expected .completed, got \(vm.state)"); return
        }

        mock.discoveryDelay = .seconds(9999)
        vm.restart()
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.peerInitiatedSync == false, "peerInitiatedSync must be cleared on restart")
    }
}

// MARK: - Role Negotiation

struct RoleNegotiationTests {
    @Test func sendAndReceive_vs_sendAndReceive_bothTransfer() {
        let local = SyncRolePreference.sendAndReceive
        let peer = SyncRolePreference.sendAndReceive
        #expect(local.localShouldSend(peerPrefers: peer) == true)
        #expect(local.localShouldReceive(peerPrefers: peer) == true)
        #expect(local.isIncompatible(with: peer) == false)
    }

    @Test func sendOnly_vs_receiveOnly_localSends() {
        #expect(SyncRolePreference.sendOnly.localShouldSend(peerPrefers: .receiveOnly) == true)
        #expect(SyncRolePreference.sendOnly.localShouldReceive(peerPrefers: .receiveOnly) == false)
    }

    @Test func receiveOnly_vs_sendOnly_localReceives() {
        #expect(SyncRolePreference.receiveOnly.localShouldSend(peerPrefers: .sendOnly) == false)
        #expect(SyncRolePreference.receiveOnly.localShouldReceive(peerPrefers: .sendOnly) == true)
    }

    @Test func bothSendOnly_incompatible() {
        #expect(SyncRolePreference.sendOnly.isIncompatible(with: .sendOnly) == true)
    }

    @Test func bothReceiveOnly_incompatible() {
        #expect(SyncRolePreference.receiveOnly.isIncompatible(with: .receiveOnly) == true)
    }
}

// MARK: - SyncMessage Codec

struct SyncMessageCodecTests {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    // ISO8601 encoder has second precision; truncate to avoid sub-second mismatch on decode.
    private func sec(_ d: Date) -> Date {
        Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded(.down))
    }

    @Test func helloRoundTrip() throws {
        let hello = SyncHelloMessage(
            displayName: "test@example.com", peerID: UUID(),
            rolePreference: .sendAndReceive,
            sendSummary: SyncSendSummary(observationCount: 10, speciesCount: 4,
                                         dateRangeBegin: sec(Date().addingTimeInterval(-3600)),
                                         dateRangeEnd: sec(Date()))
        )
        let decoded = try decoder.decode(SyncMessage.self, from: encoder.encode(SyncMessage.helloMessage(hello)))
        #expect(decoded.type == .hello)
        #expect(decoded.hello == hello)
    }

    @Test func payloadRoundTrip() throws {
        let obs = ObservationRecordDTO(id: UUID(), taxonId: "amecro",
                                       begin: Date(), end: Date(), count: 3, observer: "x@y.com")
        let payload = PayloadV1(schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Alice",
                                rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
                                observations: [obs])
        let decoded = try decoder.decode(SyncMessage.self, from: encoder.encode(SyncMessage.payloadMessage(payload)))
        #expect(decoded.type == .payload)
        #expect(decoded.payload?.observations.count == 1)
    }

    @Test func syncStartRoundTrip() throws {
        let decoded = try decoder.decode(SyncMessage.self, from: encoder.encode(SyncMessage.syncStartMessage()))
        #expect(decoded.type == .syncStart)
        #expect(decoded.hello == nil)
        #expect(decoded.payload == nil)
    }

    @Test func receiveOnlyHello_hasNilSendSummary() throws {
        let hello = SyncHelloMessage(displayName: "recv@example.com", peerID: UUID(),
                                     rolePreference: .receiveOnly, sendSummary: nil)
        let decoded = try decoder.decode(SyncMessage.self, from: encoder.encode(SyncMessage.helloMessage(hello)))
        #expect(decoded.hello?.sendSummary == nil)
    }
}
