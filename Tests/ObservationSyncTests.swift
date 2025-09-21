import XCTest
@testable import BirdCount

final class ObservationSyncTests: XCTestCase {
    
    var exportService: ObservationExportService!
    var importService: ObservationImportService!
    var observationStore: ObservationStore!
    
    override func setUp() {
        super.setUp()
        exportService = ObservationExportService()
        importService = ObservationImportService()
        observationStore = ObservationStore()
    }
    
    override func tearDown() {
        exportService = nil
        importService = nil
        observationStore = nil
        super.tearDown()
    }
    
    func testExportForSync() {
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
        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertFalse(payload.appVersion.isEmpty)
        XCTAssertFalse(payload.senderDisplayName.isEmpty)
        XCTAssertEqual(payload.rangeStart, startDate)
        XCTAssertEqual(payload.rangeEnd, endDate)
        XCTAssertEqual(payload.observations.count, 2)
        
        // Check individual observations
        let taxonIds = Set(payload.observations.map { $0.taxonId })
        XCTAssertTrue(taxonIds.contains("amecro"))
        XCTAssertTrue(taxonIds.contains("norbla"))
    }
    
    func testImportFromSync() {
        // Create a payload to import
        let observations = [
            ObservationRecordDTO(id: UUID(), parentId: nil, taxonId: "redwin", begin: Date(), end: Date(), count: 3),
            ObservationRecordDTO(id: UUID(), parentId: nil, taxonId: "blujay", begin: Date(), end: Date(), count: 1)
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
        XCTAssertEqual(observationStore.observations.count, 0)
        
        // Import the payload
        XCTAssertNoThrow(try ObservationImportService.importFromSync(payload, into: observationStore))
        
        // Verify observations were imported
        XCTAssertEqual(observationStore.observations.count, 2)
        
        let importedTaxa = Set(observationStore.observations.map { $0.taxonId })
        XCTAssertTrue(importedTaxa.contains("redwin"))
        XCTAssertTrue(importedTaxa.contains("blujay"))
    }
    
    func testImportDeduplication() {
        // Add an observation to the store
        let existingId = UUID()
        let existingRecord = ObservationRecord(id: existingId, taxonId: "amecro", begin: Date(), end: nil, count: 1)
        observationStore.importObservations([existingRecord])
        
        // Create a payload with the same observation ID (should be deduplicated)
        let duplicateObservation = ObservationRecordDTO(id: existingId, parentId: nil, taxonId: "amecro", begin: Date(), end: Date(), count: 2)
        let newObservation = ObservationRecordDTO(id: UUID(), parentId: nil, taxonId: "norbla", begin: Date(), end: Date(), count: 1)
        
        let payload = PayloadV1(
            schemaVersion: 1,
            appVersion: "1.0.0",
            senderDisplayName: "Test Device",
            rangeStart: Date().addingTimeInterval(-3600),
            rangeEnd: Date(),
            observations: [duplicateObservation, newObservation]
        )
        
        // Import the payload
        XCTAssertNoThrow(try ObservationImportService.importFromSync(payload, into: observationStore))
        
        // Verify only the new observation was added (duplicate was skipped)
        XCTAssertEqual(observationStore.observations.count, 2)
        
        // Verify the existing observation was not modified
        let existingObservation = observationStore.findRecord(by: existingId)
        XCTAssertNotNil(existingObservation)
        XCTAssertEqual(existingObservation?.count, 1) // Original count, not the duplicate's count
    }
    
    func testUnsupportedSchemaVersion() {
        let payload = PayloadV1(
            schemaVersion: 999, // Unsupported version
            appVersion: "1.0.0",
            senderDisplayName: "Test Device",
            rangeStart: Date().addingTimeInterval(-3600),
            rangeEnd: Date(),
            observations: []
        )
        
        XCTAssertThrowsError(try ObservationImportService.importFromSync(payload, into: observationStore)) { error in
            if case ObservationImportService.ImportError.unsupportedSchemaVersion(let version) = error {
                XCTAssertEqual(version, 999)
            } else {
                XCTFail("Expected unsupportedSchemaVersion error")
            }
        }
    }
}
