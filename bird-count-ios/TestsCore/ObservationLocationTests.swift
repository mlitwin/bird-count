import Testing
import CoreLocation
@testable import BirdCountCore

@Suite("ObservationLocation Tests")
struct ObservationLocationTests {
    
    @Test("Initialize from CLLocation")
    func testInitFromCLLocation() throws {
        // Given
        let coordinate = CLLocationCoordinate2D(latitude: 40.7831, longitude: -73.9712)
        let clLocation = CLLocation(
            coordinate: coordinate,
            altitude: 10.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            timestamp: Date()
        )
        
        // When
        let observationLocation = ObservationLocation(from: clLocation, name: "Central Park")
        
        // Then
        #expect(observationLocation.latitude == 40.7831)
        #expect(observationLocation.longitude == -73.9712)
        #expect(observationLocation.altitude == 10.0)
        #expect(observationLocation.horizontalAccuracy == 5.0)
        #expect(observationLocation.verticalAccuracy == 3.0)
        #expect(observationLocation.name == "Central Park")
        #expect(observationLocation.isValid == true)
    }
    
    @Test("Initialize from CLLocation with invalid altitude")
    func testInitFromCLLocationInvalidAltitude() throws {
        // Given
        let coordinate = CLLocationCoordinate2D(latitude: 40.7831, longitude: -73.9712)
        let clLocation = CLLocation(
            coordinate: coordinate,
            altitude: 0.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: -1.0, // Invalid vertical accuracy
            timestamp: Date()
        )
        
        // When
        let observationLocation = ObservationLocation(from: clLocation)
        
        // Then
        #expect(observationLocation.altitude == nil)
        #expect(observationLocation.verticalAccuracy == nil)
    }
    
    @Test("Initialize with explicit coordinates")
    func testInitWithCoordinates() throws {
        // Given/When
        let location = ObservationLocation(
            latitude: 37.7749,
            longitude: -122.4194,
            horizontalAccuracy: 10.0,
            name: "San Francisco"
        )
        
        // Then
        #expect(location.latitude == 37.7749)
        #expect(location.longitude == -122.4194)
        #expect(location.horizontalAccuracy == 10.0)
        #expect(location.name == "San Francisco")
        #expect(location.isValid == true)
    }
    
    @Test("Coordinate property returns correct CLLocationCoordinate2D")
    func testCoordinateProperty() throws {
        // Given
        let location = ObservationLocation(latitude: 40.7831, longitude: -73.9712)
        
        // When
        let coordinate = location.coordinate
        
        // Then
        #expect(coordinate.latitude == 40.7831)
        #expect(coordinate.longitude == -73.9712)
    }
    
    @Test("Distance calculation between locations")
    func testDistanceCalculation() throws {
        // Given
        let location1 = ObservationLocation(latitude: 40.7831, longitude: -73.9712) // Central Park
        let location2 = ObservationLocation(latitude: 40.7589, longitude: -73.9851) // Times Square
        
        // When
        let distance = location1.distance(to: location2)
        
        // Then - Distance should be roughly 2.8 km between Central Park and Times Square
        #expect(distance > 2500 && distance < 3000)
    }
    
    @Test("Formatted coordinates string")
    func testFormattedCoordinates() throws {
        // Given
        let location = ObservationLocation(latitude: 40.7831, longitude: -73.9712)
        
        // When
        let formatted = location.formattedCoordinates()
        
        // Then
        #expect(formatted == "40.783100°N 73.971200°W")
    }
    
    @Test("Display name falls back to coordinates")
    func testDisplayNameFallback() throws {
        // Given
        let locationWithName = ObservationLocation(latitude: 40.7831, longitude: -73.9712, name: "Central Park")
        let locationWithoutName = ObservationLocation(latitude: 40.7831, longitude: -73.9712)
        
        // Then
        #expect(locationWithName.displayName == "Central Park")
        #expect(locationWithoutName.displayName == "40.783100°N 73.971200°W")
    }
    
    @Test("Accuracy description")
    func testAccuracyDescription() throws {
        // Given/When/Then
        let excellent = ObservationLocation(latitude: 0, longitude: 0, horizontalAccuracy: 3.0)
        #expect(excellent.accuracyDescription == "Excellent")
        
        let good = ObservationLocation(latitude: 0, longitude: 0, horizontalAccuracy: 8.0)
        #expect(good.accuracyDescription == "Good")
        
        let fair = ObservationLocation(latitude: 0, longitude: 0, horizontalAccuracy: 25.0)
        #expect(fair.accuracyDescription == "Fair")
        
        let poor = ObservationLocation(latitude: 0, longitude: 0, horizontalAccuracy: 100.0)
        #expect(poor.accuracyDescription == "Poor")
        
        let invalid = ObservationLocation(latitude: 0, longitude: 0, horizontalAccuracy: -1.0)
        #expect(invalid.accuracyDescription == "Invalid")
    }
    
    @Test("Mock location factory")
    func testMockLocation() throws {
        // Given/When
        let mockLocation = ObservationLocation.mock()
        
        // Then
        #expect(mockLocation.name == "Mock Location")
        #expect(mockLocation.latitude == 40.7831)
        #expect(mockLocation.longitude == -73.9712)
        #expect(mockLocation.isValid == true)
    }
    
    @Test("Unknown location factory")
    func testUnknownLocation() throws {
        // Given/When
        let unknownLocation = ObservationLocation.unknown
        
        // Then
        #expect(unknownLocation.name == "Unknown Location")
        #expect(unknownLocation.latitude == 0.0)
        #expect(unknownLocation.longitude == 0.0)
        #expect(unknownLocation.isValid == false)
    }
    
    @Test("Codable conformance - encode and decode")
    func testCodableConformance() throws {
        // Given
        let originalLocation = ObservationLocation(
            latitude: 40.7831,
            longitude: -73.9712,
            horizontalAccuracy: 5.0,
            timestamp: Date(),
            altitude: 10.0,
            verticalAccuracy: 3.0,
            name: "Test Location",
            notes: "Test notes"
        )
        
        // When - Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalLocation)
        
        // Then - Decode
        let decoder = JSONDecoder()
        let decodedLocation = try decoder.decode(ObservationLocation.self, from: data)
        
        // Verify all properties match
        #expect(decodedLocation.latitude == originalLocation.latitude)
        #expect(decodedLocation.longitude == originalLocation.longitude)
        #expect(decodedLocation.horizontalAccuracy == originalLocation.horizontalAccuracy)
        #expect(decodedLocation.altitude == originalLocation.altitude)
        #expect(decodedLocation.verticalAccuracy == originalLocation.verticalAccuracy)
        #expect(decodedLocation.name == originalLocation.name)
        #expect(decodedLocation.notes == originalLocation.notes)
    }
    
    @Test("Equatable conformance")
    func testEquatableConformance() throws {
        // Given - Use fixed timestamp to avoid flaky comparison
        let fixedTimestamp = Date(timeIntervalSince1970: 1695312000)
        
        let location1 = ObservationLocation(
            latitude: 40.7831, 
            longitude: -73.9712, 
            horizontalAccuracy: 5.0,
            timestamp: fixedTimestamp,
            name: "Test"
        )
        let location2 = ObservationLocation(
            latitude: 40.7831, 
            longitude: -73.9712, 
            horizontalAccuracy: 5.0,
            timestamp: fixedTimestamp,
            name: "Test"
        )
        let location3 = ObservationLocation(
            latitude: 40.7832, 
            longitude: -73.9712, 
            horizontalAccuracy: 5.0,
            timestamp: fixedTimestamp,
            name: "Test"
        )
        
        // Then
        #expect(location1 == location2)
        #expect(location1 != location3)
    }
}
