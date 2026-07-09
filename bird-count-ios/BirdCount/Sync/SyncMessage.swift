import Foundation

// MARK: - Role Preference

enum SyncRolePreference: String, Codable, CaseIterable {
    case sendAndReceive
    case sendOnly
    case receiveOnly

    var label: String {
        switch self {
        case .sendAndReceive: return "Both"
        case .sendOnly: return "Send only"
        case .receiveOnly: return "Receive only"
        }
    }
}

// MARK: - Send Summary

struct SyncSendSummary: Codable, Equatable {
    let observationCount: Int
    let speciesCount: Int
    let dateRangeBegin: Date
    let dateRangeEnd: Date
}

// MARK: - Hello Message

struct SyncHelloMessage: Codable, Equatable {
    let displayName: String
    /// Stable identity id when the sender has a PeerIdentity (the transport
    /// stamps it before sending); a throwaway UUID for legacy senders.
    var peerID: UUID
    let rolePreference: SyncRolePreference
    /// nil when rolePreference is .receiveOnly or there is nothing to send
    let sendSummary: SyncSendSummary?
    /// Identity fields, stamped by the transport. Absent on legacy (pre-pairing)
    /// app versions; all handling must tolerate nil.
    var publicKey: Data? = nil
    var nonce: Data? = nil
}

// MARK: - Auth Message

/// Proof of identity for this session: a signature over both sides' hello
/// nonces (see PeerIdentity.signSession). Sent only after receiving a hello
/// that carries a publicKey — legacy peers never see this message type.
struct SyncAuthMessage: Codable, Equatable {
    let signature: Data
}

// MARK: - Wire Message Envelope

struct SyncMessage: Codable {
    let version: Int
    let type: MessageType
    var hello: SyncHelloMessage?
    var payload: PayloadV1?
    var auth: SyncAuthMessage? = nil

    enum MessageType: String, Codable {
        case hello
        case payload
        case syncStart
        // Only sent to peers whose hello carried a publicKey, so legacy
        // decoders never encounter this case.
        case auth
    }

    static func helloMessage(_ hello: SyncHelloMessage) -> SyncMessage {
        SyncMessage(version: 2, type: .hello, hello: hello, payload: nil)
    }

    static func payloadMessage(_ payload: PayloadV1) -> SyncMessage {
        SyncMessage(version: 2, type: .payload, hello: nil, payload: payload)
    }

    static func syncStartMessage() -> SyncMessage {
        SyncMessage(version: 2, type: .syncStart, hello: nil, payload: nil)
    }

    static func authMessage(_ auth: SyncAuthMessage) -> SyncMessage {
        SyncMessage(version: 2, type: .auth, hello: nil, payload: nil, auth: auth)
    }
}

// MARK: - Ready-to-Sync Info

struct SyncReadyInfo: Equatable {
    let peerName: String
    /// Summary of what the peer will send us; nil if they will not send
    let peerWillSend: SyncSendSummary?
    /// Whether we will send to the peer
    let localWillSend: Bool
    /// The peer's stable identity id (throwaway UUID for legacy peers).
    var peerID: UUID = UUID()
    /// The peer's identity public key, only set when its session signature
    /// verified. Pairing must store exactly this key.
    var peerPublicKey: Data? = nil
    /// True when the peer proved possession of peerPublicKey this session.
    var peerVerified: Bool = false

    /// Negotiate roles between local and peer hello messages.
    /// Returns nil when the combination is incompatible (nothing would transfer).
    /// `verified` is the transport's auth-handshake outcome; the peer's public
    /// key is only carried over when it verified.
    static func negotiate(local: SyncHelloMessage, peer: SyncHelloMessage, verified: Bool = false) -> SyncReadyInfo? {
        let localRole = local.rolePreference
        let peerRole = peer.rolePreference
        guard !localRole.isIncompatible(with: peerRole) else { return nil }
        return SyncReadyInfo(
            peerName: peer.displayName,
            peerWillSend: localRole.localShouldReceive(peerPrefers: peerRole) ? peer.sendSummary : nil,
            localWillSend: localRole.localShouldSend(peerPrefers: peerRole),
            peerID: peer.peerID,
            peerPublicKey: verified ? peer.publicKey : nil,
            peerVerified: verified
        )
    }
}

// MARK: - Completion Stats

struct SyncCompletionStats: Equatable {
    let sentCount: Int
    let receivedCount: Int
    let duplicatesSkipped: Int
}

// MARK: - Role Negotiation

extension SyncRolePreference {
    /// Returns whether local device should send, given the peer's preference.
    func localShouldSend(peerPrefers peer: SyncRolePreference) -> Bool {
        switch self {
        case .sendAndReceive: return peer != .sendOnly
        case .sendOnly: return peer != .sendOnly
        case .receiveOnly: return false
        }
    }

    /// Returns whether local device should receive, given the peer's preference.
    func localShouldReceive(peerPrefers peer: SyncRolePreference) -> Bool {
        switch self {
        case .sendAndReceive: return peer != .receiveOnly
        case .sendOnly: return false
        case .receiveOnly: return peer != .receiveOnly
        }
    }

    /// Returns true when the role combination is incompatible (nothing would transfer).
    func isIncompatible(with peer: SyncRolePreference) -> Bool {
        return !localShouldSend(peerPrefers: peer) && !localShouldReceive(peerPrefers: peer)
    }
}
