import Foundation
import Testing
@testable import BirdCountCore

struct ObservationImportTests {
    
    @Test
    func jsonImportBasicTest() throws {
        let store = ObservationStore(testing: true)
        store.clearAll()
        
        // Create sample JSON data matching our export format
        let jsonData = """
        {
            "metadata": {
                "exportDate": "2025-09-28T12:00:00Z",
                "dateRange": {
                    "begin": "2025-09-28T10:00:00Z",
                    "end": "2025-09-28T14:00:00Z"
                },
                "totalObservations": 2
            },
            "observations": [
                {
                    "id": "12345678-1234-1234-1234-123456789abc",
                    "taxonId": "amecro",
                    "count": 3,
                    "begin": "2025-09-28T11:00:00Z",
                    "end": "2025-09-28T11:05:00Z",
                    "location": {
                        "latitude": 42.3601,
                        "longitude": -71.0589,
                        "horizontalAccuracy": 5.0,
                        "timestamp": "2025-09-28T11:00:00Z",
                        "altitude": 10.0,
                        "verticalAccuracy": 3.0,
                        "name": "Boston Common",
                        "notes": "Near the pond"
                    },
                    "children": []
                },
                {
                    "id": "87654321-4321-4321-4321-cba987654321",
                    "taxonId": "norcar",
                    "count": 1,
                    "begin": "2025-09-28T12:00:00Z",
                    "end": "2025-09-28T12:02:00Z",
                    "children": []
                }
            ]
        }
        """
        
        // Verify store is empty
        #expect(store.totalSpeciesObserved == 0)
        #expect(store.totalIndividuals == 0)
        
        // Import the data
        try ObservationJSONImportService.importFromJSON(jsonData, into: store)
        
        // Verify import results
        #expect(store.totalSpeciesObserved == 2)
        #expect(store.totalIndividuals == 4)
        #expect(store.count(for: "amecro") == 3)
        #expect(store.count(for: "norcar") == 1)
    }
    
    @Test
    func jsonImportWithChildrenTest() throws {
        let store = ObservationStore(testing: true)
        store.clearAll()
        
        // Create JSON data with parent-child relationships
        let jsonData = """
        {
            "metadata": {
                "exportDate": "2025-09-28T12:00:00Z",
                "dateRange": {
                    "begin": "2025-09-28T10:00:00Z",
                    "end": "2025-09-28T14:00:00Z"
                },
                "totalObservations": 1
            },
            "observations": [
                {
                    "id": "12345678-1234-1234-1234-123456789abc",
                    "taxonId": "amecro",
                    "count": 5,
                    "begin": "2025-09-28T11:00:00Z",
                    "end": "2025-09-28T11:05:00Z",
                    "children": [
                        {
                            "id": "11111111-1111-1111-1111-111111111111",
                            "taxonId": "amecro",
                            "count": 2,
                            "begin": "2025-09-28T11:01:00Z",
                            "end": "2025-09-28T11:02:00Z"
                        },
                        {
                            "id": "22222222-2222-2222-2222-222222222222",
                            "taxonId": "amecro",
                            "count": 3,
                            "begin": "2025-09-28T11:03:00Z",
                            "end": "2025-09-28T11:04:00Z"
                        }
                    ]
                }
            ]
        }
        """
        
        // Import the data
        try ObservationJSONImportService.importFromJSON(jsonData, into: store)
        
        // Verify import results - should have parent + children counts
        #expect(store.totalSpeciesObserved == 1)
        #expect(store.totalIndividuals == 10) // 5 + 2 + 3
        #expect(store.count(for: "amecro") == 10)
    }
    
    @Test 
    func jsonImportInvalidFormatTest() throws {
        let store = ObservationStore(testing: true)
        
        // Test invalid JSON
        let invalidJSON = "{ invalid json }"
        
        do {
            try ObservationJSONImportService.importFromJSON(invalidJSON, into: store)
            #expect(Bool(false), "Should have thrown an error for invalid JSON")
        } catch {
            // Expected to throw an error
            #expect(error is ObservationJSONImportService.ImportError)
        }
    }
    
    @Test
    func jsonImportMissingObservationsTest() throws {
        let store = ObservationStore(testing: true)
        
        // Test JSON without observations array
        let jsonWithoutObservations = """
        {
            "metadata": {
                "exportDate": "2025-09-28T12:00:00Z"
            }
        }
        """
        
        do {
            try ObservationJSONImportService.importFromJSON(jsonWithoutObservations, into: store)
            #expect(Bool(false), "Should have thrown an error for missing observations")
        } catch {
            // Expected to throw an error
            #expect(error is ObservationJSONImportService.ImportError)
        }
    }
}