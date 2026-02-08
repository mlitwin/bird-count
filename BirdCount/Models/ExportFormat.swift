 import Foundation

/// Available export formats for observation data
enum ExportFormat: String, CaseIterable, Identifiable {
    case summary = "summary"
    case json = "json"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .summary:
            return "Summary"
        case .json:
            return "JSON"
        }
    }
}
