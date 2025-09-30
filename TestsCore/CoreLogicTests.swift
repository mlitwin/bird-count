import Foundation
import Testing
@testable import BirdCountCore

struct CoreLogicTests {
    @Test
    func observationStoreBasicCounts() {
        let store = ObservationStore(testing: true)
        store.clearAll()
        store.addObservation("amecro", count: 2)
        store.addObservation("norbla", count: 1)
        #expect(store.count(for: "amecro") == 2)
        #expect(store.totalIndividuals == 3)
        #expect(store.totalSpeciesObserved == 2)
    }

    @Test
    func observationRecordHierarchyAndCoding() throws {
        var parent = ObservationRecord(taxonId: "amecro", count: 2)
        let child = ObservationRecord(parent: &parent, taxonId: "norbla", count: 1)

        #expect(parent.children.count == 1)
        #expect(parent.children.first?.id == child.id)
        #expect(parent.children.first?.parentId == parent.id)
        #expect(child.parentId == parent.id)

        // Round-trip encode/decode and ensure parentId and children persist
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let data = try enc.encode(parent)
        let decoded = try dec.decode(ObservationRecord.self, from: data)
        #expect(decoded.children.count == 1)
        #expect(decoded.children.first?.parentId == decoded.id)
    }

    @Test
    func observationRecordTotalCount() {
        // Test simple record without children
        let simple = ObservationRecord(taxonId: "amecro", count: 3)
        #expect(simple.totalCount == 3)
        
        // Test parent with one child
        var parent = ObservationRecord(taxonId: "amecro", count: 2)
        let child1 = ObservationRecord(parent: &parent, taxonId: "norbla", count: 4)
        #expect(parent.totalCount == 6) // 2 + 4
        #expect(child1.totalCount == 4) // just the child's count
        
        // Test parent with multiple children
        let _ = ObservationRecord(parent: &parent, taxonId: "cangoo", count: 1)
        #expect(parent.totalCount == 7) // 2 + 4 + 1
        
        // Test nested children (grandchildren) - need var for child3 to add grandchild
        var child3 = ObservationRecord(parent: &parent, taxonId: "blujay", count: 3)
        let grandchild = ObservationRecord(parent: &child3, taxonId: "redwin", count: 2)
        
        // Update the parent's children array with the modified child3 that now has a grandchild
        if let index = parent.children.firstIndex(where: { $0.id == child3.id }) {
            parent.children[index] = child3
        }
        
        #expect(parent.totalCount == 12) // 2 + 4 + 1 + 3 + 2
        #expect(child3.totalCount == 5) // 3 + 2
        #expect(grandchild.totalCount == 2) // just the grandchild's count
    }

    @Test
    func observationStoreCountsIncludeChildren() {
        let store = ObservationStore(testing: true)
        store.clearAll()

        // Create a parent with count 2 and a child with count 3 of the same species
        var parent = ObservationRecord(taxonId: "amecro", count: 2)
        _ = ObservationRecord(parent: &parent, taxonId: "amecro", count: 3)

        // Persist these two as a single top-level record with nested child
        // Direct array mutation to simulate a loaded complex observation
        // Note: ObservationStore triggers rebuildDerived on set
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode([parent])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode([ObservationRecord].self, from: data)

        // Replace store.observations with hierarchical data
        // Since observations is private(set), use reflection-free path: assign via persist/load
        // We can't set directly; instead, append via addObservation for parent count and manually verify via cache by rebuilding
        // Simpler: build a local cache and assert, then also verify store via manual injection through persistence key
        var cache = ObservationStoreCache()
        cache.rebuild(from: decoded)
        #expect(cache.count(for: "amecro") == 5)
        #expect(cache.totalIndividuals == 5)
        #expect(cache.totalSpeciesObserved == 1)

        // Mixed species with nested children
        var p2 = ObservationRecord(taxonId: "norbla", count: 1)
        _ = ObservationRecord(parent: &p2, taxonId: "cangoo", count: 4)
        cache.rebuild(from: [parent, p2])
        #expect(cache.count(for: "amecro") == 5)
        #expect(cache.count(for: "norbla") == 1)
        #expect(cache.count(for: "cangoo") == 4)
        #expect(cache.totalIndividuals == 10)
        #expect(cache.totalSpeciesObserved == 3)
    }

    @Test
    func storeAddChildObservationAPITest() {
        let store = ObservationStore(testing: true)
        store.clearAll()

        // Create a top-level parent via normal API
        store.addObservation("amecro", count: 2)
        #expect(store.totalIndividuals == 2)

    // Find the parent id (tests have @testable access to internal getter)
    #expect(store.observations.count == 1)
    let pid = store.observations[0].id

        // Add a child of the same species and verify totals increase
        let attached = store.addChildObservation(parentId: pid, taxonId: "amecro", count: 3)
        #expect(attached)
        #expect(store.count(for: "amecro") == 5)
        #expect(store.totalIndividuals == 5)

    // Add a nested child under the first child (use helper to get child id)
    #expect(store.observations.first?.children.count == 1)
    let firstChild = store.observations.first!.children.first!
    let childId = store.findRecord(by: firstChild.id)!.id

        let attached2 = store.addChildObservation(parentId: childId, taxonId: "norbla", count: 4)
        #expect(attached2)
        #expect(store.count(for: "amecro") == 5)
        #expect(store.count(for: "norbla") == 4)
        #expect(store.totalIndividuals == 9)
        #expect(store.totalSpeciesObserved == 2)
    }
}
