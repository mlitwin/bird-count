import SwiftUI

@main
struct BirdCountApp: App {
    @State private var taxonomyStore = TaxonomyStore()
    @State private var observationStore = ObservationStore()
    @State private var settingsStore = SettingsStore() // Added settings store

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(taxonomyStore)
                .environment(observationStore)
                .environment(settingsStore) // inject settings
        }
    }
}
