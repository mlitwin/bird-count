import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Environment(CloudAuthService.self) private var cloudAuth
    @Environment(CloudSyncService.self) private var cloudSync
    @Binding var show: Bool
    @State private var confirmClear: Bool = false
    @State private var signInError: String?

    // Example list of bundled checklist ids; keep in sync with added resource files
    private let availableChecklists: [String] = ["checklist-US-CA-041", "checklist-US-ME"]

    // Helper to build bindings into settings values
    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
    
    // Version string with build number
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
                        if let last = cloudSync.lastSyncDate {
                            HStack {
                                Text("Last sync")
                                Spacer()
                                Text(last.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                Section("Data") {
                    Button(role: .destructive) { confirmClear = true } label: { Text("Clear all counts") }
                }
                Section("About") {
                    HStack { 
                        Text("Version"); 
                        Spacer(); 
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
        }
    }

    private func labelForChecklist(_ id: String) -> String {
        if id.contains("US-CA-041") { return "US-CA (Region 041)" }
        if id.contains("US-ME") { return "US-ME" }
        return id
    }
}

// moved to CommonnessRangeView.swift

#if DEBUG
#Preview {
    let auth = CloudAuthService()
    return SettingsView(show: .constant(true))
        .environment(SettingsStore())
        .environment(ObservationStore())
        .environment(TaxonomyStore())
        .environment(auth)
        .environment(CloudSyncService(auth: auth))
}
#endif
