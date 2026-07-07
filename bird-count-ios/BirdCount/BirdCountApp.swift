import SwiftUI
import UIKit

@main
struct BirdCountApp: App {
    @State private var taxonomyStore = TaxonomyStore()
    @State private var observationStore = ObservationStore()
    @State private var settingsStore = SettingsStore()
    @State private var dateRangeStore = DateRangeStore()
    @State private var locationManager = LocationManager.shared
    @State private var cloudAuth = CloudAuthService()
    @State private var cloudSync: CloudSyncService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth = CloudAuthService()
        _cloudAuth = State(initialValue: auth)
        _cloudSync = State(initialValue: CloudSyncService(auth: auth))

        // Enlarge segmented control text globally
        let seg = UISegmentedControl.appearance()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        seg.setTitleTextAttributes(attrs, for: .normal)
        seg.setTitleTextAttributes(attrs, for: .selected)
    }

    var body: some Scene {
        WindowGroup {
            TopTabsRoot()
                .environment(taxonomyStore)
                .environment(observationStore)
                .environment(settingsStore)
                .environment(dateRangeStore)
                .environment(locationManager)
                .environment(cloudAuth)
                .environment(cloudSync)
                .onAppear {
                    // Set up store dependencies
                    observationStore.setSettingsStore(settingsStore)
                    cloudSync.activateAutoSync(store: observationStore)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { cloudSync.requestSync() }
                }
        }
    }
}
private struct TopTabsRoot: View {
    private enum Tab: String, CaseIterable, Identifiable { case home = "Home", summary = "Summary", log = "Log"; var id: String { rawValue } }
    @State private var selection: Tab = .home
    @State private var showSettings: Bool = false
    @State private var showLeftDrawer: Bool = false
    @Environment(DateRangeStore.self) private var dateRangeStore

    var body: some View {
        ZStack {
            // Content under top tabs: bottom TabView for Home/Summary/Log
            TabView(selection: $selection) {
                HomeView()
                    .tabItem { Label(Strings.Tab.home.string, systemImage: "house") }
                    .tag(Tab.home)

                SummaryView()
                    .tabItem { Label(Strings.Tab.summary.string, systemImage: "chart.bar") }
                    .tag(Tab.summary)

                ObservationLogView()
                    .tabItem { Label(Strings.Tab.log.string, systemImage: "list.bullet") }
                    .tag(Tab.log)
            }
            .safeAreaInset(edge: .top, spacing: 8) {
                VStack(spacing: 0) {
                    AppHeaderView(showSettings: $showSettings, showLeftDrawer: $showLeftDrawer)
                    Divider()
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(show: $showSettings) }
            
            // Left drawer overlay at the top level
            LeftDrawerView(
                isPresented: $showLeftDrawer,
                showSettings: $showSettings,
                showShareOptions: .constant(false)
            )
        }
    }
}
