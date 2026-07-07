import Foundation
import Testing
@testable import BirdCount

@Suite("ObservationSync")
struct ObservationSyncTests {

    // MARK: - Helpers

    private func makeStore() -> ObservationStore {
        let store = ObservationStore()
        store.clearAll()
        return store
    }

    private func makeRange() -> DateRange {
        DateRange(begin: Date().addingTimeInterval(-7200), end: Date().addingTimeInterval(3600))
    }

    private func makePayload(taxonIds: [String], observer: String = "peer@example.com") -> PayloadV1 {
        let obs = taxonIds.map { taxonId in
            ObservationRecordDTO(id: UUID(), taxonId: taxonId,
                                 begin: Date(), end: Date(), count: 1, observer: observer)
        }
        return PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: obs
        )
    }

    // MARK: - Export

    @Test func exportIncludesAllObservationsInRange() {
        let store = makeStore()
        store.addObservation("amecro", begin: Date(), end: nil, count: 2)
        store.addObservation("norbla", begin: Date().addingTimeInterval(-3600), end: nil, count: 1)

        let range = makeRange()
        let payload = ObservationExportService.exportForSync(displayName: "Test Device", in: range, from: store)

        #expect(payload.schemaVersion == 2)
        #expect(!payload.appVersion.isEmpty)
        #expect(payload.rangeStart == range.begin)
        #expect(payload.rangeEnd == range.end)
        #expect(Set(payload.observations.map { $0.taxonId }) == ["amecro", "norbla"])
    }

    @Test func exportExcludesObservationsOutsideRange() {
        let store = makeStore()
        store.addObservation("amecro", begin: Date(), end: nil, count: 1)

        // Range in the far past — should capture nothing
        let pastRange = DateRange(
            begin: Date().addingTimeInterval(-86400 * 365),
            end: Date().addingTimeInterval(-86400 * 364)
        )
        let payload = ObservationExportService.exportForSync(displayName: "Test", in: pastRange, from: store)
        #expect(payload.observations.isEmpty)
    }

    // MARK: - Import

    @Test func importAddsNewObservations() throws {
        let store = makeStore()
        _ = try ObservationImportService.importFromSync(makePayload(taxonIds: ["redwin", "blujay"]), into: store)
        #expect(store.observations.count == 2)
        #expect(Set(store.observations.map { $0.taxonId }) == ["redwin", "blujay"])
    }

    @Test func importDeduplicatesByID() throws {
        let store = makeStore()
        let existingId = UUID()
        // Records are immutable ledger entries: a re-received copy is
        // byte-identical, so it carries the same timestamps (equal updatedAt
        // -> deduplicated, not LWW-applied).
        let created = Date()
        store.importObservations([ObservationRecord(id: existingId, taxonId: "amecro",
                                                    begin: created, end: nil, count: 1, observer: "")])

        let payload = PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: [
                ObservationRecordDTO(id: existingId, taxonId: "amecro",
                                     begin: created, end: created, count: 1, observer: ""),
                ObservationRecordDTO(id: UUID(), taxonId: "norbla",
                                     begin: Date(), end: Date(), count: 1, observer: "peer@example.com")
            ]
        )
        let stats = try ObservationImportService.importFromSync(payload, into: store)

        #expect(stats.duplicatesSkipped == 1)
        #expect(stats.newRecordsImported == 1)
        #expect(store.observations.count == 2)
        // Original count preserved — duplicate was skipped, not applied
        #expect(store.findRecord(by: existingId)?.count == 1)
    }

    @Test func importAppliesNewerCopyViaLastWriterWins() throws {
        let store = makeStore()
        let existingId = UUID()
        let created = Date()
        store.importObservations([ObservationRecord(id: existingId, taxonId: "amecro",
                                                    begin: created, end: nil, count: 1, observer: "")])

        // Same record with a newer updatedAt (the location backfill case)
        let location = ObservationLocation(latitude: 38.4, longitude: -122.7, horizontalAccuracy: 5)
        let payload = PayloadV1(
            schemaVersion: 2, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: [
                ObservationRecordDTO(id: existingId, taxonId: "amecro",
                                     begin: created, end: created, count: 1,
                                     location: location, observer: "",
                                     updatedAt: created.addingTimeInterval(60))
            ]
        )
        let stats = try ObservationImportService.importFromSync(payload, into: store)

        #expect(stats.newRecordsImported == 1) // counted as an update
        #expect(store.findRecord(by: existingId)?.location != nil)
    }

    @Test func orphanedChildAttachesToExistingParent() throws {
        let store = makeStore()
        let parentId = UUID()
        store.importObservations([ObservationRecord(id: parentId, taxonId: "amecro",
                                                    begin: Date(), end: nil, count: 1, observer: "")])

        let payload = PayloadV1(
            schemaVersion: 1, appVersion: "1.0", senderDisplayName: "Peer",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: [ObservationRecordDTO(id: UUID(), parentId: parentId, taxonId: "amecro",
                                                begin: Date(), end: Date(), count: 1, observer: "peer@example.com")]
        )
        let stats = try ObservationImportService.importFromSync(payload, into: store)

        #expect(stats.totalRecordsProcessed == 1)
        #expect(store.observations.count == 1)
        #expect(store.observations.first?.children.count == 1)
    }

    @Test func unsupportedSchemaVersionThrows() {
        let store = makeStore()
        let payload = PayloadV1(
            schemaVersion: 999, appVersion: "1.0", senderDisplayName: "Test",
            rangeStart: Date().addingTimeInterval(-3600), rangeEnd: Date(),
            observations: []
        )
        #expect(throws: ObservationImportService.ImportError.unsupportedSchemaVersion(999)) {
            try ObservationImportService.importFromSync(payload, into: store)
        }
    }
}
