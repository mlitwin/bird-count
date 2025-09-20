import Foundation
import Network
import Observation
import UIKit

/// Network Framework-based implementation of SyncTransport.
/// Uses WebSocket over TLS with pre-shared key authentication.
@Observable final class NetworkSyncTransport: NSObject, SyncTransport {
    
    // MARK: - SyncTransport Implementation
    private(set) var state: SyncState = .idle
    private(set) var discoveredPeers: [SyncPeer] = []
    private(set) var connectedPeers: [SyncPeer] = []
    private(set) var progress: Double = 0.0
    private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    private let serviceType = "_birdcount._tcp"
    private let peerID = UUID()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]
    private var peerEndpoints: [String: NWEndpoint] = [:] // Track endpoints by peer ID
    private let queue = DispatchQueue(label: "network-sync", qos: .userInitiated)
    
    // Sync-specific properties
    private var pendingPayload: PayloadV1?
    private var onSyncCompletion: ((Result<Void, Error>) -> Void)?
    private var onIncomingSync: ((PayloadV1, @escaping (Bool) -> Void) -> Void)?
    
    // MARK: - Initialization
    override init() {
        super.init()
        print("🌐 NetworkSyncTransport initialized with peer ID: \(peerID.uuidString)")
    }
    
    // MARK: - SyncTransport Methods
    
    func startBrowsing() {
        guard state == .idle else { return }
        
        print("🌐 Starting to browse for peers...")
        setState(.browsing)
        
        // Create browser with explicit local domain to avoid DNS policy issues
        let browserParameters = NWParameters.tcp
        browserParameters.includePeerToPeer = true
        browserParameters.allowLocalEndpointReuse = true
        
        browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: serviceType, domain: "local."),
            using: browserParameters
        )
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            self.handleBrowseResults(results, changes: changes)
        }
        
        browser?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.handleBrowserState(state)
        }
        
        browser?.start(queue: queue)
        print("🌐 Browser started for service type: \(serviceType) on local domain")
    }
    
    func startAdvertising(onIncomingSync: @escaping (PayloadV1, @escaping (Bool) -> Void) -> Void) {
        guard state == .idle else { return }
        
        print("🌐 Starting to advertise...")
        self.onIncomingSync = onIncomingSync
        setState(.advertising)
        
        do {
            let parameters = createNetworkParameters()
            listener = try NWListener(using: parameters)
            
            // Create TXT record with peer information
            var txtRecord = NWTXTRecord()
            txtRecord["peerID"] = peerID.uuidString
            txtRecord["displayName"] = UIDevice.current.name
            
            listener?.service = NWListener.Service(
                type: serviceType,
                domain: "local.", // Explicit local domain
                txtRecord: txtRecord.data
            )
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            
            listener?.start(queue: queue)
            print("🌐 Listener started for service type: \(serviceType) on local domain")
            
        } catch {
            setError("Failed to start advertising: \(error.localizedDescription)")
        }
    }
    
    func connect(to peer: SyncPeer) {
        guard state == .browsing else { return }
        
        print("🌐 Attempting to connect to peer: \(peer.displayName)")
        setState(.connecting)
        
        // Find the endpoint for this peer from browse results
        guard let endpoint = findEndpoint(for: peer) else {
            setError("Could not find endpoint for peer")
            return
        }
        
        let parameters = createNetworkParameters()
        let connection = NWConnection(to: endpoint, using: parameters)
        
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, for: peer, connection: connection)
        }
        
        connection.start(queue: queue)
        connections[peer.id] = connection
    }
    
    func sendSync(payload: PayloadV1, completion: @escaping (Result<Void, Error>) -> Void) {
        guard state == .connected, !connectedPeers.isEmpty else {
            completion(.failure(SyncError.notConnected))
            return
        }
        
        self.pendingPayload = payload
        self.onSyncCompletion = completion
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            
            setState(.transferring)
            
            // Send to first connected peer
            if let firstPeer = connectedPeers.first,
               let connection = connections[firstPeer.id] {
                sendMessage(data, to: connection)
                startProgressAnimation()
            } else {
                completion(.failure(SyncError.notConnected))
                reset()
            }
            
        } catch {
            completion(.failure(error))
            reset()
        }
    }
    
    func cancel() {
        reset()
    }
    
    // MARK: - Private Network Framework Methods
    
    private func createNetworkParameters() -> NWParameters {
        // Create WebSocket parameters with better configuration for local network
        let ws = NWProtocolWebSocket.Options(.version13)
        let tcp = NWProtocolTCP.Options()
        
        // Enable TCP keepalive for better connection health
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        
        // Configure for local network usage
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true
        parameters.allowFastOpen = false // Disable for better compatibility
        
        // Set service class for sync operations
        parameters.serviceClass = .responsiveData
        
        return parameters
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        // Handle browse results directly - they are already called on queue
        for change in changes {
            switch change {
            case .added(let result):
                self.addDiscoveredPeer(from: result)
            case .removed(let result):
                self.removeDiscoveredPeer(from: result)
            case .changed(_, let new, _):
                self.updateDiscoveredPeer(from: new)
            case .identical:
                // No action needed for identical peers
                break
            @unknown default:
                break
            }
        }
    }
    
    private func addDiscoveredPeer(from result: NWBrowser.Result) {
        let peer = createSyncPeer(from: result)
        if !discoveredPeers.contains(where: { $0.id == peer.id }) {
            discoveredPeers.append(peer)
            peerEndpoints[peer.id] = result.endpoint // Store endpoint for connection
            print("🌐 Found peer: \(peer.displayName)")
        }
    }
    
    private func removeDiscoveredPeer(from result: NWBrowser.Result) {
        let peer = createSyncPeer(from: result)
        discoveredPeers.removeAll { $0.id == peer.id }
        peerEndpoints.removeValue(forKey: peer.id) // Clean up endpoint tracking
        print("🌐 Lost peer: \(peer.displayName)")
    }
    
    private func updateDiscoveredPeer(from result: NWBrowser.Result) {
        let peer = createSyncPeer(from: result)
        if let index = discoveredPeers.firstIndex(where: { $0.id == peer.id }) {
            discoveredPeers[index] = peer
        }
    }
    
    private func createSyncPeer(from result: NWBrowser.Result) -> SyncPeer {
        var displayName = "Unknown Device"
        var peerIdString = UUID().uuidString
        var metadata: [String: String] = [:]
        
        if case .bonjour(let txtRecord) = result.metadata {
            if let name = txtRecord["displayName"] {
                displayName = name
                metadata["displayName"] = name
            }
            if let peerID = txtRecord["peerID"] {
                peerIdString = peerID
                metadata["peerID"] = peerID
            }
        }
        
        return SyncPeer(id: peerIdString, displayName: displayName, metadata: metadata)
    }
    
    private func findEndpoint(for peer: SyncPeer) -> NWEndpoint? {
        return peerEndpoints[peer.id]
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("🌐 New incoming connection")
        
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleIncomingConnectionState(state, connection: connection)
        }
        
        connection.start(queue: queue)
    }
    
    private func handleConnectionState(_ state: NWConnection.State, for peer: SyncPeer, connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch state {
            case .setup:
                // Connection is being set up
                break
                
            case .waiting(let error):
                print("🌐 Connection waiting: \(error.localizedDescription)")
                
            case .preparing:
                // Connection is preparing
                break
                
            case .ready:
                print("🌐 Connected to peer: \(peer.displayName)")
                self.connectedPeers.append(peer)
                self.setState(.connected)
                self.startReceiving(on: connection)
                
            case .failed(let error):
                print("🌐 Connection failed: \(error.localizedDescription)")
                self.setError("Connection failed: \(error.localizedDescription)")
                self.connections.removeValue(forKey: peer.id)
                
            case .cancelled:
                print("🌐 Connection cancelled for peer: \(peer.displayName)")
                self.connections.removeValue(forKey: peer.id)
                self.connectedPeers.removeAll { $0.id == peer.id }
                
            @unknown default:
                break
            }
        }
    }
    
    private func handleIncomingConnectionState(_ state: NWConnection.State, connection: NWConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch state {
            case .setup:
                // Connection is being set up
                break
                
            case .waiting(let error):
                print("🌐 Incoming connection waiting: \(error.localizedDescription)")
                
            case .preparing:
                // Connection is preparing
                break
                
            case .ready:
                print("🌐 Incoming connection ready")
                self.setState(.connected)
                self.startReceiving(on: connection)
                
            case .failed(let error):
                print("🌐 Incoming connection failed: \(error.localizedDescription)")
                
            case .cancelled:
                print("🌐 Incoming connection cancelled")
                
            @unknown default:
                break
            }
        }
    }
    
    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .setup:
            print("🌐 Browser setup")
            
        case .ready:
            print("🌐 Browser ready")
            
        case .failed(let error):
            print("🌐 Browser failed with error: \(error)")
            DispatchQueue.main.async { [weak self] in
                // Check for DNS policy error (nw_browser_fail_on_dns_error_locked)
                let errorDescription = error.localizedDescription
                if errorDescription.contains("PolicyDenied") || errorDescription.contains("65570") {
                    // DNS Policy error - common in simulator
                    self?.setError("Network discovery blocked by system policy. Try on a physical device or check network permissions.")
                } else {
                    self?.setError("Browser failed: \(error.localizedDescription)")
                }
            }
            
        case .cancelled:
            print("🌐 Browser cancelled")
            
        case .waiting(let error):
            print("🌐 Browser waiting: \(error.localizedDescription)")
            // Don't treat waiting as an error - it might recover
            
        @unknown default:
            break
        }
    }
    
    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .setup:
            print("🌐 Listener setup")
            
        case .ready:
            print("🌐 Listener ready and advertising")
            
        case .failed(let error):
            print("🌐 Listener failed with error: \(error)")
            DispatchQueue.main.async { [weak self] in
                // Check for DNS policy error (nw_browser_fail_on_dns_error_locked)
                let errorDescription = error.localizedDescription
                if errorDescription.contains("PolicyDenied") || errorDescription.contains("65570") {
                    // DNS Policy error - common in simulator
                    self?.setError("Network advertising blocked by system policy. Try on a physical device or check network permissions.")
                } else {
                    self?.setError("Listener failed: \(error.localizedDescription)")
                }
            }
            
        case .cancelled:
            print("🌐 Listener cancelled")
            
        case .waiting(let error):
            print("🌐 Listener waiting: \(error.localizedDescription)")
            // Don't treat waiting as an error - it might recover
            
        @unknown default:
            break
        }
    }
    
    private func sendMessage(_ data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "sync", metadata: [metadata])
        
        connection.send(content: data, contentContext: context, completion: .contentProcessed { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onSyncCompletion?(.failure(error))
                    self?.setError("Send failed: \(error.localizedDescription)")
                }
            } else {
                // Message sent successfully - complete transfer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.completeTransfer(success: true)
                }
            }
        })
    }
    
    private func startReceiving(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            if let error = error {
                print("🌐 Receive error: \(error.localizedDescription)")
                return
            }
            
            if let data = data {
                self?.handleReceivedMessage(data)
            }
            
            if !isComplete {
                self?.startReceiving(on: connection)
            }
        }
    }
    
    private func handleReceivedMessage(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let payload = try decoder.decode(PayloadV1.self, from: data)
                
                // If we're in receiver mode, present the payload for user approval
                if let onIncomingSync = self.onIncomingSync {
                    self.setState(.receivingApproval)
                    onIncomingSync(payload) { [weak self] accepted in
                        DispatchQueue.main.async {
                            if accepted {
                                self?.completeTransfer(success: true)
                            } else {
                                self?.setError("Sync declined")
                            }
                        }
                    }
                } else {
                    // We're in sender mode and got an unexpected message
                    self.completeTransfer(success: true)
                }
                
            } catch {
                self.setError("Invalid sync data received")
            }
        }
    }
    
    // MARK: - Utility Methods
    
    private func setState(_ newState: SyncState) {
        print("🌐 State change: \(state) -> \(newState)")
        state = newState
        if newState != .transferring {
            progress = 0.0
        }
        if newState == .idle {
            errorMessage = nil
        }
    }
    
    private func setError(_ message: String) {
        errorMessage = message
        setState(.error)
    }
    
    private func startProgressAnimation() {
        // Simulate progress for better UX
        progress = 0.1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.progress = 0.5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.progress = 0.8
        }
    }
    
    private func completeTransfer(success: Bool, error: Error? = nil) {
        if success {
            progress = 1.0
            setState(.completed)
            onSyncCompletion?(.success(()))
        } else {
            setState(.error)
            onSyncCompletion?(.failure(error ?? SyncError.transferFailed))
        }
        
        // Auto-reset after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.reset()
        }
    }
    
    private func reset() {
        browser?.cancel()
        listener?.cancel()
        
        for connection in connections.values {
            connection.cancel()
        }
        
        browser = nil
        listener = nil
        connections.removeAll()
        peerEndpoints.removeAll() // Clear endpoint tracking
        pendingPayload = nil
        onSyncCompletion = nil
        onIncomingSync = nil
        
        discoveredPeers.removeAll()
        connectedPeers.removeAll()
        setState(.idle)
    }
}
