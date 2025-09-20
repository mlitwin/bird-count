import Foundation
import Observation
import UIKit

/// Manager for observation sync sessions using pluggable transport implementations.
/// Handles peer discovery, connection management, and data transfer through SyncTransport protocol.
@Observable final class SyncSessionManager {
    
    // MARK: - Transport Selection
    private let transport: SyncTransport
    
    // MARK: - Public State (forwarded from transport)
    var state: SyncState { transport.state }
    var discoveredPeers: [SyncPeer] { transport.discoveredPeers }
    var connectedPeers: [SyncPeer] { transport.connectedPeers }
    var progress: Double { transport.progress }
    var errorMessage: String? { transport.errorMessage }
    
    // MARK: - Sync Success State
    private(set) var lastSentRecordCount: Int = 0
    private(set) var lastReceivedRecordCount: Int = 0
    
    
    // MARK: - Initialization
    init() {
        // Always use Network Framework transport
        self.transport = NetworkSyncTransport()
        print("🔄 SyncSessionManager initialized with Network Framework transport")
    }
    
    // MARK: - Public API (forwarded to transport)
    
    /// Start browsing for peers to sync with (sender mode)
    func startBrowsing() {
        resetSyncCounts()
        transport.startBrowsing()
    }
    
    /// Start advertising for incoming sync requests (receiver mode)
    func startAdvertising(onIncomingSync: @escaping (PayloadV1, @escaping (Bool) -> Void) -> Void) {
        resetSyncCounts()
        
        // Wrap the completion to track received record count
        transport.startAdvertising { [weak self] payload, completion in
            // Store record count when sync is received
            self?.lastReceivedRecordCount = payload.observations.count
            
            // Forward to original handler
            onIncomingSync(payload, completion)
        }
    }
    
    /// Connect to a discovered peer (sender initiates connection)
    func connect(to peer: SyncPeer) {
        transport.connect(to: peer)
    }
    
    /// Send sync payload to connected peer
    func sendSync(payload: PayloadV1, completion: @escaping (Result<Void, Error>) -> Void) {
        // Store record count for success feedback
        lastSentRecordCount = payload.observations.count
        
        transport.sendSync(payload: payload, completion: completion)
    }
    
    /// Cancel current operation and reset to idle
    func cancel() {
        resetSyncCounts()
        transport.cancel()
    }
    
    // MARK: - Private Methods
    
    /// Reset sync success counts (called when starting new sync operations)
    private func resetSyncCounts() {
        lastSentRecordCount = 0
        lastReceivedRecordCount = 0
    }
}


