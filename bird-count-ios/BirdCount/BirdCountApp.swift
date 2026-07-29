import SwiftUI
import UIKit

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
    @State private var showSettings: Bool = false
    @State private var showLeftDrawer: Bool = false
    @State private var navState = AppNavigationState()

    var body: some View {
        ZStack {
            HomeView()
                .safeAreaInset(edge: .top, spacing: 8) {
                    VStack(spacing: 0) {
                        AppHeaderView(showSettings: $showSettings, showLeftDrawer: $showLeftDrawer)
                        Divider()
                    }
                }
                .sheet(isPresented: $showSettings) { SettingsView(show: $showSettings) }

            LeftDrawerView(
                isPresented: $showLeftDrawer,
                showSettings: $showSettings,
                showShareOptions: .constant(false)
            )
        }
        .environment(navState)
    }
}
