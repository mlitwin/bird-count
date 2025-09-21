import Testing
import CoreLocation
@testable import BirdCount

@Suite("ObservationStore Location Tests")
struct ObservationStoreLocationTests {
    
    @Test("Add observation with location")
    func testAddObservationWithLocation() throws {
        // Given
        let store = ObservationStore()
        let location = ObservationLocation.mock()
        
        // When
        store.addObservation("testTaxon", location: location)
        
        // Then
        #expect(store.observations.count == 1)
        let observation = store.observations.first!
        #expect(observation.taxonId == "testTaxon")
        #expect(observation.location?.latitude == location.latitude)
        #expect(observation.location?.longitude == location.longitude)
        #expect(observation.location?.displayName == location.displayName)
    }
    
    @Test("Add child observation with location")
    func testAddChildObservationWithLocation() throws {
        // Given
        let store = ObservationStore()
        let parentLocation = ObservationLocation.mock(name: "Parent Location")
        let childLocation = ObservationLocation.mock(name: "Child Location", latitude: 41.0, longitude: -74.0)
        
        // Create parent observation
        store.addObservation("parentTaxon", location: parentLocation)
        let parentId = store.observations.first!.id
        
        // When
        let success = store.addChildObservation(parentId: parentId, taxonId: "childTaxon", location: childLocation)
        
        // Then
        #expect(success == true)
        #expect(store.observations.count == 1) // Still one root observation
        let parent = store.observations.first!
        #expect(parent.children.count == 1)
        
        let child = parent.children.first!
        #expect(child.taxonId == "childTaxon")
        #expect(child.location?.displayName == childLocation.displayName)
    }
    
    @Test("Add observation with location - automatic capture when authorized")
    func testAddObservationWithLocationAutomatic() throws {
        // Given
        let store = ObservationStore()
        
        // When - Call location-aware method
        store.addObservationWithLocation("testTaxon")
        
        // Then - Observation should be created (with or without location depending on permissions)
        #expect(store.observations.count == 1)
        let observation = store.observations.first!
        #expect(observation.taxonId == "testTaxon")
        // Location may or may not be present depending on LocationManager authorization state
    }
    
    @Test("Add child observation with location - automatic capture when authorized")
    func testAddChildObservationWithLocationAutomatic() throws {
        // Given
        let store = ObservationStore()
        
        // Create parent observation first
        store.addObservation("parentTaxon")
        let parentId = store.observations.first!.id
        
        // When - Call location-aware method
        let success = store.addChildObservationWithLocation(parentId: parentId, taxonId: "childTaxon")
        
        // Then
        #expect(success == true)
        #expect(store.observations.count == 1) // Still one root observation
        let parent = store.observations.first!
        #expect(parent.children.count == 1)
        #expect(parent.children.first!.taxonId == "childTaxon")
    }
    
    @Test("Observation without location")
    func testAddObservationWithoutLocation() throws {
        // Given
        let store = ObservationStore()
        
        // When
        store.addObservation("testTaxon", location: nil)
        
        // Then
        #expect(store.observations.count == 1)
        let observation = store.observations.first!
        #expect(observation.taxonId == "testTaxon")
        #expect(observation.location == nil)
    }
}
