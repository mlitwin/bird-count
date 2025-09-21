import Foundation

/// A plain data struct for serialization, containing only the core fields (no children).
public struct ObservationRecordDTO: Identifiable, Codable, Equatable {
    public let id: UUID
    public var parentId: UUID?
    public let taxonId: String
    public let begin: Date
    public let end: Date
    public var count: Int
    public let location: ObservationLocation?

    public init(id: UUID, parentId: UUID? = nil, taxonId: String, begin: Date, end: Date, count: Int, location: ObservationLocation? = nil) {
        self.id = id
        self.parentId = parentId
        self.taxonId = taxonId
        self.begin = begin
        self.end = end
        self.count = count
        self.location = location
    }
}
