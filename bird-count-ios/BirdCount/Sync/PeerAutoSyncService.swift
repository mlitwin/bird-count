import Foundation
import Observation

/// Zero-tap P2P sync with paired devices while the app is foregrounded.
///
/// Owns its own NetworkSyncTransport and keeps it discovering whenever the
/// app is active and at least one device is paired. When a connected peer
/// proves it holds a paired identity key, and either side has queued records,
/// the delta exchange runs automatically — no taps on either device.
///
/// Fully offline: the underlying transport is Bonjour over local / peer-to-
/// peer Wi-Fi and needs no router, internet, or cell service.
///
/// Coexistence with the manual SyncSheet: the sheet suspends this service on
/// the local device while it is open (so only one transport advertises per
/// device). A remote manual session that reaches this service is served when
/// its identity is paired; unpaired sessions are dropped — pairing requires
/// the sheet open on both devices, matching the existing manual sync UX.
@Observable
@MainActor
final class PeerAutoSyncService {

    private(set) var lastAutoSyncDate: Date?
    private(set) var isRunning = false

    /// A paired-device exchange is transferring right now (drives the header
    /// sync badge's spinner). Reads through to the observable transport.
    var isExchanging: Bool {
        if case .transferring = transport.state { return true }
        return false
    }

    // MARK: - Dependencies

    private let observationStore: ObservationStore
    private let settingsStore: SettingsStore
    private let pairedPeers: PairedPeersStore
    private let identity: PeerIdentity
    private let transport: SyncTransport

    // MARK: - Lifecycle state

    private var scenePhaseActive = false
    private var manualSyncActive = false
    /// Invalidates observation-tracking callbacks from torn-down sessions: a
    /// stale onChange arriving after a stop/start cycle must not re-register
    /// (that would accumulate duplicate tracking loops) or double-handle.
    private var sessionGeneration = 0
    private var restartTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    // Untracked and nonisolated(unsafe): written once in init, read in
    // deinit; not UI state.
    @ObservationIgnored nonisolated(unsafe) private var changeObserver: NSObjectProtocol?
    /// Send snapshot of the in-flight session: peer + exact versions sent,
    /// so completion clears only what was actually delivered unchanged.
    private var activeSession: (peerID: UUID, sentVersions: [UUID: Date])?
    private var hasInitiatedThisSession = false
    /// Whether the hello for the current session advertised records to send.
    /// The peer only waits for (and merges) a payload it was promised, so we
    /// must never send data a stale hello didn't announce — restart instead.
    private var helloAdvertisedSend = false

    /// Delay before rediscovering after a completed sync (both sides restart;
    /// short keeps paired devices connected-and-ready while near each other).
    static let restartAfterCompletion: TimeInterval = 5
    /// Backoff after a failed session.
    static let restartAfterError: TimeInterval = 15
    /// Quiet period after local changes before refreshing the session, so a
    /// burst of count taps becomes one delta exchange.
    static let changeDebounce: TimeInterval = 10

    init(
        observationStore: ObservationStore,
        settingsStore: SettingsStore,
        pairedPeers: PairedPeersStore,
        identity: PeerIdentity = PeerIdentity.loadOrCreate(),
        transport: SyncTransport? = nil
    ) {
        self.observationStore = observationStore
        self.settingsStore = settingsStore
        self.pairedPeers = pairedPeers
        self.identity = identity
        self.transport = transport ?? NetworkSyncTransport(identity: identity)

        changeObserver = NotificationCenter.default.addObserver(
            forName: ObservationStore.didChangeRecordsNotification,
            object: observationStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    // MARK: - Activation

    /// Track app foreground state. Drive with `scenePhase != .background`:
    /// brief `.inactive` moments (Control Center, Face ID, call banner) must
    /// not tear the session down — the peer would see a dropped connection
    /// and back off. Sockets keep working while merely inactive.
    func setScenePhaseActive(_ active: Bool) {
        scenePhaseActive = active
        evaluate()
    }

    /// The manual SyncSheet suspends the service while it is open so only one
    /// transport advertises on this device. Idempotent on purpose: SwiftUI
    /// can deliver duplicate onAppear calls, and a counter would wedge.
    func setManualSyncActive(_ active: Bool) {
        manualSyncActive = active
        evaluate()
    }

    private var shouldRun: Bool {
        scenePhaseActive && !manualSyncActive && !pairedPeers.peers.isEmpty
    }

    private func evaluate() {
        if shouldRun && !isRunning {
            startSession()
        } else if !shouldRun && isRunning {
            stopSession()
        }
    }

    // MARK: - Session loop

    private func startSession() {
        isRunning = true
        hasInitiatedThisSession = false
        activeSession = nil
        beginTracking()
        transport.startDiscovery(localHello: buildHello())
    }

    private func stopSession() {
        isRunning = false
        sessionGeneration += 1  // orphan any armed onChange callbacks
        restartTask?.cancel()
        restartTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        activeSession = nil
        transport.cancel()
    }

    /// Tear down the current session and rediscover after a delay (fresh
    /// hello, fresh nonce). Both peers do this after each exchange.
    private func scheduleRestart(after delay: TimeInterval) {
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.transport.cancel()
            self.hasInitiatedThisSession = false
            self.activeSession = nil
            self.beginTracking()
            self.transport.startDiscovery(localHello: self.buildHello())
        }
    }

    /// Local records changed: after a quiet period, refresh the session so
    /// the hello advertises the new queue (unless a transfer is running —
    /// its completion path restarts anyway).
    private func scheduleRefresh() {
        guard isRunning else { return }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.changeDebounce))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            if case .transferring = self.transport.state { return }
            self.scheduleRestart(after: 0)
        }
    }

    private func buildHello() -> SyncHelloMessage {
        // The hello goes out before we know which peer will connect, so the
        // summary covers the union of all peers' queues; the actual payload
        // is per-peer. An empty union advertises "nothing to send" so idle
        // reconnects don't ping-pong empty exchanges.
        let pendingUnion = pairedPeers.peers.reduce(into: Set<UUID>()) { $0.formUnion($1.pendingIds) }
        let summary: SyncSendSummary?
        if pendingUnion.isEmpty {
            summary = nil
        } else {
            let dtos = observationStore.flatDTOs().filter { pendingUnion.contains($0.id) }
            summary = SyncSendSummary(
                observationCount: dtos.count,
                speciesCount: Set(dtos.map { $0.taxonId }).count,
                dateRangeBegin: dtos.map { $0.begin }.min() ?? Date(),
                dateRangeEnd: dtos.map { $0.end }.max() ?? Date()
            )
        }
        helloAdvertisedSend = summary != nil
        return SyncHelloMessage(
            displayName: SyncViewModel.resolveDisplayName(from: settingsStore),
            peerID: identity.peerID,
            rolePreference: .sendAndReceive,
            sendSummary: summary
        )
    }

    // MARK: - Transport observation

    /// Start a fresh tracking chain, invalidating any callback still armed
    /// from a previous chain (its captured generation no longer matches).
    private func beginTracking() {
        sessionGeneration += 1
        trackTransportState(generation: sessionGeneration)
    }

    private func trackTransportState(generation: Int) {
        withObservationTracking {
            _ = transport.state
            _ = transport.peerInitiatedSync
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, generation == self.sessionGeneration else { return }
                self.trackTransportState(generation: generation)
                self.handleTransportChange()
            }
        }
    }

    private func handleTransportChange() {
        switch transport.state {
        case .readyToSync(let info):
            handleReady(info)

        case .completed:
            if let session = activeSession {
                pairedPeers.clearPending(for: session.peerID, sent: session.sentVersions, store: observationStore)
                lastAutoSyncDate = Date()
            }
            activeSession = nil
            scheduleRestart(after: Self.restartAfterCompletion)

        case .error, .incompatible:
            activeSession = nil
            scheduleRestart(after: Self.restartAfterError)

        case .idle, .discovering, .handshaking, .transferring:
            break
        }
    }

    private func handleReady(_ info: SyncReadyInfo) {
        // Auto-sync only with a peer that proved possession of the exact key
        // stored at pairing time. Anyone else gets dropped: unpaired syncing
        // stays a deliberate, sheet-open-on-both-devices act.
        guard info.peerVerified,
              let key = info.peerPublicKey,
              let paired = pairedPeers.peer(for: info.peerID),
              paired.publicKey == key
        else {
            scheduleRestart(after: Self.restartAfterError)
            return
        }
        pairedPeers.updateDisplayName(info.peerName, for: info.peerID)

        guard !hasInitiatedThisSession else { return }

        // Initiate when either side has something queued; otherwise stay
        // connected and quiet (a change on either side restarts the session,
        // and a peer-initiated manual sync arrives as peerInitiatedSync).
        let pending = pairedPeers.pendingIds(for: info.peerID)
        let peerHasData = (info.peerWillSend?.observationCount ?? 0) > 0
        guard !pending.isEmpty || peerHasData || transport.peerInitiatedSync else { return }

        // Records queued after this session's hello went out: the peer wasn't
        // promised a payload and would ignore it. Rebuild the session with a
        // fresh hello instead — unless the peer already started the exchange,
        // in which case serve it now and let the next session carry the queue.
        if !pending.isEmpty && !helloAdvertisedSend && !transport.peerInitiatedSync {
            scheduleRestart(after: 0)
            return
        }

        hasInitiatedThisSession = true
        let canSend = helloAdvertisedSend && info.localWillSend
        let dtos = canSend ? observationStore.flatDTOs().filter { pending.contains($0.id) } : []
        activeSession = (
            peerID: info.peerID,
            sentVersions: Dictionary(uniqueKeysWithValues: dtos.map { ($0.id, $0.updatedAt) })
        )

        let payload: PayloadV1? = canSend ? PayloadV1(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            senderDisplayName: SyncViewModel.resolveDisplayName(from: settingsStore),
            rangeStart: dtos.map { $0.begin }.min() ?? Date(),
            rangeEnd: dtos.map { $0.end }.max() ?? Date(),
            observations: dtos
        ) : nil

        Task { [weak self] in
            guard let self else { return }
            await self.transport.initiateSync(payload: payload, receiveInto: self.observationStore)
        }
    }
}
