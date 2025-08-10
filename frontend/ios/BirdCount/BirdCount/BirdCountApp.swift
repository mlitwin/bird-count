import SwiftUI

@main
struct BirdCountApp: App {
    @State private var taxonomyStore = TaxonomyStore()
    @State private var observationStore = ObservationStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(taxonomyStore)
                .environment(observationStore)
        }
    }
}
