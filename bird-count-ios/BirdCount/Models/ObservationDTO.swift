import Foundation

/// Status of an observation record - pending location resolution or completed
public enum ObservationStatus: String, Codable, CaseIterable {
    case pending = "pending"
    case completed = "completed"
}

/// A plain data struct for serialization, containing only the core fields (no children).
public struct ObservationRecordDTO: Identifiable, Codable, Equatable {
    public let id: UUID
    public var parentId: UUID?
    public let taxonId: String
    public let begin: Date
    public let end: Date
    public var count: Int
    public var location: ObservationLocation?
    public let observer: String
    public var status: ObservationStatus

    public init(id: UUID, parentId: UUID? = nil, taxonId: String, begin: Date, end: Date, count: Int, location: ObservationLocation? = nil, observer: String = "", status: ObservationStatus = .completed) {
        self.id = id
        self.parentId = parentId
        self.taxonId = taxonId
        self.begin = begin
        self.end = end
        self.count = count
        self.location = location
        self.observer = observer
        self.status = status
    }
    
    // Custom coding to handle backwards compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
        taxonId = try container.decode(String.self, forKey: .taxonId)
        begin = try container.decode(Date.self, forKey: .begin)
        end = try container.decode(Date.self, forKey: .end)
        count = try container.decode(Int.self, forKey: .count)
        location = try container.decodeIfPresent(ObservationLocation.self, forKey: .location)
        observer = try container.decodeIfPresent(String.self, forKey: .observer) ?? ""
        status = try container.decodeIfPresent(ObservationStatus.self, forKey: .status) ?? .completed
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, parentId, taxonId, begin, end, count, location, observer, status
    }
}
