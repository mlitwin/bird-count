import Foundation

/// A single bird observation event.
/// Stored as an immutable record with the species (taxonId) and capture timestamp.
/// Named ObservationRecord to avoid conflicting with Apple's Observation module.
public struct ObservationRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let taxonId: String
    public let timestamp: Date
    public var count: Int

    public init(id: UUID = UUID(), taxonId: String, timestamp: Date = Date(), count: Int = 1) {
        self.id = id
        self.taxonId = taxonId
        self.timestamp = timestamp
        self.count = max(0, count)
    }
}
