import SwiftUI

struct HomeView: View {
    @Environment(TaxonomyStore.self) private var taxonomy

    var body: some View {
        NavigationStack {
            Group {
                if let error = taxonomy.error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if !taxonomy.loaded {
                    ProgressView("Loading taxonomy…")
                        .task { taxonomy.load() }
                } else if taxonomy.species.isEmpty {
                    ContentUnavailableView("No Species", systemImage: "bird", description: Text("Taxonomy file empty"))
                } else {
                    List(taxonomy.species) { taxon in
                        VStack(alignment: .leading) {
                            Text(taxon.commonName)
                                .font(.headline)
                            Text(taxon.scientificName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Bird Count")
        }
    }
}

#if DEBUG
private extension TaxonomyStore {
    static var previewInstance: TaxonomyStore {
        let store = TaxonomyStore()
        store.loadPreview(species: [
            Taxon(id: "amecro", commonName: "American Crow", scientificName: "Corvus brachyrhynchos", order: 1, rank: "species")
        ])
        return store
    }
}
#endif

#Preview("Home") {
    HomeView()
        .environment(TaxonomyStore.previewInstance)
}
