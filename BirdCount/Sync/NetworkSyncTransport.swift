import Foundation
import Network
import Observation
import UIKit

@Observable final class NetworkSyncTransport: SyncTransport {

    // MARK: - SyncTransport

    private(set) var state: SyncState = .idle

    // MARK: - Private

    private let serviceType = "_birdcount._tcp"
    private let peerID = UUID()
    private let queue = DispatchQueue(label: "network-sync", qos: .userInitiated)

    private var listener: NWListener?
    private var browser: NWBrowser?

    // The single active connection (first one that completes handshake wins)
    private var connection: NWConnection?
    private var peerConnection: NWConnection?  // incoming connection before peer ID known

    // Peer endpoints keyed by peerID string
    private var peerEndpoints: [String: NWEndpoint] = [:]

    private var localHello: SyncHelloMessage?
    private var peerHello: SyncHelloMessage?

    // Continuation for initiateSync to wait on incoming payload
    private var receiveContinuation: CheckedContinuation<PayloadV1?, Never>?

    // MARK: - SyncTransport Methods

    func startDiscovery(localHello: SyncHelloMessage) {
        guard state == .idle else { return }
        self.localHello = localHello
        setState(.discovering)
        startListener(localHello: localHello)
        startBrowser()
    }

    func initiateSync(payload: PayloadV1?, receiveInto store: ObservationStore) async {
        guard case .readyToSync(let info) = state,
              let conn = connection else { return }

        setState(.transferring)

        if info.localWillSend, let payload {
            do {
                try await sendPayload(payload, over: conn)
            } catch {
                setState(.error(message: "Send failed: \(error.localizedDescription)"))
                return
            }
        }

        var receivedCount = 0
        var duplicatesSkipped = 0

        if info.peerWillSend != nil {
            let incoming = await withCheckedContinuation { continuation in
                self.receiveContinuation = continuation
            }
            if let incoming {
                let stats = try? ObservationImportService.importFromSync(incoming, into: store)
                receivedCount = stats?.newRecordsImported ?? 0
                duplicatesSkipped = stats?.duplicatesSkipped ?? 0
            }
        }

        // Connection failure resumes the continuation with nil and sets .error state.
        // Don't overwrite that with .completed.
        guard case .transferring = state else { return }

        let stats = SyncCompletionStats(
            sentCount: payload?.observations.count ?? 0,
            receivedCount: receivedCount,
            duplicatesSkipped: duplicatesSkipped
        )
        setState(.completed(stats: stats))
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
                } else if case .transferring = self.state {
                    // Payload already received (or send-only path). The connection
                    // dropped after the data transferred — let initiateSync finish.
                } else {
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
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data {
                self.handleReceivedData(data)
            }
            if error == nil {
                self.startReceiving(on: conn)
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
            }
        }
    }

    private func handlePeerHello(_ peerHello: SyncHelloMessage) {
        guard let localHello else { return }
        self.peerHello = peerHello

        if let info = SyncReadyInfo.negotiate(local: localHello, peer: peerHello) {
            setState(.readyToSync(info: info))
        } else {
            setState(.incompatible(reason: "Both devices have the same directional role"))
        }
    }

    private func handleIncomingPayload(_ payload: PayloadV1) {
        if let continuation = receiveContinuation {
            receiveContinuation = nil
            continuation.resume(returning: payload)
        }
    }

    // MARK: - Send helpers

    private func sendHello(_ hello: SyncHelloMessage, over conn: NWConnection) {
        let msg = SyncMessage.helloMessage(hello)
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
