import Foundation

/// A single bird observation event.
/// Stored as an immutable record with the species (taxonId) and capture timestamp.
/// Named ObservationRecord to avoid conflicting with Apple's Observation module.
public struct ObservationRecord: Identifiable, Codable, Equatable {
    public var data: ObservationRecordDTO
    public var children: [ObservationRecord] = []

    // MARK: Computed accessors
    public var id: UUID { data.id }
    public var parentId: UUID? {
        get { data.parentId }
        set { data.parentId = newValue }
    }
    public var taxonId: String { data.taxonId }
    public var begin: Date { data.begin }
    public var end: Date { data.end }
    public var count: Int {
        get { data.count }
        set { data.count = newValue }
    }
    
    /// Total count including this record and all children recursively
    public var totalCount: Int {
        return count + children.reduce(0) { $0 + $1.totalCount }
    }
    
    public var location: ObservationLocation? {
        get { data.location }
        set { data.location = newValue }
    }
    public var observer: String { data.observer }
    public var status: ObservationStatus {
        get { data.status }
        set { data.status = newValue }
    }
    public var updatedAt: Date { data.updatedAt }

    // MARK: Initializers
    /// Wrap an incoming DTO, preserving its identity and timestamps exactly
    /// (sync/merge must never mint new UUIDs for transferred records).
    public init(data: ObservationRecordDTO) {
        self.data = data
        self.children = []
    }

    public init(id: UUID = UUID(), taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil, observer: String = "", status: ObservationStatus = .completed) {
        let beginTime = begin
        self.data = ObservationRecordDTO(id: id, parentId: nil, taxonId: taxonId, begin: beginTime, end: end ?? beginTime, count: count, location: location, observer: observer, status: status)
        self.children = []
    }

    public init(parent: inout ObservationRecord, id: UUID = UUID(), taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil, observer: String = "", status: ObservationStatus = .completed) {
        let beginTime = begin
        self.data = ObservationRecordDTO(id: id, parentId: parent.id, taxonId: taxonId, begin: beginTime, end: end ?? beginTime, count: count, location: location, observer: observer, status: status)
        self.children = []
        parent.children.append(self)
    }

    // MARK: Mutating helpers
    public mutating func addChild(_ child: ObservationRecord) {
        var adjusted = child
        adjusted.parentId = self.id
        children.append(adjusted)
    }
    
    /// Update the observation with location and mark as completed.
    /// This is the one post-creation mutation; it bumps updatedAt so the new
    /// location wins last-writer-wins merges on other devices.
    public mutating func updateWithLocation(_ location: ObservationLocation?) {
        data.location = location
        data.status = .completed
        data.updatedAt = Date()
    }
}

// MARK: - Equatable
extension ObservationRecord {
    public static func == (lhs: ObservationRecord, rhs: ObservationRecord) -> Bool {
        return lhs.data == rhs.data && lhs.children == rhs.children
    }
}
