import Foundation
import Observation

@Observable
final class DateRangeStore {

    private let userDefaultsKey = "dateRange"
    private let presetKey = "dateRangePreset"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var dateRange: DateRange {
        didSet { persist() }
    }
    public var dateRangePreset: DateRangePreset {
        didSet { persist() }
    }

    init() {
        // Restore range and preset from UserDefaults, or use defaults
        let storedRange = DateRangeStore.loadFromDefaults()
        let storedPreset = DateRangeStore.loadPresetFromDefaults()
        let initialRange: DateRange
        let initialPreset: DateRangePreset

        if let range = storedRange {
            initialRange = range
        } else {
            initialRange = DateRange.defaultRange()
        }

        if let preset = storedPreset {
            initialPreset = preset
        } else {
            // Infer preset from range if possible
            initialPreset = DateRangeStore.inferPreset(for: initialRange)
        }

        if initialPreset == .today {
            let now = Date()
            let cal = Calendar.current
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
            self.dateRange = DateRange(begin: start, end: end)
        } else {
            self.dateRange = initialRange
        }
        self.dateRangePreset = initialPreset
    }

    init(testing: Bool) {
        if testing {
            // Use default values for testing, don't load from UserDefaults
            self.dateRange = DateRange.defaultRange()
            self.dateRangePreset = .custom
        } else {
            // Standard initialization (delegate to main init)
            let storedRange = DateRangeStore.loadFromDefaults()
            let storedPreset = DateRangeStore.loadPresetFromDefaults()
            let initialRange: DateRange
            let initialPreset: DateRangePreset

            if let range = storedRange {
                initialRange = range
            } else {
                initialRange = DateRange.defaultRange()
            }

            if let preset = storedPreset {
                initialPreset = preset
            } else {
                // Infer preset from range if possible
                initialPreset = DateRangeStore.inferPreset(for: initialRange)
            }

            if initialPreset == .today {
                let now = Date()
                let cal = Calendar.current
                let start = cal.startOfDay(for: now)
                let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
                self.dateRange = DateRange(begin: start, end: end)
            } else {
                self.dateRange = initialRange
            }
            self.dateRangePreset = initialPreset
        }
    }

    func update(_ newRange: DateRange) {
        dateRange = newRange
    }

    func reset() {
        dateRange = DateRange.defaultRange()
    }


    private func persist() {
        if let data = try? encoder.encode(dateRange) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
        UserDefaults.standard.set(dateRangePreset.rawValue, forKey: presetKey)
    }

    private static func loadPresetFromDefaults() -> DateRangePreset? {
        guard let raw = UserDefaults.standard.string(forKey: "dateRangePreset") else { return nil }
        return DateRangePreset(rawValue: raw)
    }

    private static func inferPreset(for range: DateRange) -> DateRangePreset {
        let now = Date()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let todayEnd = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now
        if range.begin == todayStart && range.end == todayEnd {
            return .today
        }
        // Add more inference logic if needed
        return .custom
    }

    private static func loadFromDefaults() -> DateRange? {
        guard let data = UserDefaults.standard.data(forKey: "dateRange") else { return nil }
        return try? JSONDecoder().decode(DateRange.self, from: data)
    }


    // Set preset and update date range accordingly, but avoid recursion
    func setPreset(_ preset: DateRangePreset) {
        if dateRangePreset == preset { return }
        self.dateRangePreset = preset
        if preset != .custom {
            applyPreset(preset)
        }
        // For .custom, do not change dateRange
    }


    func applyPreset(_ preset: DateRangePreset) {
        let now = Date()
        switch preset {
        case .lastHour:
            dateRange = DateRange(
                begin: Calendar.current.date(byAdding: .hour, value: -1, to: now) ?? now,
                end: now
            )
        case .today:
            let cal = Calendar.current
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
            dateRange = DateRange(begin: start, end: end)
        case .last7Days:
            dateRange = DateRange(
                begin: Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now,
                end: now
            )
        case .all:
            dateRange = DateRange(begin: .distantPast, end: now)
        case .custom:
            // Do not change dateRange
            break
        }
    }

    func shiftRangeByDays(_ days: Int) {
        let cal = Calendar.current
        let newStart = cal.date(byAdding: .day, value: days, to: dateRange.begin) ?? dateRange.begin
        let newEnd = cal.date(byAdding: .day, value: days, to: dateRange.end) ?? dateRange.end
        dateRange = DateRange(begin: newStart, end: max(newStart, newEnd))
        dateRangePreset = .custom
    }
}
