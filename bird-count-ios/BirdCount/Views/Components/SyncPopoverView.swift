import SwiftUI

/// Full-screen sync sheet — mirrors the Settings sheet style.
/// Consolidates all sync controls: cloud status, auto-sync, per-peer
/// status/queue/actions, pairing, and global Re-sync All.
struct SyncStatusSheet: View {
    @Environment(ObservationStore.self) private var observations
    @Environment(PairedPeersStore.self) private var pairedPeers
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(CloudAuthService.self) private var cloudAuth
    @Environment(PeerAutoSyncService.self) private var autoSync
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var showPairSheet = false
    @State private var emailText: String = ""
    @State private var signInError: String?

    private var hasSyncTargets: Bool {
        cloudAuth.isSignedIn || !pairedPeers.peers.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                cloudSection
                pairedDevicesSection
            }
            .onAppear { emailText = settings.loginEmail }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.General.close.string) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Re-sync All") {
                        Task { await cloudSync.resyncAll(store: observations) }
                        for peer in pairedPeers.peers {
                            pairedPeers.resetPending(for: peer.id, store: observations)
                            if autoSync.presentPeerIDs.contains(peer.id) {
                                autoSync.syncNow(peerID: peer.id)
                            }
                        }
                    }
                    .foregroundStyle(hasSyncTargets ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    .disabled(!hasSyncTargets)
                }
            }
        }
        .sheet(isPresented: $showPairSheet) {
            PairDeviceSheet()
        }
    }

    // MARK: - Cloud section

    @ViewBuilder
    private var cloudSection: some View {
        Section {
            // Email address used as observer identifier
            TextField(Strings.User.emailPlaceholder.string, text: $emailText)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onChange(of: emailText) { _, newValue in
                    settings.loginEmail = newValue
                }

            if cloudAuth.isSignedIn {
                // Apple ID display
                HStack {
                    Text("Apple ID")
                    Spacer()
                    Text(cloudAuth.accountEmail ?? "Signed in")
                        .foregroundStyle(.secondary)
                }

                // Connection status
                HStack(spacing: 8) {
                    Circle()
                        .fill(cloudStatusColor)
                        .frame(width: 8, height: 8)
                    Text(cloudStatusLabel)
                        .foregroundStyle(.secondary)
                }

                // In-progress or error message
                if case .syncing(let msg) = cloudSync.state {
                    Text(msg).font(.footnote).foregroundStyle(.secondary)
                }
                if case .failure(let msg) = cloudSync.state {
                    Text(msg).font(.footnote).foregroundStyle(.orange)
                }

                // Queue count
                HStack {
                    Text("Queued for upload")
                    Spacer()
                    Text("\(observations.dirtyIds.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // Last sync
                HStack {
                    Text("Last sync")
                    Spacer()
                    Text(cloudSync.lastSyncDate.map(relativeDate) ?? "Never")
                        .foregroundStyle(.secondary)
                }

                // Auto-sync toggle
                Toggle("Auto sync on Wi-Fi", isOn: Binding(
                    get: { cloudSync.autoSyncEnabled },
                    set: { cloudSync.autoSyncEnabled = $0 }
                ))

                // Sync Now
                if cloudSync.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Syncing…").foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sync Now") {
                        Task { await cloudSync.syncNow(store: observations) }
                    }
                }

                // Re-sync All
                Button("Re-sync All") {
                    Task { await cloudSync.resyncAll(store: observations) }
                }
                .foregroundStyle(.orange)

                Button("Sign out", role: .destructive) { cloudAuth.signOut() }
            } else {
                Button("Sign in with Apple") {
                    signInError = nil
                    Task {
                        do { try await cloudAuth.signIn() }
                        catch { signInError = error.localizedDescription }
                    }
                }
                if let signInError {
                    Text(signInError).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("iCloud")
        }
    }

    // MARK: - Paired devices section

    @ViewBuilder
    private var pairedDevicesSection: some View {
        Section {
            ForEach(pairedPeers.peers) { peer in
                PeerRows(peer: peer)
            }
            Button {
                showPairSheet = true
            } label: {
                Label(Strings.Sync.pairNewDevice.string, systemImage: "link.badge.plus")
            }
        } header: {
            Text(Strings.Sync.pairedDevices.string)
        } footer: {
            Text(Strings.Sync.pairExplanation.string)
        }
    }

    // MARK: - Cloud status helpers

    private var cloudStatusColor: Color {
        guard cloudAuth.isSignedIn else { return Color(.secondaryLabel) }
        if case .failure = cloudSync.state { return .orange }
        if cloudSync.isOnWifi && cloudSync.autoSyncEnabled { return .green }
        return .yellow
    }

    private var cloudStatusLabel: String {
        guard cloudAuth.isSignedIn else { return "Not signed in" }
        if case .failure(let msg) = cloudSync.state { return msg }
        if cloudSync.isOnWifi && cloudSync.autoSyncEnabled { return "Wi-Fi · Auto-sync on" }
        if cloudSync.isOnWifi { return "Wi-Fi · Auto-sync off" }
        return "No Wi-Fi"
    }
}

// MARK: - Peer rows

private struct PeerRows: View {
    let peer: PairedPeer

    @Environment(ObservationStore.self) private var observations
    @Environment(PairedPeersStore.self) private var pairedPeers
    @Environment(PeerAutoSyncService.self) private var autoSync

    private var isPresent: Bool { autoSync.presentPeerIDs.contains(peer.id) }

    var body: some View {
        // Name + presence
        HStack {
            Image(systemName: "iphone").foregroundStyle(.tint)
            Text(peer.displayName)
            Spacer()
            Circle()
                .fill(isPresent ? Color.green : Color(.secondaryLabel))
                .frame(width: 8, height: 8)
            Text(isPresent ? "Nearby" : "Away")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Queue count
        HStack {
            Text("Queued")
            Spacer()
            Text("\(peer.pendingIds.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }

        // Last sync
        HStack {
            Text("Last sync")
            Spacer()
            Text(peer.lastSyncDate.map(relativeDate) ?? "Never")
                .foregroundStyle(.secondary)
        }

        // Sync Now (present peers only)
        if isPresent {
            Button("Sync Now") {
                autoSync.syncNow(peerID: peer.id)
            }
        }

        // Re-sync
        Button("Re-sync") {
            pairedPeers.resetPending(for: peer.id, store: observations)
            if isPresent { autoSync.syncNow(peerID: peer.id) }
        }
        .foregroundStyle(.orange)

        // Unpair
        Button(Strings.Sync.unpair.string, role: .destructive) {
            pairedPeers.unpair(peer.id)
        }
    }
}

// MARK: - Utilities

private func relativeDate(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

#if DEBUG
#Preview {
    let store = ObservationStore()
    store.addObservation("amecro")
    store.addObservation("norcar")
    let auth = CloudAuthService()
    let peers = PairedPeersStore()
    let settingsStore = SettingsStore()
    return SyncStatusSheet()
        .environment(store)
        .environment(peers)
        .environment(auth)
        .environment(CloudSyncService(auth: auth))
        .environment(PeerAutoSyncService(
            observationStore: store,
            settingsStore: settingsStore,
            pairedPeers: peers
        ))
        .environment(settingsStore)
}
#endif
