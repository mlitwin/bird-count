import SwiftUI

/// Compact header badge showing what a sync is doing or about to do RIGHT
/// NOW: a spinner while an exchange runs, and a count of observations queued
/// for destinations that are currently reachable (a paired phone in range, or
/// the cloud when signed in + Wi-Fi + auto-sync). Latent backlog for
/// unreachable destinations does not light the header — the full queue story
/// lives in UserView, one tap away.
struct SyncStatusBadge: View {
    /// Tap action — the header opens UserView, where the number is explained
    /// (cloud status + paired device queues).
    let action: () -> Void

    @Environment(ObservationStore.self) private var observations
    @Environment(PairedPeersStore.self) private var pairedPeers
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(CloudAuthService.self) private var cloudAuth
    @Environment(PeerAutoSyncService.self) private var autoSync

    var body: some View {
        if isVisible {
            Button(action: action) {
                HStack(spacing: 4) {
                    if isActive {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: hasCloudError ? "exclamationmark.arrow.circlepath" : "arrow.up")
                            .font(.caption2.weight(.semibold))
                    }
                    if queuedCount > 0 {
                        Text(countText)
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .foregroundStyle(hasCloudError ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            .accessibilityLabel(accessibilityText)
        }
    }

    // MARK: - Derived state

    /// Cloud will deliver on its own shortly: signed in, on Wi-Fi, and
    /// auto-sync enabled. Otherwise cloud dirt is latent, not imminent.
    private var cloudReachable: Bool {
        cloudAuth.isSignedIn && cloudSync.isOnWifi && cloudSync.autoSyncEnabled
    }

    private var queuedCount: Int {
        SyncQueue.imminentUndeliveredIds(
            cloudDirty: observations.dirtyIds,
            cloudReachable: cloudReachable,
            peerPending: Dictionary(uniqueKeysWithValues: pairedPeers.peers.map { ($0.id, $0.pendingIds) }),
            presentPeers: autoSync.presentPeerIDs
        ).count
    }

    private var isActive: Bool {
        cloudSync.isSyncing || autoSync.isExchanging
    }

    private var hasCloudError: Bool {
        guard cloudAuth.isSignedIn, case .failure = cloudSync.state else { return false }
        return true
    }

    /// Visible only when something is happening or about to: an exchange in
    /// flight, or records queued for a destination that can take them now.
    private var isVisible: Bool {
        isActive || queuedCount > 0
    }

    private var countText: String {
        queuedCount > 999 ? "999+" : "\(queuedCount)"
    }

    private var accessibilityText: String {
        if isActive {
            return String(format: Strings.Sync.badgeSyncing.string, queuedCount)
        }
        return String(format: Strings.Sync.badgeQueued.string, queuedCount)
    }
}

#if DEBUG
#Preview("Queued") {
    let store = ObservationStore()
    store.addObservation("amecro")
    store.addObservation("norcar")
    let auth = CloudAuthService()
    let peers = PairedPeersStore()
    return SyncStatusBadge(action: {})
        .environment(store)
        .environment(peers)
        .environment(auth)
        .environment(CloudSyncService(auth: auth))
        .environment(PeerAutoSyncService(
            observationStore: store,
            settingsStore: SettingsStore(),
            pairedPeers: peers
        ))
        .padding()
}
#endif
