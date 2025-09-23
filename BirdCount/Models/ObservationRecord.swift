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
    public var location: ObservationLocation? { data.location }
    public var observer: String { data.observer }

    // MARK: Initializers
    public init(id: UUID = UUID(), taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil, observer: String = "") {
        let beginTime = begin
        self.data = ObservationRecordDTO(id: id, parentId: nil, taxonId: taxonId, begin: beginTime, end: end ?? beginTime, count: count, location: location, observer: observer)
        self.children = []
    }

    public init(parent: inout ObservationRecord, id: UUID = UUID(), taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil, observer: String = "") {
        let beginTime = begin
        self.data = ObservationRecordDTO(id: id, parentId: parent.id, taxonId: taxonId, begin: beginTime, end: end ?? beginTime, count: count, location: location, observer: observer)
        self.children = []
        parent.children.append(self)
    }

    // MARK: Mutating helpers
    public mutating func addChild(_ child: ObservationRecord) {
        var adjusted = child
        adjusted.parentId = self.id
        children.append(adjusted)
    }
}
