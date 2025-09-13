import Foundation
import Testing
@testable import BirdCountCore

struct DateRangeStoreTests {
    @Test
    func persistsAndLoads() throws {
        let store = DateRangeStore()
        let original = store.dateRange
        let newRange = DateRange(
            begin: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            end: Date()
        )
        store.update(newRange)
        let loaded = DateRangeStore().dateRange
        #expect(loaded == newRange)
        store.update(original) // restore
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
