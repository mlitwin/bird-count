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

    // MARK: - Observation number HWM tests

    @Test func hwmServerAdvancesBothHWMs() {
        let store = ObservationStore(testing: true)
        store.advanceServerSyncedHWM(to: 50)
        #expect(store.serverSyncedHWM == 50)
        #expect(store.localObservationNumberMax == 50)
        // Must not regress below the current value
        store.advanceServerSyncedHWM(to: 30)
        #expect(store.serverSyncedHWM == 50)
        #expect(store.localObservationNumberMax == 50)
        store.advanceServerSyncedHWM(to: 100)
        #expect(store.serverSyncedHWM == 100)
        #expect(store.localObservationNumberMax == 100)
    }

    @Test func hwmP2PAdvancesLocalMaxOnly() {
        let store = ObservationStore(testing: true)
        store.advanceServerSyncedHWM(to: 50)
        store.advanceLocalObservationNumberMax(to: 75)
        #expect(store.localObservationNumberMax == 75)
        #expect(store.serverSyncedHWM == 50) // server HWM must not move on P2P receipt
    }

    @Test func applyServerObservationNumbersSetsInPlace() {
        let store = ObservationStore(testing: true)
        store.addObservation("amecro", count: 1)
        let id = store.observations.first!.id

        store.applyServerObservationNumbers([(id: id, number: 42)])

        #expect(store.findRecord(by: id)?.data.observationNumber == 42)
        #expect(store.localObservationNumberMax == 42)
        // The applied path stamps numbers from the push response; it must NOT
        // advance serverSyncedHWM (only the ordered pull stream does that).
        #expect(store.serverSyncedHWM == 0)
    }

    @Test func hwmPersistsAcrossReload() throws {
        let suiteName = "hwm-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store1 = ObservationStore(testing: false, defaults: defaults)
        store1.advanceServerSyncedHWM(to: 77)
        store1.advanceLocalObservationNumberMax(to: 99)

        let store2 = ObservationStore(testing: false, defaults: defaults)
        #expect(store2.serverSyncedHWM == 77)
        #expect(store2.localObservationNumberMax == 99)
    }
}
