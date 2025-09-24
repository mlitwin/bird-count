import Foundation
import Testing
@testable import BirdCountCore

struct DateRangeStoreTests {
    @Test
    func persistsAndLoads() throws {
        let store = DateRangeStore()
        let original = store.dateRange
        
        // Use fixed dates to avoid flaky behavior
        let fixedEndDate = Date(timeIntervalSince1970: 1695312000) // Fixed timestamp
        let fixedBeginDate = Date(timeIntervalSince1970: 1695312000 - 2 * 24 * 60 * 60) // 2 days earlier
        
        let newRange = DateRange(begin: fixedBeginDate, end: fixedEndDate)
        store.update(newRange)
        
        // Verify the store has the updated range
        #expect(store.dateRange == newRange)
        
        // Test persistence by creating a new store instance
        // (This tests if the data was actually persisted to storage)
        let newStore = DateRangeStore()
        #expect(newStore.dateRange == newRange)
        
        // Restore original range
        store.update(original)
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
