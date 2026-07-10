import Foundation
import Network
import Observation
import UIKit

@Observable final class NetworkSyncTransport: SyncTransport {

    // MARK: - SyncTransport

    private(set) var state: SyncState = .idle
    private(set) var peerInitiatedSync: Bool = false

    // MARK: - Private

    private let serviceType = "_birdcount._tcp"
    /// Stable identity: peerID is derived from the identity public key, so
    /// paired devices recognize each other across sessions.
    private let identity: PeerIdentity
    private var peerID: UUID { identity.peerID }
    private let queue = DispatchQueue(label: "network-sync", qos: .userInitiated)

    init(identity: PeerIdentity = PeerIdentity.loadOrCreate()) {
        self.identity = identity
    }

    private var listener: NWListener?
    private var browser: NWBrowser?

    // The single active connection (first one that completes handshake wins)
    private var connection: NWConnection?
    private var peerConnection: NWConnection?  // incoming connection before peer ID known

    // Peer endpoints keyed by peerID string
    private var peerEndpoints: [String: NWEndpoint] = [:]

    private var localHello: SyncHelloMessage?
    private var peerHello: SyncHelloMessage?

    // Session auth state: fresh nonce per discovery session; the peer is
    // "verified" once its signature over both nonces checks out against the
    // public key (and claimed peerID) in its hello.
    private var localNonce = PeerIdentity.makeNonce()
    private var peerAuthVerified = false

    // Continuation for initiateSync to wait on incoming payload
    private var receiveContinuation: CheckedContinuation<PayloadV1?, Never>?
    // Payload buffered when it arrives before initiateSync sets up the continuation
    private var bufferedPayload: PayloadV1?

    // MARK: - SyncTransport Methods

    func startDiscovery(localHello: SyncHelloMessage) {
        guard state == .idle else { return }
        // Stamp the hello with this install's identity so the peer can verify
        // (and pair with) a stable key rather than a per-session UUID.
        var hello = localHello
        hello.peerID = identity.peerID
        hello.publicKey = identity.publicKey
        localNonce = PeerIdentity.makeNonce()
        hello.nonce = localNonce
        self.localHello = hello
        setState(.discovering)
        startListener(localHello: hello)
        startBrowser()
    }

    /// State, store, and continuation bookkeeping all happen on the main
    /// actor: this nonisolated async function itself runs on the cooperative
    /// pool, and mutating the @Observable store or transport state from there
    /// raced with main-thread reads (an intermittent-freeze class of bug).
    func initiateSync(payload: PayloadV1?, receiveInto store: ObservationStore) async {
        let start: (SyncReadyInfo, NWConnection)? = await MainActor.run {
            guard case .readyToSync(let info) = state, let conn = connection else { return nil }
            setState(.transferring)
            return (info, conn)
        }
        guard let (info, conn) = start else { return }

        // Signal the peer so the non-initiator auto-starts its side of the sync.
        sendSyncStart(over: conn)

        if info.localWillSend, let payload {
            do {
                try await sendPayload(payload, over: conn)
            } catch {
                await MainActor.run {
                    setState(.error(message: "Send failed: \(error.localizedDescription)"))
                }
                return
            }
        }

        var receivedCount = 0
        var duplicatesSkipped = 0

        if info.peerWillSend != nil {
            // Register on main, where handleIncomingPayload and the connection
            // handlers also run. The peer's payload may have arrived already
            // (non-initiator race) — consume the buffer. If the connection
            // died while we were sending, the state is no longer .transferring
            // and nothing will ever resume us — bail with nil instead of
            // hanging in .transferring forever.
            let incoming: PayloadV1? = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    if let buffered = self.bufferedPayload {
                        self.bufferedPayload = nil
                        continuation.resume(returning: buffered)
                    } else if case .transferring = self.state {
                        self.receiveContinuation = continuation
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let incoming {
                let stats = await MainActor.run {
                    try? ObservationImportService.importFromSync(incoming, into: store)
                }
                receivedCount = stats?.newRecordsImported ?? 0
                duplicatesSkipped = stats?.duplicatesSkipped ?? 0
            }
        }

        await MainActor.run {
            // Connection failure resumes the continuation with nil and sets
            // .error state. Don't overwrite that with .completed.
            guard case .transferring = state else { return }

            let stats = SyncCompletionStats(
                sentCount: payload?.observations.count ?? 0,
                receivedCount: receivedCount,
                duplicatesSkipped: duplicatesSkipped
            )
            setState(.completed(stats: stats))
        }
    }

    func cancel() {
        reset()
    }

    // MARK: - Listener

    private func startListener(localHello: SyncHelloMessage) {
        do {
            let parameters = makeParameters()
            listener = try NWListener(using: parameters)

            var txt = NWTXTRecord()
            txt["peerID"] = peerID.uuidString
            txt["displayName"] = localHello.displayName

            listener?.service = NWListener.Service(
                type: serviceType,
                domain: "local.",
                txtRecord: txt.data
            )

            listener?.newConnectionHandler = { [weak self] conn in
                self?.handleIncomingConnection(conn)
            }

            listener?.stateUpdateHandler = { [weak self] s in
                if case .failed(let err) = s {
                    DispatchQueue.main.async {
                        self?.setState(.error(message: self?.friendlyNetworkError(err) ?? err.localizedDescription))
                    }
                }
            }

            listener?.start(queue: queue)
        } catch {
            setState(.error(message: "Failed to start listener: \(error.localizedDescription)"))
        }
    }

    // MARK: - Browser

    private func startBrowser() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true

        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: serviceType, domain: "local."),
            using: params
        )

        browser?.browseResultsChangedHandler = { [weak self] _, changes in
            self?.handleBrowseChanges(changes)
        }

        browser?.stateUpdateHandler = { [weak self] s in
            if case .failed(let err) = s {
                DispatchQueue.main.async {
                    self?.setState(.error(message: self?.friendlyNetworkError(err) ?? err.localizedDescription))
                }
            }
        }

        browser?.start(queue: queue)
    }

    private func handleBrowseChanges(_ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            if case .added(let result) = change {
                handleBrowseResult(result)
            }
        }
    }

    private func handleBrowseResult(_ result: NWBrowser.Result) {
        guard case .bonjour(let txt) = result.metadata,
              let remotePeerIDStr = txt["peerID"],
              let remotePeerID = UUID(uuidString: remotePeerIDStr) else { return }

        // Avoid connecting to ourselves
        guard remotePeerID != peerID else { return }

        peerEndpoints[remotePeerIDStr] = result.endpoint

        // UUID tiebreaker: smaller UUID initiates the connection
        guard peerID.uuidString < remotePeerIDStr else { return }

        // Only connect if we haven't already
        guard connection == nil, state == .discovering else { return }

        let displayName = txt["displayName"] ?? "Unknown Device"
        DispatchQueue.main.async { [weak self] in
            self?.initiateConnection(to: result.endpoint, peerName: displayName)
        }
    }

    // MARK: - Connection (outgoing)

    private func initiateConnection(to endpoint: NWEndpoint, peerName: String) {
        guard state == .discovering else { return }
        setState(.handshaking(peerName: peerName))

        let conn = NWConnection(to: endpoint, using: makeParameters())
        connection = conn

        conn.stateUpdateHandler = { [weak self] s in
            self?.handleConnectionState(s, connection: conn)
        }

        conn.start(queue: queue)
    }

    // MARK: - Connection (incoming)

    private func handleIncomingConnection(_ conn: NWConnection) {
        // Only accept if we haven't connected yet
        guard connection == nil, state == .discovering else {
            conn.cancel()
            return
        }
        connection = conn

        conn.stateUpdateHandler = { [weak self] s in
            self?.handleConnectionState(s, connection: conn)
        }

        conn.start(queue: queue)
    }

    // MARK: - Connection state

    private func handleConnectionState(_ s: NWConnection.State, connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch s {
            case .ready:
                self.onConnectionReady(connection)

            case .failed(let err):
                if let cont = self.receiveContinuation {
                    // Still waiting for the peer's payload — unblock and surface the error.
                    self.receiveContinuation = nil
                    cont.resume(returning: nil)
                    self.setState(.error(message: self.friendlyNetworkError(err)))
                } else if case .transferring = self.state, self.bufferedPayload != nil {
                    // Payload already arrived; initiateSync will consume the
                    // buffer — let it finish.
                } else {
                    // Includes: failure landing before the receiver registered
                    // its continuation and before any payload arrived. Leaving
                    // .transferring there wedged the transport forever (the
                    // late registration waited on a dead connection, and with
                    // no state change the auto service never restarted).
                    // Setting .error makes the late registration bail with
                    // nil. Trade-off: a drop just after a consumed payload
                    // also reports an error though the data merged — harmless
                    // (idempotent), and strictly better than a wedge.
                    self.setState(.error(message: self.friendlyNetworkError(err)))
                }

            case .cancelled:
                // Always unblock a pending receive so initiateSync is never stuck.
                self.receiveContinuation?.resume(returning: nil)
                self.receiveContinuation = nil
                // If a transfer is in flight, let initiateSync complete on its own.
                guard case .transferring = self.state else {
                    if case .idle = self.state {} else { self.setState(.idle) }
                    return
                }

            default:
                break
            }
        }
    }

    private func onConnectionReady(_ conn: NWConnection) {
        guard let localHello else { return }
        startReceiving(on: conn)
        sendHello(localHello, over: conn)
    }

    // MARK: - Receive loop

    private func startReceiving(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handleReceivedData(data)
                if error == nil { self.startReceiving(on: conn) }
            } else if error == nil && !isComplete {
                // No message yet; keep listening.
                self.startReceiving(on: conn)
            } else {
                // nil data + isComplete is a graceful close, error is a dead
                // connection. Re-arming on close spun this loop at 100% CPU
                // (receiveMessage completes again immediately) — stop, and
                // unblock any pending receive so initiateSync never hangs.
                DispatchQueue.main.async {
                    self.receiveContinuation?.resume(returning: nil)
                    self.receiveContinuation = nil
                }
            }
        }
    }

    private func handleReceivedData(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let msg = try? decoder.decode(SyncMessage.self, from: data) else {
            DispatchQueue.main.async { self.setState(.error(message: "Invalid data received")) }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch msg.type {
            case .hello:
                if let hello = msg.hello { self.handlePeerHello(hello) }
            case .payload:
                if let payload = msg.payload { self.handleIncomingPayload(payload) }
            case .syncStart:
                self.handleSyncStart()
            case .auth:
                if let auth = msg.auth { self.handlePeerAuth(auth) }
            }
        }
    }

    private func handlePeerHello(_ peerHello: SyncHelloMessage) {
        guard localHello != nil else { return }
        self.peerHello = peerHello

        // Identity-capable peer: answer with our session signature and wait
        // for theirs before becoming ready. Legacy peer (no key): ready now,
        // unverified — the manual confirm-and-tap flow still applies.
        if let peerNonce = peerHello.nonce, peerHello.publicKey != nil {
            if let signature = identity.signSession(localNonce: localNonce, peerNonce: peerNonce),
               let conn = connection {
                sendAuth(SyncAuthMessage(signature: signature), over: conn)
            }
        } else {
            becomeReadyIfNegotiable()
        }
    }

    private func handlePeerAuth(_ auth: SyncAuthMessage) {
        guard let peerHello, let peerKey = peerHello.publicKey, let peerNonce = peerHello.nonce else { return }
        guard !peerAuthVerified else { return }

        // The signature must verify against the hello's key, and the claimed
        // peerID must actually be that key's fingerprint — otherwise a device
        // could present its own valid key under a paired peer's id.
        let signatureOK = PeerIdentity.verifySession(
            signature: auth.signature,
            publicKey: peerKey,
            peerNonce: peerNonce,
            localNonce: localNonce
        )
        guard signatureOK, PeerIdentity.peerID(forPublicKey: peerKey) == peerHello.peerID else {
            setState(.error(message: SyncError.peerNotVerified.localizedDescription))
            return
        }
        peerAuthVerified = true
        becomeReadyIfNegotiable()
    }

    private func becomeReadyIfNegotiable() {
        guard let localHello, let peerHello else { return }
        if let info = SyncReadyInfo.negotiate(local: localHello, peer: peerHello, verified: peerAuthVerified) {
            setState(.readyToSync(info: info))
        } else {
            setState(.incompatible(reason: "Both devices have the same directional role"))
        }
    }

    private func handleSyncStart() {
        peerInitiatedSync = true
    }

    private func handleIncomingPayload(_ payload: PayloadV1) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: payload)
        } else {
            // Arrived before initiateSync set up the continuation — buffer for pickup.
            bufferedPayload = payload
        }
    }

    // MARK: - Send helpers

    private func sendSyncStart(over conn: NWConnection) {
        let msg = SyncMessage.syncStartMessage()
        guard let data = try? makeEncoder().encode(msg) else { return }
        sendData(data, over: conn)
    }

    private func sendHello(_ hello: SyncHelloMessage, over conn: NWConnection) {
        let msg = SyncMessage.helloMessage(hello)
        guard let data = try? makeEncoder().encode(msg) else { return }
        sendData(data, over: conn)
    }

    private func sendAuth(_ auth: SyncAuthMessage, over conn: NWConnection) {
        let msg = SyncMessage.authMessage(auth)
        guard let data = try? makeEncoder().encode(msg) else { return }
        sendData(data, over: conn)
    }

    private func sendPayload(_ payload: PayloadV1, over conn: NWConnection) async throws {
        let msg = SyncMessage.payloadMessage(payload)
        let data = try makeEncoder().encode(msg)
        return try await withCheckedThrowingContinuation { continuation in
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "sync", metadata: [metadata])
            conn.send(content: data, contentContext: context, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func sendData(_ data: Data, over conn: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "sync", metadata: [metadata])
        conn.send(content: data, contentContext: context, completion: .contentProcessed { _ in })
    }

    // MARK: - Utilities

    private func makeParameters() -> NWParameters {
        let ws = NWProtocolWebSocket.Options(.version13)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3

        let params = NWParameters(tls: nil, tcp: tcp)
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true
        params.serviceClass = .responsiveData
        return params
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func setState(_ newState: SyncState) {
        state = newState
    }

    private func friendlyNetworkError(_ error: Error) -> String {
        let desc = error.localizedDescription
        if desc.contains("PolicyDenied") || desc.contains("65570") {
            return "Network discovery blocked by system policy. Try on a physical device."
        }
        return desc
    }

    private func reset() {
        receiveContinuation?.resume(returning: nil)
        receiveContinuation = nil
        bufferedPayload = nil
        peerInitiatedSync = false
        peerAuthVerified = false

        browser?.cancel()
        listener?.cancel()
        connection?.cancel()

        browser = nil
        listener = nil
        connection = nil
        peerEndpoints.removeAll()
        localHello = nil
        peerHello = nil

        setState(.idle)
    }
}
