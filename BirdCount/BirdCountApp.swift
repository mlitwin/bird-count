import SwiftUI
import UIKit

@main
struct BirdCountApp: App {
    init() {
        // Enlarge segmented control text globally
        let seg = UISegmentedControl.appearance()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        seg.setTitleTextAttributes(attrs, for: .normal)
        seg.setTitleTextAttributes(attrs, for: .selected)
    }
    @State private var taxonomyStore = TaxonomyStore()
    @State private var observationStore = ObservationStore()
    @State private var settingsStore = SettingsStore()
    @State private var dateRangeStore = DateRangeStore()
    @State private var syncSessionManager = SyncSessionManager()

    var body: some Scene {
        WindowGroup {
            TopTabsRoot()
                .environment(taxonomyStore)
                .environment(observationStore)
                .environment(settingsStore)
                .environment(dateRangeStore)
                .environment(syncSessionManager)
        }
    }
}
private struct TopTabsRoot: View {
    private enum Tab: String, CaseIterable, Identifiable { case home = "Home", summary = "Summary", log = "Log"; var id: String { rawValue } }
    @State private var selection: Tab = .home
    @State private var showSettings: Bool = false
    @Environment(DateRangeStore.self) private var dateRangeStore

    var body: some View {
        // Content under top tabs: bottom TabView for Home/Summary/Log
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

            SummaryView()
                .tabItem { Label("Summary", systemImage: "chart.bar") }
                .tag(Tab.summary)

            ObservationLogView()
                .tabItem { Label("Log", systemImage: "list.bullet") }
                .tag(Tab.log)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                AppHeaderView(showSettings: $showSettings)
                Divider()
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(show: $showSettings) }
    }
}
