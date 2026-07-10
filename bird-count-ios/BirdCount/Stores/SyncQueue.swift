import Foundation

/// Semantics for the header sync badge: which observations count as
/// "not sent yet".
public enum SyncQueue {
    /// Distinct observations not yet delivered to every live destination:
    /// the union of the cloud dirty set and each paired peer's pending queue.
    /// The number stays visible while ANY destination is missing something —
    /// that is the warning the badge exists to give.
    ///
    /// The cloud set only counts when the cloud is a real destination
    /// (signed in); otherwise dirty ids would keep the badge lit forever for
    /// users who never use cloud sync.
    public static func undeliveredIds(
        cloudDirty: Set<UUID>,
        cloudIsDestination: Bool,
        peerPending: some Collection<Set<UUID>>
    ) -> Set<UUID> {
        var result: Set<UUID> = cloudIsDestination ? cloudDirty : []
        for pending in peerPending {
            result.formUnion(pending)
        }
        return result
    }
}
