import Foundation
import Testing
@testable import BirdCountCore

/// The person badge next to counts: observer collection on records, the
/// per-taxon aggregation, and the attribution → icon mapping.
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

    // MARK: - Attribution → icon mapping

    @Test
    func iconMapping() {
        let me = "me@example.com"
        func attribution(_ observers: Set<String>) -> ObserverAttribution {
            ObserverAttribution(observers: observers, currentObserver: me)
        }
        // Mine only: no badge.
        #expect(attribution([me]).symbolName == nil)
        // Filled = current user in the mix; person count grows with others.
        #expect(attribution([me, "a"]).symbolName == "person.2.fill")
        #expect(attribution([me, "a", "b"]).symbolName == "person.3.fill")
        #expect(attribution([me, "a", "b", "c"]).symbolName == "person.3.fill")
        // Outline = entirely synced users.
        #expect(attribution(["a"]).symbolName == "person")
        #expect(attribution(["a", "b"]).symbolName == "person.2")
        #expect(attribution(["a", "b", "c"]).symbolName == "person.3")
        #expect(attribution(["a", "b", "c", "d"]).symbolName == "person.3")
    }

    @Test
    func includesCurrentUserDrivesFillState() {
        let me = "me@example.com"
        #expect(ObserverAttribution(observers: [me, "a"], currentObserver: me).includesCurrentUser)
        #expect(!ObserverAttribution(observers: ["a"], currentObserver: me).includesCurrentUser)
        #expect(!ObserverAttribution(observers: [me], currentObserver: me).includesCurrentUser)
    }

    // MARK: - Record observer collection

    @Test
    func recordCollectsObserversIncludingChildren() {
        let store = ObservationStore(testing: true)
        let mine = dto(observer: "me@example.com")
        let foreignChild = dto(parentId: mine.id, observer: "friend@example.com")
        store.mergeDTOs([mine, foreignChild], markDirty: false)

        let observers = store.findRecord(by: mine.id)!.observers()
        #expect(observers == ["me@example.com", "friend@example.com"])
    }

    // MARK: - Per-taxon aggregation

    @Test
    func observersByTaxonRespectsRangeAndTaxon() {
        let store = ObservationStore(testing: true)
        let mine = dto(taxonId: "amecro", observer: "me@example.com")
        let theirs = dto(taxonId: "norcar", observer: "friend@example.com")
        let outOfRange = ObservationRecordDTO(
            id: UUID(), taxonId: "houspa",
            begin: day.addingTimeInterval(-86_400), end: day.addingTimeInterval(-86_400),
            count: 1, observer: "friend@example.com"
        )
        store.mergeDTOs([mine, theirs, outOfRange], markDirty: false)

        let observers = ObservationStoreCache.observersByTaxon(in: range, from: store.observations)
        #expect(observers["amecro"] == ["me@example.com"])
        #expect(observers["norcar"] == ["friend@example.com"])
        #expect(observers["houspa"] == nil)
    }

    @Test
    func mixedTaxonYieldsMixedAttribution() {
        let store = ObservationStore(testing: true)
        let mine = dto(taxonId: "amecro", observer: "me@example.com")
        let foreignChild = dto(parentId: mine.id, taxonId: "amecro", observer: "friend@example.com")
        store.mergeDTOs([mine, foreignChild], markDirty: false)

        let observers = ObservationStoreCache.observersByTaxon(in: range, from: store.observations)
        let attribution = ObserverAttribution(
            observers: observers["amecro"] ?? [],
            currentObserver: "me@example.com"
        )
        #expect(attribution == .mixed(othersCount: 1))
    }
}
