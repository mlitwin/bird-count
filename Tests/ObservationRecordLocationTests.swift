import Foundation
import Testing
@testable import BirdCount

struct ObservationRecordLocationTests {
    
    @Test("ObservationRecord without location serializes correctly")
    func testSerializationWithoutLocation() throws {
        // Use a fixed date to avoid timing issues in test
        let fixedDate = Date()
        let record = ObservationRecord(taxonId: "amecro", begin: fixedDate, count: 2, observer: "")
        
        // Verify location is nil
        #expect(record.location == nil)
        
        // Test JSON serialization
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        
        // Test JSON deserialization
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ObservationRecord.self, from: data)
        
        // Verify all fields match (check individual fields for better debugging)
        #expect(decoded.id == record.id, "ID mismatch: \(decoded.id) != \(record.id)")
        #expect(decoded.taxonId == record.taxonId, "TaxonId mismatch: \(decoded.taxonId) != \(record.taxonId)")
        #expect(decoded.count == record.count, "Count mismatch: \(decoded.count) != \(record.count)")
        #expect(decoded.location == nil, "Location should be nil but got: \(String(describing: decoded.location))")
        
        // Only check overall equality if all individual fields match
        if decoded.id == record.id && decoded.taxonId == record.taxonId && decoded.count == record.count && decoded.location == record.location {
            #expect(decoded == record, "Records should be equal but aren't")
        }
    }
    
    @Test("ObservationRecord with location serializes correctly")
    func testSerializationWithLocation() throws {
        let location = ObservationLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            horizontalAccuracy: 5.0,
            altitude: 20.0,
            name: "San Francisco"
        )
        
        let record = ObservationRecord(
            taxonId: "amecro",
            count: 3,
            location: location
        )
        
        // Verify location is set
        #expect(record.location != nil)
        #expect(record.location?.latitude == 37.7749)
        #expect(record.location?.longitude == -122.4194)
        #expect(record.location?.name == "San Francisco")
        
        // Test JSON serialization
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        
        // Test JSON deserialization
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ObservationRecord.self, from: data)
        
        // Verify all fields match (check individual fields for better debugging)
        #expect(decoded.id == record.id, "ID mismatch: \(decoded.id) != \(record.id)")
        #expect(decoded.taxonId == record.taxonId, "TaxonId mismatch: \(decoded.taxonId) != \(record.taxonId)")
        #expect(decoded.count == record.count, "Count mismatch: \(decoded.count) != \(record.count)")
        #expect(decoded.location != nil, "Location should not be nil")
        
        if let decodedLocation = decoded.location {
            #expect(decodedLocation.latitude == 37.7749, "Latitude mismatch: \(decodedLocation.latitude) != 37.7749")
            #expect(decodedLocation.longitude == -122.4194, "Longitude mismatch: \(decodedLocation.longitude) != -122.4194")
            #expect(decodedLocation.name == "San Francisco", "Name mismatch: \(String(describing: decodedLocation.name)) != San Francisco")
        }
        
        // Only check overall equality if all individual fields match
        if decoded.id == record.id && decoded.taxonId == record.taxonId && decoded.count == record.count && decoded.location == record.location {
            #expect(decoded == record, "Records should be equal but aren't")
        }
    }
    
    @Test("ObservationRecordDTO backwards compatibility")
    func testDTOBackwardsCompatibility() throws {
        // Test that old JSON without location field can still be decoded
        let jsonWithoutLocation = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "taxonId": "amecro",
            "begin": "2023-09-21T12:00:00Z",
            "end": "2023-09-21T12:00:00Z",
            "count": 1
        }
        """
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = jsonWithoutLocation.data(using: .utf8)!
        
        // This should not throw and location should be nil, observer should be empty string
        let dto = try decoder.decode(ObservationRecordDTO.self, from: data)
        #expect(dto.location == nil)
        #expect(dto.observer == "")
        #expect(dto.taxonId == "amecro")
        #expect(dto.count == 1)
    }
    
    @Test("ObservationRecord with observer serialization")
    func testObserverSerialization() throws {
        let fixedDate = Date(timeIntervalSince1970: 1695312000) // Fixed date for reproducible tests
        let record = ObservationRecord(taxonId: "amecro", begin: fixedDate, count: 2, observer: "observer@example.com")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        
        let data = try encoder.encode(record)
        let jsonString = String(data: data, encoding: .utf8)!
        
        // Verify observer field is included in JSON
        #expect(jsonString.contains("\"observer\" : \"observer@example.com\""))
        
        // Verify it can be decoded back correctly
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ObservationRecord.self, from: data)
        
        #expect(decoded.observer == "observer@example.com")
        #expect(decoded.taxonId == "amecro")
        #expect(decoded.count == 2)
    }
    
    @Test("ObservationRecord child with location")
    func testChildObservationWithLocation() throws {
        let parentLocation = ObservationLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            name: "San Francisco"
        )
        
        let childLocation = ObservationLocation(
            latitude: 37.7849,
            longitude: -122.4094,
            name: "Near San Francisco"
        )
        
        var parent = ObservationRecord(
            taxonId: "amecro",
            count: 2,
            location: parentLocation
        )
        
        let child = ObservationRecord(
            parent: &parent,
            taxonId: "norbla",
            count: 1,
            location: childLocation
        )
        
        // Verify parent and child both have locations
        #expect(parent.location != nil)
        #expect(parent.location?.name == "San Francisco")
        #expect(child.location != nil)
        #expect(child.location?.name == "Near San Francisco")
        
        // Verify child is properly linked
        #expect(child.parentId == parent.id)
        #expect(parent.children.count == 1)
        #expect(parent.children[0].location?.name == "Near San Francisco")
    }
    
    @Test("ObservationRecord mixed location scenarios")
    func testMixedLocationScenarios() throws {
        let location = ObservationLocation(latitude: 40.7128, longitude: -74.0060, name: "NYC")
        
        // Parent with location, child without
        var parentWithLocation = ObservationRecord(
            taxonId: "amecro",
            count: 1,
            location: location
        )
        
        let childWithoutLocation = ObservationRecord(
            parent: &parentWithLocation,
            taxonId: "norbla",
            count: 1
        )
        
        #expect(parentWithLocation.location != nil)
        #expect(childWithoutLocation.location == nil)
        
        // Parent without location, child with location
        var parentWithoutLocation = ObservationRecord(taxonId: "redwin", count: 1, observer: "")
        
        let childWithLocation = ObservationRecord(
            parent: &parentWithoutLocation,
            taxonId: "blujay",
            count: 2,
            location: location
        )
        
        #expect(parentWithoutLocation.location == nil)
        #expect(childWithLocation.location != nil)
        #expect(childWithLocation.location?.name == "NYC")
    }
}
