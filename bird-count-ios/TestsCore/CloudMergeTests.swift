import Foundation
import Testing
@testable import BirdCountCore

struct CloudMergeTests {
    private func dto(
        _ id: UUID = UUID(),
        parentId: UUID? = nil,
        taxonId: String = "amecro",
        count: Int = 1,
        updatedAt: Date? = nil,
        location: ObservationLocation? = nil
    ) -> ObservationRecordDTO {
        let end = Date(timeIntervalSince1970: 1_782_900_000)
        return ObservationRecordDTO(
            id: id, parentId: parentId, taxonId: taxonId,
            begin: end, end: end, count: count,
            location: location, observer: "test", status: .completed,
            updatedAt: updatedAt
        )
    }

    @Test
    func putIfAbsentImportsNewRecords() {
        let store = ObservationStore(testing: true)
        let stats = store.mergeDTOs([dto(), dto(taxonId: "norcar", count: 2)], markDirty: false)
        #expect(stats.imported == 2)
        #expect(store.totalIndividuals == 3)
    }

    @Test
    func lwwNewerUpdateWins() {
        let store = ObservationStore(testing: true)
        let id = UUID()
        let base = Date(timeIntervalSince1970: 1_782_900_000)
        store.mergeDTOs([dto(id, updatedAt: base)], markDirty: false)

        let location = ObservationLocation(latitude: 38.4, longitude: -122.7, horizontalAccuracy: 5)
        let stats = store.mergeDTOs(
            [dto(id, updatedAt: base.addingTimeInterval(60), location: location)],
            markDirty: false
        )
        #expect(stats.updated == 1)
        #expect(store.findRecord(by: id)?.location != nil)
    }

    @Test
    func lwwOlderCopyIsSkipped() {
        let store = ObservationStore(testing: true)
        let id = UUID()
        let base = Date(timeIntervalSince1970: 1_782_900_000)
        store.mergeDTOs([dto(id, updatedAt: base)], markDirty: false)

        let location = ObservationLocation(latitude: 38.4, longitude: -122.7, horizontalAccuracy: 5)
        let stats = store.mergeDTOs(
            [dto(id, updatedAt: base.addingTimeInterval(-60), location: location)],
            markDirty: false
        )
        #expect(stats.duplicatesSkipped == 1)
        #expect(store.findRecord(by: id)?.location == nil)
    }

    @Test
    func childBeforeParentInSameBatchAttaches() {
        let store = ObservationStore(testing: true)
        let parentId = UUID()
        let childId = UUID()
        // child listed first: merge must still attach it under the parent
        let stats = store.mergeDTOs(
            [dto(childId, parentId: parentId, count: -1), dto(parentId)],
            markDirty: false
        )
        #expect(stats.imported == 2)
        #expect(stats.orphansHeld == 0)
        let parent = store.findRecord(by: parentId)
        #expect(parent?.children.first?.id == childId)
        #expect(parent?.totalCount == 0)
    }

    @Test
    func orphanIsHeldThenReattachedOnLaterMerge() {
        let store = ObservationStore(testing: true)
        let parentId = UUID()
        let childId = UUID()

        let first = store.mergeDTOs([dto(childId, parentId: parentId, count: -1)], markDirty: false)
        #expect(first.orphansHeld == 1)
        #expect(store.findRecord(by: childId) == nil)

        let second = store.mergeDTOs([dto(parentId)], markDirty: false)
        #expect(second.orphansHeld == 0)
        #expect(store.findRecord(by: childId) != nil)
        #expect(store.findRecord(by: parentId)?.totalCount == 0)
    }

    @Test
    func p2pMergeMarksDirtyButCloudApplyDoesNot() {
        let store = ObservationStore(testing: true)
        let p2p = dto()
        let cloud = dto()
        store.mergeDTOs([p2p], markDirty: true)
        store.mergeDTOs([cloud], markDirty: false)
        #expect(store.dirtyIds.contains(p2p.id))
        #expect(!store.dirtyIds.contains(cloud.id))
    }

    @Test
    func creationMarksDirtyAndClearAllResetsCloudState() {
        let store = ObservationStore(testing: true)
        store.addObservation("amecro")
        #expect(store.dirtyIds.count == 1)
        store.cloudSyncCursor = "12345"
        store.clearAll()
        #expect(store.dirtyIds.isEmpty)
        #expect(store.cloudSyncCursor == nil)
    }

    @Test
    func dirtyIdsAndCursorSurviveRelaunch() throws {
        // Offline queueing: dirty state written by one store instance must be
        // visible to a freshly-initialized one (simulating an app relaunch).
        // Isolated suite: tests run concurrently and .standard is shared.
        let suiteName = "CloudMergeTests-relaunch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ObservationStore(testing: true, defaults: defaults)
        first.addObservation("amecro")
        first.cloudSyncCursor = "1782914800456"
        // Record persists are coalesced/async; the app flushes on
        // backgrounding, which is what a relaunch implies.
        first.flushPendingPersist()
        let dirty = first.dirtyIds
        #expect(dirty.count == 1)

        let relaunched = ObservationStore(testing: false, defaults: defaults)
        #expect(relaunched.dirtyIds == dirty)
        #expect(relaunched.cloudSyncCursor == "1782914800456")
        #expect(relaunched.observations.count == 1)
    }

    @Test
    func dtoWireFormatUsesMillisecondUpdatedAt() throws {
        let record = dto(updatedAt: Date(timeIntervalSince1970: 1_782_914_790))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(record)) as? [String: Any]
        )
        #expect(json["updatedAt"] as? Int64 == 1_782_914_790_000)
        #expect(json["begin"] is String) // other dates stay ISO8601
    }
}
