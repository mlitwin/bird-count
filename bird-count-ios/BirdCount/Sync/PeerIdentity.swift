import CryptoKit
import Foundation

/// Stable per-install sync identity: a Curve25519 signing keypair kept in the
/// Keychain. The public key's fingerprint doubles as the device's stable peer
/// id, so paired devices can recognize each other across sessions, and the
/// keypair lets a connection prove it belongs to a paired identity (signature
/// over the session nonces) rather than merely claiming a peer id string.
struct PeerIdentity {
    let privateKey: Curve25519.Signing.PrivateKey

    var publicKey: Data { privateKey.publicKey.rawRepresentation }

    /// Stable peer id: first 16 bytes of SHA256(publicKey) as a UUID.
    var peerID: UUID { Self.peerID(forPublicKey: publicKey) }

    static func peerID(forPublicKey publicKey: Data) -> UUID {
        let digest = SHA256.hash(data: publicKey)
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    // MARK: - Session authentication

    /// Domain separator so these signatures can never be confused with any
    /// other use of the key.
    private static let context = Data("birdcount-p2p-auth-v1".utf8)

    /// Sign this session: proves possession of the private key, bound to the
    /// fresh nonces of both sides so it cannot be replayed in a later session.
    func signSession(localNonce: Data, peerNonce: Data) -> Data? {
        try? privateKey.signature(for: Self.context + localNonce + peerNonce)
    }

    /// Verify the peer's session signature. The peer signed (its nonce, then
    /// ours), so the transcript is reconstructed in that order.
    static func verifySession(
        signature: Data,
        publicKey: Data,
        peerNonce: Data,
        localNonce: Data
    ) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            return false
        }
        return key.isValidSignature(signature, for: context + peerNonce + localNonce)
    }

    static func makeNonce() -> Data {
        Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
    }

    // MARK: - Persistence

    private static let keychainService = "org.antoninus.birdcount.sync"
    private static let keychainAccount = "peer-identity-key"

    /// Load the install's identity, creating and persisting one on first use.
    static func loadOrCreate(keychain: KeychainStore = KeychainStore(service: keychainService)) -> PeerIdentity {
        if let raw = keychain.data(for: keychainAccount),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return PeerIdentity(privateKey: key)
        }
        let key = Curve25519.Signing.PrivateKey()
        keychain.set(key.rawRepresentation, for: keychainAccount)
        return PeerIdentity(privateKey: key)
    }
}
