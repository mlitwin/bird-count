import SwiftUI

/// Compact header badge showing sync activity. Always visible — idle state
/// uses a static icon; the spinner runs only during an active transfer. Tap
/// opens `SyncStatusSheet` as a sheet.
struct SyncStatusBadge: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(PairedPeersStore.self) private var pairedPeers
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(PeerAutoSyncService.self) private var autoSync

    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            Group {
                if isActive {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.headline)
                }
            }
            .padding(8)
            .background(Circle().fill(Color(.secondarySystemBackground)))
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel(accessibilityText)
        .sheet(isPresented: $showSheet) {
            SyncStatusSheet()
        }
    }

    // MARK: - Derived state

    /// Total observations queued for any destination, reachable or not.
    /// Reaches zero only when everything has been delivered everywhere.
    private var queuedCount: Int {
        var ids = observations.dirtyIds
        for peer in pairedPeers.peers { ids.formUnion(peer.pendingIds) }
        return ids.count
    }

    private var isActive: Bool {
        cloudSync.isSyncing || autoSync.isExchanging
    }

    private var accessibilityText: String {
        if isActive {
            return String(format: Strings.Sync.badgeSyncing.string, queuedCount)
        }
        return String(format: Strings.Sync.badgeQueued.string, queuedCount)
    }
}

#if DEBUG
#Preview("Idle") {
    let store = ObservationStore()
    let auth = CloudAuthService()
    let peers = PairedPeersStore()
    return SyncStatusBadge()
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

#Preview("Queued") {
    let store = ObservationStore()
    store.addObservation("amecro")
    store.addObservation("norcar")
    let auth = CloudAuthService()
    let peers = PairedPeersStore()
    return SyncStatusBadge()
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
