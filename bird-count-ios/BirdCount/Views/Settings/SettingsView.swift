import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(CloudAuthService.self) private var cloudAuth
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(PairedPeersStore.self) private var pairedPeers
    @Environment(PeerAutoSyncService.self) private var autoSync
    @Binding var show: Bool
    @State private var confirmClear: Bool = false
    @State private var showPairSheet = false
    @State private var showResyncConfirmation = false

    private let availableChecklists: [String] = ["checklist-US-CA-041", "checklist-US-ME"]

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        if version != "-" && build != "-" {
            return "\(version) (\(build))"
        } else if version != "-" {
            return version
        } else {
            return "-"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Checklist") {
                    Picker("Region checklist", selection: binding(\.selectedChecklistId)) {
                        Text("None (global)").tag(String?.none)
                        ForEach(availableChecklists, id: \.self) { id in
                            Text(labelForChecklist(id)).tag(String?.some(id))
                        }
                    }
                    if settings.selectedChecklistId != nil {
                        CommonnessRangeView(
                            minCommonness: binding(\.minCommonness),
                            maxCommonness: binding(\.maxCommonness)
                        )
                    }
                }

                Section("Cloud Sync") {
                    if cloudAuth.isSignedIn {
                        Button {
                            Task { await cloudSync.syncNow(store: observations) }
                        } label: {
                            HStack {
                                Text("Sync now")
                                Spacer()
                                if cloudSync.isSyncing { ProgressView() }
                            }
                        }
                        .disabled(cloudSync.isSyncing)
                        if case .syncing(let message) = cloudSync.state {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                        }
                        if case .failure(let message) = cloudSync.state {
                            Text(message).font(.footnote).foregroundStyle(.red)
                        }
                        if let last = cloudSync.lastSyncDate {
                            HStack {
                                Text("Last sync")
                                Spacer()
                                Text(last.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Toggle("Auto sync on Wi-Fi", isOn: Binding(
                            get: { cloudSync.autoSyncEnabled },
                            set: { cloudSync.autoSyncEnabled = $0 }
                        ))
                        HStack {
                            Text(Strings.User.queuedForUpload.string)
                            Spacer()
                            Image(systemName: cloudSync.isOnWifi ? "wifi" : "wifi.slash")
                                .font(.subheadline)
                                .foregroundStyle(cloudSync.isOnWifi ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                                .accessibilityLabel(
                                    cloudSync.isOnWifi
                                        ? Strings.User.connectionAvailable.string
                                        : Strings.User.connectionUnavailable.string
                                )
                            Text("\(observations.dirtyIds.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Button("Re-sync all data") {
                            showResyncConfirmation = true
                        }
                        .disabled(cloudSync.isSyncing)
                        .confirmationDialog(
                            "Re-sync all data?",
                            isPresented: $showResyncConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Re-sync all") {
                                Task { await cloudSync.resyncAll(store: observations) }
                            }
                            Button(Strings.General.cancel.string, role: .cancel) {}
                        } message: {
                            Text("Re-uploads every observation on this device and re-downloads everything from the cloud. Nothing is deleted; use this if devices are out of sync.")
                        }
                    } else {
                        Text("Sign in via Account to enable cloud sync.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                }

                Section {
                    ForEach(pairedPeers.peers) { peer in
                        let present = autoSync.presentPeerIDs.contains(peer.id)
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.displayName)
                                HStack(spacing: 4) {
                                    Image(systemName: present
                                        ? "antenna.radiowaves.left.and.right"
                                        : "antenna.radiowaves.left.and.right.slash")
                                        .font(.caption2)
                                        .foregroundStyle(present ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                                        .accessibilityLabel(
                                            present
                                                ? Strings.User.connectionAvailable.string
                                                : Strings.User.connectionUnavailable.string
                                        )
                                    Text(String(format: Strings.User.peerQueued.string, peer.pendingIds.count))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(Strings.Sync.unpair.string, role: .destructive) {
                                pairedPeers.unpair(peer.id)
                            }
                        }
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

                Section("Data") {
                    Button(role: .destructive) { confirmClear = true } label: { Text("Clear all counts") }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { show = false } } }
            .alert("Clear all counts?", isPresented: $confirmClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    observations.clearAll()
                }
            } message: {
                Text("This will reset every species' count to zero. This cannot be undone.")
            }
            .sheet(isPresented: $showPairSheet) {
                PairDeviceSheet()
            }
        }
    }

    private func labelForChecklist(_ id: String) -> String {
        if id.contains("US-CA-041") { return "US-CA (Region 041)" }
        if id.contains("US-ME") { return "US-ME" }
        return id
    }
}

#if DEBUG
#Preview {
    let auth = CloudAuthService()
    let store = ObservationStore()
    let settings = SettingsStore()
    let peers = PairedPeersStore()
    return SettingsView(show: .constant(true))
        .environment(settings)
        .environment(store)
        .environment(TaxonomyStore())
        .environment(auth)
        .environment(CloudSyncService(auth: auth))
        .environment(peers)
        .environment(PeerAutoSyncService(
            observationStore: store,
            settingsStore: settings,
            pairedPeers: peers
        ))
}
#endif
