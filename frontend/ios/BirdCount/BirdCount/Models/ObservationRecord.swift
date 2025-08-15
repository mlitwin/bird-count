import Foundation

/// A single bird observation event.
/// Stored as an immutable record with the species (taxonId) and capture timestamp.
/// Named ObservationRecord to avoid conflicting with Apple's Observation module.
public struct ObservationRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let taxonId: String
    public let timestamp: Date

    public init(id: UUID = UUID(), taxonId: String, timestamp: Date = Date()) {
        self.id = id
        self.taxonId = taxonId
        self.timestamp = timestamp
    }
}
