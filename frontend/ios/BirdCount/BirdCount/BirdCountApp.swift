import SwiftUI

@main
struct BirdCountApp: App {
    @State private var taxonomyStore = TaxonomyStore()
    @State private var observationStore = ObservationStore()
    @State private var settingsStore = SettingsStore() // Added settings store

    var body: some Scene {
        WindowGroup {
            TopTabsRoot()
            .environment(taxonomyStore)
            .environment(observationStore)
            .environment(settingsStore) // inject settings
        }
    }
}

private struct TopTabsRoot: View {
    private enum Tab: String, CaseIterable, Identifiable { case home = "Home", summary = "Summary", log = "Log"; var id: String { rawValue } }
    @State private var selection: Tab = .home
    @State private var showSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Top tab selector with Settings button on the right
            ZStack {
                Picker("", selection: $selection) {
                    ForEach(Tab.allCases) { tab in Text(tab.rawValue).tag(tab) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                HStack { Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.headline)
                            .padding(8)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .accessibilityLabel("Settings")
                    .padding(.trailing, 8)
                }
                .allowsHitTesting(true)
            }
            .padding(.top, 8)

            Divider()

            // Content
            Group {
                switch selection {
                case .home: HomeView()
                case .summary: SummaryView()
                case .log: ObservationLogView()
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(show: $showSettings) }
    }
}
