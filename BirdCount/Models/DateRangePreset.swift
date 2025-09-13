import Foundation

public enum DateRangePreset: String, CaseIterable, Identifiable, Codable {
    case lastHour = "Last Hour"
    case today = "Today"
    case last7Days = "7 Days"
    case all = "All"
    case custom = "Custom"
    public var id: String { rawValue }
}
