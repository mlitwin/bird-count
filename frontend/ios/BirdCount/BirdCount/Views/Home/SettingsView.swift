import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ObservationStore.self) private var observations
    @Environment(TaxonomyStore.self) private var taxonomy
    @Binding var show: Bool
    @State private var confirmClear: Bool = false

    // Example list of bundled checklist ids; keep in sync with added resource files
    private let availableChecklists: [String] = ["checklist-US-CA-041", "checklist-US-ME"]

    // Helper to build bindings into settings values
    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Search") {
                    Toggle("Enable abbreviation search", isOn: binding(\.enableAbbreviationSearch))
                }
                Section("Checklist") {
                    Picker("Region checklist", selection: binding(\.selectedChecklistId)) {
                        Text("None (global)").tag(String?.none)
                        ForEach(availableChecklists, id: \.self) { id in
                            Text(labelForChecklist(id)).tag(String?.some(id))
                        }
                    }
                    if settings.selectedChecklistId != nil {
                        VStack(alignment: .leading) {
                            Text("Show species with commonness between:")
                            HStack {
                                Stepper(value: binding(\.minCommonness), in: 0...3) { Text("Min: \(settings.minCommonness)") }
                                Stepper(value: binding(\.maxCommonness), in: 0...3) { Text("Max: \(settings.maxCommonness)") }
                            }
                            CommonnessLegend()
                        }
                    }
                }
                Section("Feedback") {
                    Toggle("Haptics", isOn: binding(\.enableHaptics))
                }
                Section("Appearance") {
                    Picker("Theme", selection: binding(\.darkModeOverride)) {
                        ForEach(SettingsStore.DarkModeOverride.allCases) { m in
                            Text(label(for: m)).tag(m)
                        }
                    }
                }
                Section("Data") {
                    Button(role: .destructive) { confirmClear = true } label: { Text("Clear all counts") }
                }
                Section("About") {
                    HStack { Text("Version"); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-") }
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

    private func label(for mode: SettingsStore.DarkModeOverride) -> String {
        switch mode { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }

    private func labelForChecklist(_ id: String) -> String {
        if id.contains("US-CA-041") { return "US-CA (Region 041)" }
        if id.contains("US-ME") { return "US-ME" }
        return id
    }
}

private struct CommonnessLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            legendItem(code: "R", label: "Rare")
            legendItem(code: "S", label: "Scarce")
            legendItem(code: "U", label: "Uncommon")
            legendItem(code: "C", label: "Common")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    private func legendItem(code: String, label: String) -> some View { HStack(spacing: 2) { Text(code).bold(); Text(label) } }
}

#if DEBUG
#Preview { SettingsView(show: .constant(true)).environment(SettingsStore()).environment(ObservationStore()).environment(TaxonomyStore()) }
#endif
