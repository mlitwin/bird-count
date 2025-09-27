import Foundation
import Testing
@testable import BirdCountCore

struct ObservationStoreTests {
    @Test
    func countsAggregate() throws {
        let store = ObservationStore(testing: true)
        store.clearAll()
        store.addObservation("amecro", count: 1)
        store.addObservation("amecro", count: 2)
        #expect(store.count(for: "amecro") == 3)
        #expect(store.totalIndividuals == 3)
        #expect(store.totalSpeciesObserved == 1)
    }
}
