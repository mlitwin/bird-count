import Foundation
import Testing
@testable import BirdCountCore

/// The "from a synced user" indicator: observer-mismatch detection on records
/// and the per-taxon aggregation used by the species list.
struct SyncedObserverIndicatorTests {

    private let day = Date(timeIntervalSince1970: 1_782_900_000)
    private var range: DateRange {
        DateRange(begin: day.addingTimeInterval(-3600), end: day.addingTimeInterval(3600))
    }

    private func dto(
        _ id: UUID = UUID(),
        parentId: UUID? = nil,
        taxonId: String = "amecro",
        observer: String
    ) -> ObservationRecordDTO {
        ObservationRecordDTO(
            id: id, parentId: parentId, taxonId: taxonId,
            begin: day, end: day, count: 1, observer: observer
        )
    }

    @Test
    func recordDetectsForeignObserverIncludingChildren() {
        let store = ObservationStore(testing: true)
        let mine = dto(observer: "me@example.com")
        let foreignChild = dto(parentId: mine.id, observer: "friend@example.com")
        store.mergeDTOs([mine, foreignChild], markDirty: false)

        let record = store.findRecord(by: mine.id)!
        #expect(record.hasObserver(otherThan: "me@example.com"))
        // From the friend's perspective the parent record itself differs.
        #expect(record.hasObserver(otherThan: "friend@example.com"))
    }

    @Test
    func localOnlyRecordIsNotFlagged() {
        let store = ObservationStore(testing: true)
        let mine = dto(observer: "me@example.com")
        store.mergeDTOs([mine], markDirty: false)
        #expect(!store.findRecord(by: mine.id)!.hasObserver(otherThan: "me@example.com"))
    }

    @Test
    func taxaAggregationFlagsOnlyForeignTaxaInRange() {
        let store = ObservationStore(testing: true)
        let mine = dto(taxonId: "amecro", observer: "me@example.com")
        let theirs = dto(taxonId: "norcar", observer: "friend@example.com")
        // Foreign, but outside the range: must not be flagged.
        var outOfRange = dto(taxonId: "houspa", observer: "friend@example.com")
        outOfRange = ObservationRecordDTO(
            id: outOfRange.id, taxonId: "houspa",
            begin: day.addingTimeInterval(-86_400), end: day.addingTimeInterval(-86_400),
            count: 1, observer: "friend@example.com"
        )
        store.mergeDTOs([mine, theirs, outOfRange], markDirty: false)

        let flagged = ObservationStoreCache.taxaWithOtherObservers(
            than: "me@example.com", in: range, from: store.observations
        )
        #expect(flagged == ["norcar"])
    }

    @Test
    func foreignAdjustmentChildFlagsItsOwnTaxon() {
        let store = ObservationStore(testing: true)
        let mine = dto(taxonId: "amecro", observer: "me@example.com")
        let foreignChild = dto(parentId: mine.id, taxonId: "amecro", observer: "friend@example.com")
        store.mergeDTOs([mine, foreignChild], markDirty: false)

        let flagged = ObservationStoreCache.taxaWithOtherObservers(
            than: "me@example.com", in: range, from: store.observations
        )
        #expect(flagged == ["amecro"])
    }
}
