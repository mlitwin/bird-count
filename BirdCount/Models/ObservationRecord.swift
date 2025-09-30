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
    
    public var location: ObservationLocation? { data.location }
    public var observer: String { data.observer }
    public var status: ObservationStatus {
        get { data.status }
        set { data.status = newValue }
    }

    // MARK: Initializers
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
    
    /// Update the observation with location and mark as completed
    public mutating func updateWithLocation(_ location: ObservationLocation?) {
        data.location = location
        data.status = .completed
    }
}

// MARK: - Equatable
extension ObservationRecord {
    public static func == (lhs: ObservationRecord, rhs: ObservationRecord) -> Bool {
        return lhs.data == rhs.data && lhs.children == rhs.children
    }
}
