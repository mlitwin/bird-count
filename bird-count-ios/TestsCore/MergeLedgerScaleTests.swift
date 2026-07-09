import Foundation
import Testing
@testable import BirdCountCore

/// First pairing sync merges an entire peer ledger at once — the case that
/// exposed quadratic per-record tree walks in mergeDTOs. These tests pin the
/// indexed merge's correctness on full-ledger and echo rounds.
struct MergeLedgerScaleTests {

    /// A ledger like a real one: parents each with adjustment children.
    private func ledgerDTOs(parents: Int, childrenPer: Int, observer: String) -> [ObservationRecordDTO] {
        let base = Date(timeIntervalSince1970: 1_782_900_000)
        var dtos: [ObservationRecordDTO] = []
        for p in 0..<parents {
            let parentId = UUID()
            let t = base.addingTimeInterval(Double(p))
            dtos.append(ObservationRecordDTO(
                id: parentId, taxonId: "taxon-\(p % 50)", begin: t, end: t,
                count: 1, observer: observer
            ))
            for c in 0..<childrenPer {
                dtos.append(ObservationRecordDTO(
                    id: UUID(), parentId: parentId, taxonId: "taxon-\(p % 50)",
                    begin: t, end: t, count: c % 2 == 0 ? 1 : -1, observer: observer
                ))
            }
        }
        return dtos
    }

    @Test
    func fullLedgerMergeImportsEverythingOnce() {
        let incoming = ledgerDTOs(parents: 800, childrenPer: 3, observer: "friend")
        let store = ObservationStore(testing: true)
        store.mergeDTOs(ledgerDTOs(parents: 800, childrenPer: 3, observer: "me"), markDirty: false)

        let start = Date()
        let stats = store.mergeDTOs(incoming, markDirty: true)
        let elapsed = Date().timeIntervalSince(start)

        #expect(stats.imported == incoming.count)
        #expect(stats.updated == 0)
        #expect(stats.orphansHeld == 0)
        #expect(store.allRecordIds.count == incoming.count * 2)
        // Indexed merge is O(n); the old per-record tree walk was O(n²) and
        // froze devices for minutes on ledgers this size.
        #expect(elapsed < 5)
    }

    @Test
    func echoRoundSkipsEverythingWithoutRequeue() {
        let incoming = ledgerDTOs(parents: 500, childrenPer: 2, observer: "friend")
        let store = ObservationStore(testing: true)
        store.mergeDTOs(incoming, markDirty: true)

        // The peer echoes the same records back next session.
        let stats = store.mergeDTOs(incoming, markDirty: true)
        #expect(stats.imported == 0)
        #expect(stats.updated == 0)
        #expect(stats.duplicatesSkipped == incoming.count)
    }

    @Test
    func childBeforeParentStillReattaches() {
        // Index must stay coherent when a parent arrives after its child
        // within one merge (multi-pass orphan resolution).
        let base = Date(timeIntervalSince1970: 1_782_900_000)
        let parentId = UUID()
        let child = ObservationRecordDTO(
            id: UUID(), parentId: parentId, taxonId: "amecro",
            begin: base, end: base, count: -1, observer: "friend"
        )
        let parent = ObservationRecordDTO(
            id: parentId, taxonId: "amecro", begin: base, end: base,
            count: 2, observer: "friend"
        )

        let store = ObservationStore(testing: true)
        let stats = store.mergeDTOs([child, parent], markDirty: false)
        #expect(stats.imported == 2)
        #expect(stats.orphansHeld == 0)
        #expect(store.findRecord(by: parentId)?.totalCount == 1)
    }

    @Test
    func lwwUpdateAppliesThroughIndexedPath() {
        let base = Date(timeIntervalSince1970: 1_782_900_000)
        let parentId = UUID()
        let childId = UUID()
        let store = ObservationStore(testing: true)
        store.mergeDTOs([
            ObservationRecordDTO(id: parentId, taxonId: "amecro", begin: base, end: base, count: 1, observer: "me", updatedAt: base),
            ObservationRecordDTO(id: childId, parentId: parentId, taxonId: "amecro", begin: base, end: base, count: 1, observer: "me", updatedAt: base),
        ], markDirty: false)

        // Newer copy of the CHILD: update must land at its nested position.
        let location = ObservationLocation(latitude: 38.4, longitude: -122.7, horizontalAccuracy: 5)
        let newer = ObservationRecordDTO(
            id: childId, parentId: parentId, taxonId: "amecro", begin: base, end: base,
            count: 1, location: location, observer: "me", updatedAt: base.addingTimeInterval(60)
        )
        let stats = store.mergeDTOs([newer], markDirty: false)
        #expect(stats.updated == 1)
        #expect(store.findRecord(by: childId)?.location != nil)
    }
}
