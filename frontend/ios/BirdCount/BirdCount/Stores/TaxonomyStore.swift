import Foundation
import Observation

@Observable final class TaxonomyStore {
    private(set) var species: [Taxon] = []
    private(set) var loaded: Bool = false
    private(set) var error: String? = nil

    func load() {
        guard !loaded else { return }
        do {
            guard let url = Bundle.main.url(forResource: "ios_taxonomy_min", withExtension: "json") else {
                error = "Missing taxonomy resource"
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Taxon].self, from: data)
            species = decoded.sorted { $0.order < $1.order }
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Simple case-insensitive substring search across common + scientific names.
    func search(_ text: String) -> [Taxon] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return species }
        let needle = trimmed.lowercased()
        return species.filter { taxon in
            taxon.commonName.lowercased().contains(needle) || taxon.scientificName.lowercased().contains(needle)
        }
    }
}

#if DEBUG
extension TaxonomyStore {
    func loadPreview(species: [Taxon]) {
        self.species = species
        self.loaded = true
        self.error = nil
    }
}
#endif
