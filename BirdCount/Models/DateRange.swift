import Foundation

public struct DateRange: Codable, Equatable {
    public var begin: Date
    public var end: Date

    public static func defaultRange() -> DateRange {
        let now = Date()
        // Default: today only
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        return DateRange(begin: startOfDay, end: endOfDay)
    }
    
    public init(begin: Date, end: Date) {
        self.begin = begin
        self.end = end
    }
}
