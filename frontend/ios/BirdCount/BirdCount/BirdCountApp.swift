import SwiftUI

@main
struct BirdCountApp: App {
    @State private var taxonomyStore = TaxonomyStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(taxonomyStore)
        }
    }
}
