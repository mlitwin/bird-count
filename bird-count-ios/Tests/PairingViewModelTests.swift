import Foundation
import Testing
@testable import BirdCount

/// The pairing sheet must act as a receiver when a paired peer's auto-sync
/// initiates an exchange with it: the sender clears its outbound queue on
/// completion, so a dropped payload would be lost permanently.
@MainActor
@Suite(.serialized)
struct PairingViewModelTests {

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
    func consumesPayloadWhenVerifiedPeerInitiates() async {
        let store = ObservationStore(testing: true)
        let transport = MockSyncTransport()
        transport.simulatePeerVerified = true
        transport.discoveryDelay = .milliseconds(20)

        let day = Date(timeIntervalSince1970: 1_782_900_000)
        let incoming = ObservationRecordDTO(
            id: UUID(), taxonId: "amecro", begin: day, end: day,
            count: 3, observer: "friend@example.com"
        )
        transport.simulatedIncomingPayload = PayloadV1(
            appVersion: "test",
            senderDisplayName: "Field Phone",
            rangeStart: day,
            rangeEnd: day,
            observations: [incoming]
        )

        let vm = PairingViewModel(transport: transport)
        vm.start(settingsStore: SettingsStore(), receiveInto: store)

        await waitUntil {
            if case .found = vm.phase { return true }
            return false
        }

        // The peer's auto-sync starts the exchange; the sheet must receive.
        transport.triggerPeerInitiatedSync()
        await waitUntil { store.findRecord(by: incoming.id) != nil }

        #expect(store.findRecord(by: incoming.id) != nil)
        vm.stop()
    }
}
