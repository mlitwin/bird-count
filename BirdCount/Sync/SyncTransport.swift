import Foundation

// MARK: - State

enum SyncState: Equatable {
    case idle
    case discovering
    case handshaking(peerName: String)
    case readyToSync(info: SyncReadyInfo)
    case transferring
    case completed(stats: SyncCompletionStats)
    case incompatible(reason: String)
    case error(message: String)
}

// MARK: - Errors

enum SyncError: Error, LocalizedError {
    case notConnected
    case transferFailed
    case cancelled
    case networkUnavailable
    case incompatibleRoles
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notConnected: return "No device connected for sync"
        case .transferFailed: return "Sync transfer failed"
        case .cancelled: return "Sync was cancelled"
        case .networkUnavailable: return "Network unavailable for sync"
        case .incompatibleRoles: return "Both devices have incompatible sync roles"
        case .invalidData: return "Invalid sync data received"
        }
    }
}

// MARK: - Protocol

protocol SyncTransport: AnyObject {
    var state: SyncState { get }

    /// True when the peer has sent a syncStart message. The VM uses this to auto-initiate the
    /// non-initiator's side of a bidirectional sync without requiring a user tap on both devices.
    var peerInitiatedSync: Bool { get }

    /// Start advertising and browsing simultaneously. The hello is sent to any peer that connects.
    func startDiscovery(localHello: SyncHelloMessage)

    /// Initiate transfer once in .readyToSync. Pass the payload to send, or nil if receiveOnly.
    /// The transport is responsible for importing received data.
    func initiateSync(payload: PayloadV1?, receiveInto store: ObservationStore) async

    /// Cancel everything and return to .idle.
    func cancel()
}
