import Foundation

/// Semantics for the header sync badge: which observations count as
/// "about to be sent".
public enum SyncQueue {
    /// Distinct observations queued for destinations that are REACHABLE right
    /// now: the cloud dirty set when the cloud can actually deliver (signed
    /// in, on Wi-Fi, auto-sync on), plus each pending queue whose paired peer
    /// is currently present. The badge shows what leaving the app would
    /// interrupt — not the full latent backlog (a partner's phone that has
    /// been out of range all day doesn't light the header; UserView carries
    /// the complete queue story).
    public static func imminentUndeliveredIds(
        cloudDirty: Set<UUID>,
        cloudReachable: Bool,
        peerPending: [UUID: Set<UUID>],
        presentPeers: Set<UUID>
    ) -> Set<UUID> {
        var result: Set<UUID> = cloudReachable ? cloudDirty : []
        for (peerID, pending) in peerPending where presentPeers.contains(peerID) {
            result.formUnion(pending)
        }
        return result
    }
}
