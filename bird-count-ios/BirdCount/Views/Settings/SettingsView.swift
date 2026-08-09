import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ObservationStore.self) private var observations
    @Binding var show: Bool
    @State private var confirmClear: Bool = false

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
    let store = ObservationStore()
    let settings = SettingsStore()
    SettingsView(show: .constant(true))
        .environment(settings)
        .environment(store)
        .environment(TaxonomyStore())
}
#endif
