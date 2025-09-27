import Foundation
import Testing
@testable import BirdCountCore

struct TaxonomyStoreTests {
    @Test
    func searchOrdersByCommonnessAscending() throws {
        let taxa = [
            Taxon(id: "c0", commonName: "Rare", scientificName: "Rarus", order: 2, rank: "species", commonness: 0),
            Taxon(id: "c3", commonName: "Common", scientificName: "Communis", order: 3, rank: "species", commonness: 3),
            Taxon(id: "c1", commonName: "Scarce", scientificName: "Scarsus", order: 1, rank: "species", commonness: 1),
            Taxon(id: "unk", commonName: "Unknown", scientificName: "Incertus", order: 0, rank: "species", commonness: nil)
        ]
        let taxStore = TaxonomyStore(); taxStore.loadPreview(species: taxa)
        let obsStore = ObservationStore(testing: true); obsStore.clearAll()
        let now = Date()
        // Make them older than 24h to avoid recent bucket
        obsStore.addObservation("c1", begin: now.addingTimeInterval(-26*60*60), end: now.addingTimeInterval(-26*60*60), count: 1)
        obsStore.addObservation("c0", begin: now.addingTimeInterval(-25*60*60), end: now.addingTimeInterval(-25*60*60), count: 1)
        ObservationStoreProxy.shared.register(obsStore)
        let ids = taxStore.search("").map { $0.id }
        #expect(ids == ["c0", "c1", "c3", "unk"]) // rare → scarce → common → unknown
    }

    @Test
    func searchPutsRecentSpeciesAtBottom() throws {
        let now = Date()
        let taxa = [
            Taxon(id: "rareOld", commonName: "Rare Old", scientificName: "Rarus antiquus", order: 1, rank: "species", commonness: 0),
            Taxon(id: "scarceOld", commonName: "Scarce Old", scientificName: "Scarsus antiquus", order: 2, rank: "species", commonness: 1),
            Taxon(id: "commonRecentOlder", commonName: "Common Recent Older", scientificName: "Communis recenta", order: 3, rank: "species", commonness: 3),
            Taxon(id: "commonRecentNewest", commonName: "Common Recent Newest", scientificName: "Communis recentissimus", order: 4, rank: "species", commonness: 3)
        ]
        let taxStore = TaxonomyStore(); taxStore.loadPreview(species: taxa)
        let obsStore = ObservationStore(testing: true); obsStore.clearAll()
        // Two recent within 24h
        obsStore.addObservation("commonRecentOlder", begin: now.addingTimeInterval(-60*60), end: now.addingTimeInterval(-60*60), count: 1)
        obsStore.addObservation("commonRecentNewest", begin: now.addingTimeInterval(-10*60), end: now.addingTimeInterval(-10*60), count: 1)
        // Older observations outside 24h for others
        obsStore.addObservation("rareOld", begin: now.addingTimeInterval(-3*24*60*60), end: now.addingTimeInterval(-3*24*60*60), count: 1)
        obsStore.addObservation("scarceOld", begin: now.addingTimeInterval(-2*24*60*60), end: now.addingTimeInterval(-2*24*60*60), count: 1)
        ObservationStoreProxy.shared.register(obsStore)
        let ids = taxStore.search("").map { $0.id }
        #expect(ids == ["rareOld", "scarceOld", "commonRecentOlder", "commonRecentNewest"])
    }
}
