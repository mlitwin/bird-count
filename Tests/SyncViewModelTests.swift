import Foundation
import Testing
@testable import BirdCount

// Helpers shared across tests

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
        let store = makeStore(observations: [("amecro", 2), ("norbla", 1)])
        let filter = makeFilter()
        let vm = SyncViewModel(
            transport: MockSyncTransport(),
            observationStore: store,
            settingsStore: makeSettings(),
            initialFilter: filter
        )
        #expect(vm.localSendSummary.observationCount == 2)
        #expect(vm.localSendSummary.speciesCount == 2)
    }

    @Test func summaryUpdatesWhenFilterChanges() {
        let store = makeStore(observations: [("amecro", 2)])
        let oldFilter = makeFilter()
        let vm = SyncViewModel(
            transport: MockSyncTransport(),
            observationStore: store,
            settingsStore: makeSettings(),
            initialFilter: oldFilter
        )
        // Narrow the filter to the far past — no observations in range
        let emptyFilter = DateRange(begin: Date().addingTimeInterval(-86400 * 365), end: Date().addingTimeInterval(-86400 * 364))
        vm.syncFilter = emptyFilter
        #expect(vm.localSendSummary.observationCount == 0)
    }
}

// MARK: - State Transitions

struct SyncStateTransitionTests {
    @Test func startsDiscovering() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .seconds(9999) // prevent auto-discovery
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(50))
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
            displayName: "Peer",
            peerID: UUID(),
            rolePreference: .sendOnly,
            sendSummary: nil
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
            displayName: "Peer",
            peerID: UUID(),
            rolePreference: .receiveOnly,
            sendSummary: nil
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
        mock.discoveryDelay = .seconds(9999) // prevent auto-handshake
        let vm = makeVM(transport: mock)
        vm.start()
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.state == .discovering)
        #expect(mock.startDiscoveryCallCount == 1)

        vm.rolePreference = .sendOnly
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.state == .discovering)
        #expect(mock.startDiscoveryCallCount == 2)
    }
}

// MARK: - Sync Execution

struct SyncExecutionTests {
    @Test func sendAndReceive_bothTransfer() async throws {
        let incomingObs = [ObservationRecordDTO(
            id: UUID(), parentId: nil, taxonId: "redwin",
            begin: Date(), end: Date(), count: 2, observer: "peer@example.com"
        )]
        let incomingPayload = PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: incomingObs
        )

        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedIncomingPayload = incomingPayload

        let store = makeStore(observations: [("amecro", 1)])
        let vm = SyncViewModel(
            transport: mock,
            observationStore: store,
            settingsStore: makeSettings(email: "local@example.com"),
            initialFilter: makeFilter()
        )

        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard case .completed(let stats) = vm.state else {
            Issue.record("Expected .completed, got \(vm.state)")
            return
        }
        #expect(stats.sentCount == 1)
        #expect(stats.receivedCount == 1)
        #expect(mock.capturedSentPayload != nil)
    }

    @Test func sendOnly_noIncomingPayloadUsed() async throws {
        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Peer", peerID: UUID(),
            rolePreference: .receiveOnly, sendSummary: nil
        )
        mock.simulatedIncomingPayload = nil

        let vm = makeVM(transport: mock, observations: [("amecro", 1)])
        vm.rolePreference = .sendOnly
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard case .completed(let stats) = vm.state else {
            Issue.record("Expected .completed, got \(vm.state)")
            return
        }
        #expect(stats.sentCount == 1)
        #expect(stats.receivedCount == 0)
    }

    @Test func receiveOnly_nothingSent() async throws {
        let incomingObs = [ObservationRecordDTO(
            id: UUID(), parentId: nil, taxonId: "blujay",
            begin: Date(), end: Date(), count: 1, observer: "peer@example.com"
        )]
        let incomingPayload = PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: incomingObs
        )

        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedPeerHello = SyncHelloMessage(
            displayName: "Peer", peerID: UUID(),
            rolePreference: .sendOnly,
            sendSummary: SyncSendSummary(
                observationCount: 1, speciesCount: 1,
                dateRangeBegin: Date().addingTimeInterval(-3600), dateRangeEnd: Date()
            )
        )
        mock.simulatedIncomingPayload = incomingPayload

        let vm = makeVM(transport: mock, observations: [("amecro", 1)])
        vm.rolePreference = .receiveOnly
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard case .completed(let stats) = vm.state else {
            Issue.record("Expected .completed, got \(vm.state)")
            return
        }
        #expect(stats.sentCount == 0)
        #expect(stats.receivedCount == 1)
        #expect(mock.capturedSentPayload == nil)
    }

    @Test func completionStats_correctCounts() async throws {
        // Pre-populate store with one record that will be a duplicate
        let duplicateID = UUID()
        let store = makeStore()
        store.importObservations([ObservationRecord(
            id: duplicateID, taxonId: "amecro", begin: Date(), end: nil, count: 1, observer: ""
        )])

        let incomingObs = [
            ObservationRecordDTO(id: duplicateID, parentId: nil, taxonId: "amecro",
                                 begin: Date(), end: Date(), count: 1, observer: "p@e.com"),
            ObservationRecordDTO(id: UUID(), parentId: nil, taxonId: "norbla",
                                 begin: Date(), end: Date(), count: 1, observer: "p@e.com")
        ]
        let incomingPayload = PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: incomingObs
        )

        let mock = MockSyncTransport()
        mock.discoveryDelay = .milliseconds(50)
        mock.simulatedIncomingPayload = incomingPayload

        let vm = SyncViewModel(
            transport: mock,
            observationStore: store,
            settingsStore: makeSettings(email: "local@example.com"),
            initialFilter: makeFilter()
        )
        vm.start()
        try await Task.sleep(for: .milliseconds(300))
        vm.initiateSync()
        try await Task.sleep(for: .milliseconds(500))

        guard case .completed(let stats) = vm.state else {
            Issue.record("Expected .completed, got \(vm.state)")
            return
        }
        #expect(stats.receivedCount == 1)
        #expect(stats.duplicatesSkipped == 1)
    }
}

// MARK: - Role Negotiation Logic

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
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // ISO8601 encoder has second precision; truncate to avoid sub-second mismatch on decode.
    private func sec(_ d: Date) -> Date {
        Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded(.down))
    }

    @Test func helloRoundTrip() throws {
        let hello = SyncHelloMessage(
            displayName: "test@example.com",
            peerID: UUID(),
            rolePreference: .sendAndReceive,
            sendSummary: SyncSendSummary(
                observationCount: 10,
                speciesCount: 4,
                dateRangeBegin: sec(Date().addingTimeInterval(-3600)),
                dateRangeEnd: sec(Date())
            )
        )
        let msg = SyncMessage.helloMessage(hello)
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(SyncMessage.self, from: data)
        #expect(decoded.type == .hello)
        #expect(decoded.hello == hello)
    }

    @Test func payloadRoundTrip() throws {
        let obs = ObservationRecordDTO(
            id: UUID(), taxonId: "amecro",
            begin: Date(), end: Date(), count: 3, observer: "x@y.com"
        )
        let payload = PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Alice",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: [obs]
        )
        let msg = SyncMessage.payloadMessage(payload)
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(SyncMessage.self, from: data)
        #expect(decoded.type == .payload)
        #expect(decoded.payload?.observations.count == 1)
    }

    @Test func receiveOnlyHello_hasNilSendSummary() throws {
        let hello = SyncHelloMessage(
            displayName: "recv@example.com",
            peerID: UUID(),
            rolePreference: .receiveOnly,
            sendSummary: nil
        )
        let msg = SyncMessage.helloMessage(hello)
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(SyncMessage.self, from: data)
        #expect(decoded.hello?.sendSummary == nil)
    }
}
