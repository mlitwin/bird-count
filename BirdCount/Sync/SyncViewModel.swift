import Foundation
import Observation
import UIKit

@Observable final class SyncViewModel {

    // MARK: - User-configurable state

    var rolePreference: SyncRolePreference = .sendAndReceive {
        didSet {
            updateLocalSummary()
            // Restart discovery so the new role is advertised
            if case .discovering = state { restartDiscovery() }
        }
    }

    var syncFilter: DateRange {
        didSet { updateLocalSummary() }
    }

    // MARK: - Derived state

    private(set) var localSendSummary: SyncSendSummary
    private(set) var state: SyncState = .idle

    // MARK: - Dependencies

    private let transport: SyncTransport
    private let observationStore: ObservationStore
    private let displayName: String
    private let localPeerID: UUID = UUID()

    // MARK: - Init

    init(
        transport: SyncTransport,
        observationStore: ObservationStore,
        settingsStore: SettingsStore,
        initialFilter: DateRange
    ) {
        self.transport = transport
        self.observationStore = observationStore
        self.displayName = SyncViewModel.resolveDisplayName(from: settingsStore)
        self.syncFilter = initialFilter
        self.localSendSummary = ObservationExportService.summaryForSync(in: initialFilter, from: observationStore)
    }

    // MARK: - Public API

    func start() {
        guard case .idle = state else { return }
        trackTransportState()
        transport.startDiscovery(localHello: buildHello())
    }

    func initiateSync() {
        guard case .readyToSync(let info) = state else { return }
        let payload = info.localWillSend
            ? ObservationExportService.exportForSync(displayName: displayName, in: syncFilter, from: observationStore)
            : nil
        Task { [weak self] in
            guard let self else { return }
            await self.transport.initiateSync(payload: payload, receiveInto: self.observationStore)
        }
    }

    func cancel() {
        transport.cancel()
        state = .idle
    }

    // MARK: - Private

    private func buildHello() -> SyncHelloMessage {
        let summary: SyncSendSummary? = rolePreference != .receiveOnly ? localSendSummary : nil
        return SyncHelloMessage(
            displayName: displayName,
            peerID: localPeerID,
            rolePreference: rolePreference,
            sendSummary: summary
        )
    }

    private func restartDiscovery() {
        transport.cancel()
        state = .idle
        trackTransportState()
        transport.startDiscovery(localHello: buildHello())
    }

    /// Keeps self.state in sync with transport.state using recursive observation tracking.
    private func trackTransportState() {
        withObservationTracking {
            state = transport.state
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = self.transport.state
                self.trackTransportState()
            }
        }
    }

    private func updateLocalSummary() {
        localSendSummary = ObservationExportService.summaryForSync(in: syncFilter, from: observationStore)
    }

    // MARK: - Display Name

    static func resolveDisplayName(from settingsStore: SettingsStore) -> String {
        let email = settingsStore.loginEmail
        return email.isEmpty ? UIDevice.current.name : email
    }
}
