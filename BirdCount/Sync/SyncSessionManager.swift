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
    
    
    // MARK: - Initialization
    init() {
        // Always use Network Framework transport
        self.transport = NetworkSyncTransport()
        print("🔄 SyncSessionManager initialized with Network Framework transport")
    }
    
    // MARK: - Public API (forwarded to transport)
    
    /// Start browsing for peers to sync with (sender mode)
    func startBrowsing() {
        transport.startBrowsing()
    }
    
    /// Start advertising for incoming sync requests (receiver mode)
    func startAdvertising(onIncomingSync: @escaping (PayloadV1, @escaping (Bool) -> Void) -> Void) {
        transport.startAdvertising(onIncomingSync: onIncomingSync)
    }
    
    /// Connect to a discovered peer (sender initiates connection)
    func connect(to peer: SyncPeer) {
        transport.connect(to: peer)
    }
    
    /// Send sync payload to connected peer
    func sendSync(payload: PayloadV1, completion: @escaping (Result<Void, Error>) -> Void) {
        transport.sendSync(payload: payload, completion: completion)
    }
    
    /// Cancel current operation and reset to idle
    func cancel() {
        transport.cancel()
    }
}


