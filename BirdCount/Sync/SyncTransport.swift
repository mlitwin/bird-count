import Foundation

/// Protocol abstraction for different sync transport implementations.
/// Primary implementation uses Network Framework with WebSocket over TLS.
protocol SyncTransport {
    // MARK: - State
    var state: SyncState { get }
    var discoveredPeers: [SyncPeer] { get }
    var connectedPeers: [SyncPeer] { get }
    var progress: Double { get }
    var errorMessage: String? { get }
    
    // MARK: - Discovery
    /// Start browsing for peers to sync with (sender mode)
    func startBrowsing()
    
    /// Start advertising for incoming sync requests (receiver mode)
    func startAdvertising(onIncomingSync: @escaping (PayloadV1, @escaping (Bool) -> Void) -> Void)
    
    // MARK: - Connection
    /// Connect to a discovered peer (sender initiates connection)
    func connect(to peer: SyncPeer)
    
    /// Send sync payload to connected peer
    func sendSync(payload: PayloadV1, completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Cancel current operation and reset to idle
    func cancel()
}

/// Common peer representation that works across different transport implementations
struct SyncPeer: Identifiable, Equatable {
    let id: String
    let displayName: String
    let metadata: [String: String]
    
    static func == (lhs: SyncPeer, rhs: SyncPeer) -> Bool {
        lhs.id == rhs.id
    }
}

/// Common sync states used by all transport implementations
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

/// Common sync errors
enum SyncError: Error, LocalizedError {
    case notConnected
    case transferFailed
    case cancelled
    case networkUnavailable
    case securityError
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No device connected for sync"
        case .transferFailed:
            return "Sync transfer failed"
        case .cancelled:
            return "Sync was cancelled"
        case .networkUnavailable:
            return "Network unavailable for sync"
        case .securityError:
            return "Security error during sync"
        case .timeout:
            return "Sync connection timed out"
        }
    }
}
