import Foundation

struct DateRange: Codable, Equatable {
    var begin: Date
    var end: Date

    static func defaultRange() -> DateRange {
        let now = Date()
        // Default: today only
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        return DateRange(begin: startOfDay, end: endOfDay)
    }
}
