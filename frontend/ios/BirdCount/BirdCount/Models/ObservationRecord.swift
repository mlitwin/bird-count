import Foundation

/// A single bird observation event.
/// Stored as an immutable record with the species (taxonId) and capture timestamp.
/// Named ObservationRecord to avoid conflicting with Apple's Observation module.
public struct ObservationRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let taxonId: String
    // Use a time interval [begin, end]; default behavior is begin == end
    public let begin: Date
    public let end: Date
    public var count: Int

    public init(id: UUID = UUID(), taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) {
        self.id = id
        self.taxonId = taxonId
        self.begin = begin
        self.end = end ?? begin
        self.count = max(0, count)
    }
}
