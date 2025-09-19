import Foundation
import MultipeerConnectivity
import Observation
import UIKit

/// Manager for MultipeerConnectivity-based observation sync sessions.
/// Handles peer discovery, connection management, and data transfer.
@Observable final class SyncSessionManager: NSObject {
    
    // MARK: - Public State
    private(set) var state: SyncState = .idle
    private(set) var discoveredPeers: [MCPeerID] = []
    private(set) var connectedPeers: [MCPeerID] = []
    private(set) var progress: Double = 0.0
    private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    private let serviceType = "birdcount"  // Simplified service type name
    private let localPeerID: MCPeerID
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var transferCompleted = false
    
    // Sync-specific properties
    private var pendingPayload: PayloadV1?
    private var onSyncCompletion: ((Result<Void, Error>) -> Void)?
    private var onIncomingSync: ((PayloadV1, @escaping (Bool) -> Void) -> Void)?
    
    // MARK: - Initialization
    override init() {
        // Create a unique peer ID for this device
        let deviceName = UIDevice.current.name
        self.localPeerID = MCPeerID(displayName: deviceName)
        super.init()
        print("🔄 SyncSessionManager initialized with peer ID: \(deviceName)")
    }
    
    // MARK: - Public API
    
    /// Start browsing for peers to sync with (sender mode)
    func startBrowsing() {
        guard state == .idle else { return }
        
        print("🔍 Starting to browse for peers...")
        setState(.browsing)
        setupSession()
        
        browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        print("🔍 Browser started for service type: \(serviceType)")
    }
    
    /// Start advertising for incoming sync requests (receiver mode)
    func startAdvertising(onIncomingSync: @escaping (PayloadV1, @escaping (Bool) -> Void) -> Void) {
        guard state == .idle else { return }
        
        print("📢 Starting to advertise...")
        self.onIncomingSync = onIncomingSync
        setState(.advertising)
        setupSession()
        
        advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        print("📢 Advertiser started for service type: \(serviceType)")
    }
    
    /// Connect to a discovered peer (sender initiates connection)
    func connect(to peer: MCPeerID) {
        guard state == .browsing, let browser = browser else { return }
        
        print("🤝 Attempting to connect to peer: \(peer.displayName)")
        setState(.connecting)
        browser.invitePeer(peer, to: session!, withContext: nil, timeout: 30)
    }
    
    /// Send sync payload to connected peer
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
            try session?.send(data, toPeers: connectedPeers, with: .reliable)
            
            // Simulate progress for user feedback
            startProgressAnimation()
            
            // Mark transfer as completed for sender side
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.completeTransfer(success: true)
            }
            
        } catch {
            completion(.failure(error))
            reset()
        }
    }
    
    /// Cancel current operation and reset to idle
    func cancel() {
        reset()
    }
    
    // MARK: - Private Methods
    
    private func setupSession() {
        print("🔧 Setting up MCSession...")
        session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        print("🔧 MCSession created with encryption required")
    }
    
    private func setState(_ newState: SyncState) {
        print("🔄 State change: \(state) -> \(newState)")
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
    
    private func reset() {
        browser?.stopBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        
        browser = nil
        advertiser = nil
        session = nil
        pendingPayload = nil
        onSyncCompletion = nil
        onIncomingSync = nil
        transferCompleted = false  // Reset the transfer completion flag
        
        discoveredPeers.removeAll()
        connectedPeers.removeAll()
        setState(.idle)
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
            transferCompleted = true  // Mark transfer as successful
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
}

// MARK: - MCNearbyServiceBrowserDelegate
extension SyncSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🔍 Found peer: \(peerID.displayName)")
        DispatchQueue.main.async { [weak self] in
            self?.discoveredPeers.append(peerID)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("🔍 Lost peer: \(peerID.displayName)")
        DispatchQueue.main.async { [weak self] in
            self?.discoveredPeers.removeAll { $0 == peerID }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Browser failed to start: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.setError("Failed to start browsing: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate  
extension SyncSessionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📢 Received invitation from peer: \(peerID.displayName)")
        // Accept the invitation
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Advertiser failed to start: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            self?.setError("Failed to start advertising: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension SyncSessionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("🔗 Peer \(peerID.displayName) changed state to: \(state.rawValue)")
        DispatchQueue.main.async { [weak self] in
            switch state {
            case .connected:
                print("✅ Connected to peer: \(peerID.displayName)")
                self?.connectedPeers.append(peerID)
                self?.setState(.connected)
                
            case .connecting:
                print("🔄 Connecting to peer: \(peerID.displayName)")
                break // Keep current state
                
            case .notConnected:
                print("❌ Disconnected from peer: \(peerID.displayName)")
                self?.connectedPeers.removeAll { $0 == peerID }
                if self?.connectedPeers.isEmpty == true {
                    // Only show error if transfer wasn't completed successfully
                    if self?.transferCompleted != true {
                        self?.setError("Connection lost")
                    } else {
                        // Transfer was successful, just clean up
                        self?.setState(.completed)
                    }
                }
                
            @unknown default:
                print("⚠️ Unknown session state: \(state.rawValue)")
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
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
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for sync
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used for sync
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used for sync
    }
}

// MARK: - Supporting Types
enum SyncState {
    case idle
    case browsing
    case advertising
    case connecting
    case connected
    case transferring
    case receivingApproval
    case completed
    case error
}

enum SyncError: Error, LocalizedError {
    case notConnected
    case transferFailed
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No device connected for sync"
        case .transferFailed:
            return "Sync transfer failed"
        case .cancelled:
            return "Sync was cancelled"
        }
    }
}
