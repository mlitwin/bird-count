import Foundation
import Testing
@testable import BirdCountCore

struct DateRangeStoreTests {
    @Test
    func persistsAndLoads() throws {
        // Clear any existing preferences to ensure clean test
        UserDefaults.standard.removeObject(forKey: "dateRange")
        UserDefaults.standard.removeObject(forKey: "dateRangePreset")
        
        // Use testing initializer for predictable behavior
        let store = DateRangeStore(testing: true)
        
        // Use fixed dates to avoid flaky behavior
        let fixedEndDate = Date(timeIntervalSince1970: 1695312000) // Fixed timestamp
        let fixedBeginDate = Date(timeIntervalSince1970: 1695312000 - 2 * 24 * 60 * 60) // 2 days earlier
        
        let newRange = DateRange(begin: fixedBeginDate, end: fixedEndDate)
        store.update(newRange)
        // Set preset to custom so it doesn't get recalculated on load
        store.setPreset(.custom)
        
        // Verify the store has the updated range
        #expect(store.dateRange == newRange)
        
        // Test persistence by creating a new store instance that loads from UserDefaults
        // (This tests if the data was actually persisted to storage)
        let newStore = DateRangeStore(testing: false) // This one should load from UserDefaults
        #expect(newStore.dateRange == newRange)
        
        // Clean up - restore original range
        UserDefaults.standard.removeObject(forKey: "dateRange")
        UserDefaults.standard.removeObject(forKey: "dateRangePreset")
    }

    @Test
    func resetsToDefault() throws {
        let store = DateRangeStore()
        store.update(DateRange(
            begin: Calendar.current.date(byAdding: .day, value: -10, to: Date())!,
            end: Date()
        ))
        store.reset()
        let def = DateRange.defaultRange()
        #expect(store.dateRange.begin == def.begin)
        #expect(store.dateRange.end == def.end)
    }
}
