import SwiftUI

/// Compact header badge showing how many observations are still queued for
/// delivery (cloud and/or paired devices), with a spinner while a sync is
/// running so the count visibly ticks down. Renders nothing when everything
/// is delivered or when the user has no sync destinations at all.
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
                    Text(countText)
                        .font(.caption.weight(.semibold).monospacedDigit())
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

    private var queuedCount: Int {
        SyncQueue.undeliveredIds(
            cloudDirty: observations.dirtyIds,
            cloudIsDestination: cloudAuth.isSignedIn,
            peerPending: pairedPeers.peers.map { $0.pendingIds }
        ).count
    }

    private var isActive: Bool {
        cloudSync.isSyncing || autoSync.isExchanging
    }

    private var hasCloudError: Bool {
        guard cloudAuth.isSignedIn, case .failure = cloudSync.state else { return false }
        return true
    }

    /// No destinations -> nothing to promise, so no badge. Otherwise show
    /// while anything is queued or a sync is running.
    private var isVisible: Bool {
        let hasDestinations = cloudAuth.isSignedIn || !pairedPeers.peers.isEmpty
        return hasDestinations && (queuedCount > 0 || isActive)
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
