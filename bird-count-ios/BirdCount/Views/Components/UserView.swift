import SwiftUI

/// User view containing user settings, account information, and cloud sync.
struct UserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ObservationStore.self) private var observations
    @Environment(CloudAuthService.self) private var cloudAuth
    @Environment(CloudSyncService.self) private var cloudSync
    @Environment(PairedPeersStore.self) private var pairedPeers
    @Environment(PeerAutoSyncService.self) private var autoSync
    @State private var emailText: String = ""
    @State private var signInError: String?
    @State private var showPairSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.tint)

                        Text("User Settings")
                            .font(.title2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section(Strings.User.email.string) {
                    TextField(Strings.User.emailPlaceholder.string, text: $emailText)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            settingsStore.loginEmail = emailText
                        }
                        .onChange(of: emailText) { _, newValue in
                            settingsStore.loginEmail = newValue
                        }
                }

                Section("Cloud Sync") {
                    if cloudAuth.isSignedIn {
                        HStack {
                            Text("Account")
                            Spacer()
                            Text(cloudAuth.accountEmail ?? "Signed in")
                                .foregroundStyle(.secondary)
                        }
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
            }
            .sheet(isPresented: $showPairSheet) {
                PairDeviceSheet()
            }
            .onAppear {
                emailText = settingsStore.loginEmail
            }
            .navigationTitle("User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.General.close.string) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let auth = CloudAuthService()
    let store = ObservationStore()
    let settings = SettingsStore()
    let peers = PairedPeersStore()
    return UserView()
        .environment(settings)
        .environment(store)
        .environment(auth)
        .environment(CloudSyncService(auth: auth))
        .environment(peers)
        .environment(PeerAutoSyncService(
            observationStore: store,
            settingsStore: settings,
            pairedPeers: peers
        ))
}
