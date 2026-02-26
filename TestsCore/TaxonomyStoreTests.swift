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
        // Make them older than the current date range to avoid recent bucket
        obsStore.addObservation("c1", begin: now.addingTimeInterval(-26*60*60), end: now.addingTimeInterval(-26*60*60), count: 1)
        obsStore.addObservation("c0", begin: now.addingTimeInterval(-25*60*60), end: now.addingTimeInterval(-25*60*60), count: 1)
        ObservationStoreProxy.shared.register(obsStore)
        
        // Set up a date range that excludes the old observations (only covers last hour)
        let rangeStart = now.addingTimeInterval(-60*60) // 1 hour ago
        let dateRange = DateRange(begin: rangeStart, end: now)
        let ids = taxStore.search("", dateRange: dateRange).map { $0.id }
        #expect(ids == ["c0", "c1", "c3", "unk"]) // rare → scarce → common → unknown
    }

    // MARK: - Proximate bucket (bucket C)

    @Test
    func searchPutsProximateSpeciesBetweenBuckets() throws {
        // Verifies bucket order: B (non-recent, non-proximate) → C (proximate) → A (in-range)
        // "proximate" is rare (commonness 0) — in bucket B alone it would sort above "nonRecent"
        // (commonness 3), but bucket C membership overrides commonness ordering.
        let now = Date()
        let taxa = [
            Taxon(id: "nonRecent", commonName: "Non Recent", scientificName: "Vetus absentus", order: 1, rank: "species", commonness: 3),
            Taxon(id: "proximate", commonName: "Proximate", scientificName: "Proximus localis", order: 2, rank: "species", commonness: 0),
            Taxon(id: "recent", commonName: "Recent", scientificName: "Recens activus", order: 3, rank: "species", commonness: 0)
        ]
        let taxStore = TaxonomyStore(); taxStore.loadPreview(species: taxa)
        let obsStore = ObservationStore(testing: true); obsStore.clearAll()

        // "recent" falls within the 2-hour active date range
        obsStore.addObservation("recent", begin: now.addingTimeInterval(-30 * 60), end: now.addingTimeInterval(-30 * 60), count: 1)

        // "proximate" is 3 days ago (outside 2h range, inside 14-day window) with a location
        let loc = ObservationLocation(latitude: 37.7749, longitude: -122.4194)
        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 3600)
        obsStore.addObservation("proximate", begin: threeDaysAgo, end: threeDaysAgo, count: 1, location: loc)

        // "nonRecent" is 20 days ago — outside the 14-day proximate window entirely
        let twentyDaysAgo = now.addingTimeInterval(-20 * 24 * 3600)
        obsStore.addObservation("nonRecent", begin: twentyDaysAgo, end: twentyDaysAgo, count: 1)

        ObservationStoreProxy.shared.register(obsStore)
        let dateRange = DateRange(begin: now.addingTimeInterval(-2 * 3600), end: now)
        let ids = taxStore.search("", dateRange: dateRange).map { $0.id }
        #expect(ids == ["nonRecent", "proximate", "recent"])
    }

    @Test
    func searchNoLocationRecordIsNotProximate() throws {
        // A record within the 14-day window but with no location must NOT enter bucket C.
        let now = Date()
        let taxa = [
            Taxon(id: "noLoc", commonName: "No Location", scientificName: "Absens locus", order: 1, rank: "species", commonness: 3),
            Taxon(id: "hasLoc", commonName: "Has Location", scientificName: "Praesens locus", order: 2, rank: "species", commonness: 0)
        ]
        let taxStore = TaxonomyStore(); taxStore.loadPreview(species: taxa)
        let obsStore = ObservationStore(testing: true); obsStore.clearAll()

        let threeDaysAgo = now.addingTimeInterval(-3 * 24 * 3600)
        let loc = ObservationLocation(latitude: 37.7749, longitude: -122.4194)
        // noLoc: within window, no location → should stay in bucket B
        obsStore.addObservation("noLoc", begin: threeDaysAgo, end: threeDaysAgo, count: 1)
        // hasLoc: within window, with location → should enter bucket C
        obsStore.addObservation("hasLoc", begin: threeDaysAgo.addingTimeInterval(-3600), end: threeDaysAgo.addingTimeInterval(-3600), count: 1, location: loc)

        ObservationStoreProxy.shared.register(obsStore)
        let dateRange = DateRange(begin: now.addingTimeInterval(-3600), end: now)
        let ids = taxStore.search("", dateRange: dateRange).map { $0.id }
        // noLoc stays in bucket B (commonness 3 → bottom of B), hasLoc in bucket C
        #expect(ids == ["noLoc", "hasLoc"])
    }

    @Test
    func searchSortsProximateByFrequencyThenDate() throws {
        // Within bucket C, sort is: lower frequency first, then older date first.
        // freq1 (1 entry), freq2 (2 entries), freq3 (3 entries) → ascending frequency at bottom.
        let now = Date()
        let taxa = [
            Taxon(id: "freq1", commonName: "Freq 1", scientificName: "Unicus semel", order: 1, rank: "species", commonness: 3),
            Taxon(id: "freq3", commonName: "Freq 3", scientificName: "Tertius ter", order: 2, rank: "species", commonness: 3),
            Taxon(id: "freq2", commonName: "Freq 2", scientificName: "Secundus bis", order: 3, rank: "species", commonness: 3)
        ]
        let taxStore = TaxonomyStore(); taxStore.loadPreview(species: taxa)
        let obsStore = ObservationStore(testing: true); obsStore.clearAll()

        let loc = ObservationLocation(latitude: 37.7749, longitude: -122.4194)
        let base = now.addingTimeInterval(-5 * 24 * 3600) // 5 days ago, inside 14-day window

        obsStore.addObservation("freq1", begin: base, end: base, count: 1, location: loc)
        obsStore.addObservation("freq2", begin: base, end: base, count: 1, location: loc)
        obsStore.addObservation("freq2", begin: base.addingTimeInterval(3600), end: base.addingTimeInterval(3600), count: 1, location: loc)
        obsStore.addObservation("freq3", begin: base, end: base, count: 1, location: loc)
        obsStore.addObservation("freq3", begin: base.addingTimeInterval(3600), end: base.addingTimeInterval(3600), count: 1, location: loc)
        obsStore.addObservation("freq3", begin: base.addingTimeInterval(7200), end: base.addingTimeInterval(7200), count: 1, location: loc)

        ObservationStoreProxy.shared.register(obsStore)
        // Active range covers only the last hour — all observations fall outside it (bucket C candidates)
        let dateRange = DateRange(begin: now.addingTimeInterval(-3600), end: now)
        let ids = taxStore.search("", dateRange: dateRange).map { $0.id }
        #expect(ids == ["freq1", "freq2", "freq3"])
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
        // Two recent within the current date range
        obsStore.addObservation("commonRecentOlder", begin: now.addingTimeInterval(-60*60), end: now.addingTimeInterval(-60*60), count: 1)
        obsStore.addObservation("commonRecentNewest", begin: now.addingTimeInterval(-10*60), end: now.addingTimeInterval(-10*60), count: 1)
        // Older observations outside the current date range
        obsStore.addObservation("rareOld", begin: now.addingTimeInterval(-3*24*60*60), end: now.addingTimeInterval(-3*24*60*60), count: 1)
        obsStore.addObservation("scarceOld", begin: now.addingTimeInterval(-2*24*60*60), end: now.addingTimeInterval(-2*24*60*60), count: 1)
        ObservationStoreProxy.shared.register(obsStore)
        
        // Set up a date range that includes observations from the last 2 hours
        let rangeStart = now.addingTimeInterval(-2*60*60) // 2 hours ago
        let dateRange = DateRange(begin: rangeStart, end: now)
        let ids = taxStore.search("", dateRange: dateRange).map { $0.id }
        #expect(ids == ["rareOld", "scarceOld", "commonRecentOlder", "commonRecentNewest"])
    }
}
