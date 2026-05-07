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
    let peerID: UUID
    let rolePreference: SyncRolePreference
    /// nil when rolePreference is .receiveOnly or there is nothing to send
    let sendSummary: SyncSendSummary?
}

// MARK: - Wire Message Envelope

struct SyncMessage: Codable {
    let version: Int
    let type: MessageType
    var hello: SyncHelloMessage?
    var payload: PayloadV1?

    enum MessageType: String, Codable {
        case hello
        case payload
        case syncStart
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
}

// MARK: - Ready-to-Sync Info

struct SyncReadyInfo: Equatable {
    let peerName: String
    /// Summary of what the peer will send us; nil if they will not send
    let peerWillSend: SyncSendSummary?
    /// Whether we will send to the peer
    let localWillSend: Bool

    /// Negotiate roles between local and peer hello messages.
    /// Returns nil when the combination is incompatible (nothing would transfer).
    static func negotiate(local: SyncHelloMessage, peer: SyncHelloMessage) -> SyncReadyInfo? {
        let localRole = local.rolePreference
        let peerRole = peer.rolePreference
        guard !localRole.isIncompatible(with: peerRole) else { return nil }
        return SyncReadyInfo(
            peerName: peer.displayName,
            peerWillSend: localRole.localShouldReceive(peerPrefers: peerRole) ? peer.sendSummary : nil,
            localWillSend: localRole.localShouldSend(peerPrefers: peerRole)
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
