import Foundation
import Testing
@testable import BirdCount

struct ObservationSyncTests {
    
    @Test func testExportForSync() {
        let observationStore = ObservationStore()
        
        // Add some test observations
        observationStore.addObservation("amecro", begin: Date(), end: nil, count: 2)
        observationStore.addObservation("norbla", begin: Date().addingTimeInterval(-3600), end: nil, count: 1)
        
        // Create a date range that includes all observations
        let startDate = Date().addingTimeInterval(-7200) // 2 hours ago
        let endDate = Date().addingTimeInterval(3600)    // 1 hour from now
        let range = DateRange(begin: startDate, end: endDate)
        
        // Export observations for sync
        let payload = ObservationExportService.exportForSync(in: range, from: observationStore)
        
        // Verify payload structure
        #expect(payload.schemaVersion == 1)
        #expect(!payload.appVersion.isEmpty)
        #expect(!payload.senderDisplayName.isEmpty)
        #expect(payload.rangeStart == startDate)
        #expect(payload.rangeEnd == endDate)
        #expect(payload.observations.count == 2)
        
        // Check individual observations
        let taxonIds = Set(payload.observations.map { $0.taxonId })
        #expect(taxonIds.contains("amecro"))
        #expect(taxonIds.contains("norbla"))
    }
    
    @Test func testImportFromSync() {
        let observationStore = ObservationStore()
        
        // Create a payload to import
        let observations = [
            ObservationRecordDTO(id: UUID(), parentId: nil, taxonId: "redwin", begin: Date(), end: Date(), count: 3, observer: "test@example.com"),
            ObservationRecordDTO(id: UUID(), parentId: nil, taxonId: "blujay", begin: Date(), end: Date(), count: 1, observer: "test@example.com")
        ]
        
        let payload = PayloadV1(
            schemaVersion: 1,
            appVersion: "1.0.0",
            senderDisplayName: "Test Device",
            rangeStart: Date().addingTimeInterval(-3600),
            rangeEnd: Date(),
            observations: observations
        )
        
        // Verify store is initially empty
        #expect(observationStore.observations.count == 0)
        
        // Import the payload
        do {
            try ObservationImportService.importFromSync(payload, into: observationStore)
        } catch {
            #expect(Bool(false), "Import failed with error: \(error)")
            return
        }
        
        // Debug output
        print("Imported observations count: \(observationStore.observations.count)")
        for obs in observationStore.observations {
            print("- \(obs.taxonId): count=\(obs.count), observer='\(obs.observer)'")
        }
        
        // Verify observations were imported
        #expect(observationStore.observations.count == 2)
        
        let importedTaxa = Set(observationStore.observations.map { $0.taxonId })
        #expect(importedTaxa.contains("redwin"))
        #expect(importedTaxa.contains("blujay"))
    }
    
    @Test func testImportDeduplication() {
        let observationStore = ObservationStore()
        
        // Add an observation to the store
        let existingId = UUID()
        let existingRecord = ObservationRecord(id: existingId, taxonId: "amecro", begin: Date(), end: nil, count: 1, observer: "")
        observationStore.importObservations([existingRecord])
        
        // Create a payload with the same observation ID (should be deduplicated)
        let duplicateObservation = ObservationRecordDTO(id: existingId, parentId: nil, taxonId: "amecro", begin: Date(), end: Date(), count: 2, observer: "test@example.com")
        let newObservation = ObservationRecordDTO(id: UUID(), parentId: nil, taxonId: "norbla", begin: Date(), end: Date(), count: 1, observer: "test@example.com")
        
        let payload = PayloadV1(
            schemaVersion: 1,
            appVersion: "1.0.0",
            senderDisplayName: "Test Device",
            rangeStart: Date().addingTimeInterval(-3600),
            rangeEnd: Date(),
            observations: [duplicateObservation, newObservation]
        )
        
        // Import the payload
        #expect(throws: Never.self) { try ObservationImportService.importFromSync(payload, into: observationStore) }
        
        // Verify only the new observation was added (duplicate was skipped)
        #expect(observationStore.observations.count == 2)
        
        // Verify the existing observation was not modified
        let existingObservation = observationStore.findRecord(by: existingId)
        #expect(existingObservation != nil)
        #expect(existingObservation?.count == 1) // Original count, not the duplicate's count
    }
    
    @Test func testUnsupportedSchemaVersion() {
        let observationStore = ObservationStore()
        
        let payload = PayloadV1(
            schemaVersion: 999, // Unsupported version
            appVersion: "1.0.0",
            senderDisplayName: "Test Device",
            rangeStart: Date().addingTimeInterval(-3600),
            rangeEnd: Date(),
            observations: []
        )
        
        #expect(throws: ObservationImportService.ImportError.unsupportedSchemaVersion(999)) {
            try ObservationImportService.importFromSync(payload, into: observationStore)
        }
    }
}
