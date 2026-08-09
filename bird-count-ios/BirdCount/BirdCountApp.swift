import SwiftUI

@main
struct BirdCountApp: App {
    @State private var taxonomyStore = TaxonomyStore()
    @State private var observationStore: ObservationStore
    @State private var settingsStore: SettingsStore
    @State private var dateRangeStore = DateRangeStore()
    @State private var locationManager = LocationManager.shared
    @State private var cloudAuth = CloudAuthService()
    @State private var cloudSync: CloudSyncService
    @State private var pairedPeers: PairedPeersStore
    @State private var peerAutoSync: PeerAutoSyncService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth = CloudAuthService()
        _cloudAuth = State(initialValue: auth)
        _cloudSync = State(initialValue: CloudSyncService(auth: auth))

        let observations = ObservationStore()
        let settings = SettingsStore()
        let paired = PairedPeersStore()
        _observationStore = State(initialValue: observations)
        _settingsStore = State(initialValue: settings)
        _pairedPeers = State(initialValue: paired)
        _peerAutoSync = State(initialValue: PeerAutoSyncService(
            observationStore: observations,
            settingsStore: settings,
            pairedPeers: paired
        ))

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
                .environment(pairedPeers)
                .environment(peerAutoSync)
                .onAppear {
                    // Set up store dependencies
                    observationStore.setSettingsStore(settingsStore)
                    cloudSync.activateAutoSync(store: observationStore)
                    pairedPeers.activate(store: observationStore)
                    peerAutoSync.setScenePhaseActive(scenePhase != .background)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { cloudSync.requestSync() }
                    // Persists are coalesced/async; make sure any pending one
                    // lands before the app can be suspended.
                    if phase == .background { observationStore.flushPendingPersist() }
                    // != .background: brief .inactive (Control Center, Face
                    // ID) must not drop paired-sync connections.
                    peerAutoSync.setScenePhaseActive(phase != .background)
                }
        }
    }
}
private struct TopTabsRoot: View {
    @State private var selection: AppTab = .home
    @State private var showSettings: Bool = false
    @State private var showLeftDrawer: Bool = false
    @State private var homeNavState = AppNavigationState()
    @State private var summaryNavState = AppNavigationState()
    @State private var logNavState = AppNavigationState()

    private var activeNavState: AppNavigationState {
        switch selection {
        case .home:    return homeNavState
        case .summary: return summaryNavState
        case .log:     return logNavState
        }
    }

    var body: some View {
        ZStack {
            Group {
                switch selection {
                case .home:    HomeView().environment(homeNavState)
                case .summary: SummaryView().environment(summaryNavState)
                case .log:     LogView().environment(logNavState)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Spacer preserving the height the tab bar previously occupied.
                Color.clear.frame(height: 49)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    AppHeaderView(showSettings: $showSettings, showLeftDrawer: $showLeftDrawer)
                        .environment(activeNavState)
                    Divider()
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(show: $showSettings) }

            LeftDrawerView(
                isPresented: $showLeftDrawer,
                selectedTab: $selection,
                showSettings: $showSettings
            )
        }
    }
}
