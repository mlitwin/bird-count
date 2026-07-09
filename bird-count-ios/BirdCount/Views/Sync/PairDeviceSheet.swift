import SwiftUI
import Observation

/// Guided flow for pairing a nearby device, reached from User Settings.
/// Both people open this sheet; each taps Pair on their own phone (pairing is
/// per-device trust, mirroring the mutual model of manual sync).
///
/// Discovery quietly retries on errors: if the other phone's auto-sync
/// service answers first and drops us (we're not paired with it yet), we keep
/// searching until their pairing sheet — which suspends their auto service —
/// takes over the connection.
struct PairDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ObservationStore.self) private var observations
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(PairedPeersStore.self) private var pairedPeers
    @Environment(PeerAutoSyncService.self) private var autoSync
    @State private var vm = PairingViewModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text(Strings.Sync.pairInstructions.string)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                phaseContent

                Spacer()
            }
            .padding()
            .navigationTitle(Strings.Sync.pairTitle.string)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.General.done.string) { dismiss() }
                }
            }
        }
        .onAppear {
            autoSync.setManualSyncActive(true)  // one advertising transport per device
            vm.start(settingsStore: settingsStore)
        }
        .onDisappear {
            vm.stop()
            autoSync.setManualSyncActive(false)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch vm.phase {
        case .searching:
            HStack(spacing: 12) {
                ProgressView()
                Text(Strings.Sync.looking.string)
                    .foregroundStyle(.secondary)
            }

        case .found(let info):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .foregroundStyle(.tint)
                    Text(info.peerName)
                        .font(.headline)
                }

                if pairedPeers.isPaired(info.peerID) {
                    Label(Strings.Sync.pairedAutoSyncs.string, systemImage: "link")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let key = info.peerPublicKey {
                    Button {
                        pairedPeers.pair(
                            id: info.peerID,
                            displayName: info.peerName,
                            publicKey: key,
                            store: observations
                        )
                    } label: {
                        Label(Strings.Sync.pairDevice.string, systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text(Strings.Sync.pairExplanation.string)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case .unsupported:
            Label(Strings.Sync.pairUnsupported.string, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

/// Discovery loop for the pairing sheet: no payload, no roles — just find a
/// verified peer and hold the connection so the user can tap Pair.
@Observable
@MainActor
final class PairingViewModel {
    enum Phase {
        case searching
        case found(SyncReadyInfo)
        /// Peer runs an app version without identity support; it can still
        /// manual-sync, but it cannot pair.
        case unsupported
    }

    private(set) var phase: Phase = .searching

    private let transport: SyncTransport
    private var retryTask: Task<Void, Never>?
    private var generation = 0
    private var running = false

    init(transport: SyncTransport = NetworkSyncTransport()) {
        self.transport = transport
    }

    func start(settingsStore: SettingsStore) {
        guard !running else { return }
        running = true
        phase = .searching
        beginSession(hello: SyncHelloMessage(
            displayName: SyncViewModel.resolveDisplayName(from: settingsStore),
            peerID: UUID(),  // transport stamps the stable identity id
            rolePreference: .sendAndReceive,
            sendSummary: nil
        ))
    }

    func stop() {
        running = false
        generation += 1
        retryTask?.cancel()
        retryTask = nil
        transport.cancel()
    }

    private func beginSession(hello: SyncHelloMessage) {
        generation += 1
        track(generation: generation)
        transport.startDiscovery(localHello: hello)

        func track(generation: Int) {
            withObservationTracking {
                _ = transport.state
            } onChange: {
                Task { @MainActor [weak self] in
                    guard let self, self.running, generation == self.generation else { return }
                    track(generation: generation)
                    self.handleChange(hello: hello)
                }
            }
        }
    }

    private func handleChange(hello: SyncHelloMessage) {
        switch transport.state {
        case .readyToSync(let info):
            phase = info.peerVerified ? .found(info) : .unsupported

        case .error, .incompatible, .completed:
            // Likely the peer's auto-sync service dropping an unpaired
            // connection — keep searching until their pairing sheet answers.
            phase = .searching
            retryTask?.cancel()
            retryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, self.running else { return }
                self.transport.cancel()
                self.beginSession(hello: hello)
            }

        case .idle, .discovering, .handshaking, .transferring:
            break
        }
    }
}
