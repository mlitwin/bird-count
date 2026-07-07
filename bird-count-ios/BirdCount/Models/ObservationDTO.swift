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
    /// Conflict resolution timestamp (whole-record last-writer-wins; in practice
    /// only the location backfill ever overwrites). On the wire this is integer
    /// milliseconds since epoch (see bird-count-schema/schemas/observation.schema.json),
    /// unlike the other dates which are ISO8601 strings.
    public var updatedAt: Date

    public init(id: UUID, parentId: UUID? = nil, taxonId: String, begin: Date, end: Date, count: Int, location: ObservationLocation? = nil, observer: String = "", status: ObservationStatus = .completed, updatedAt: Date? = nil) {
        self.id = id
        self.parentId = parentId
        self.taxonId = taxonId
        self.begin = begin
        self.end = end
        self.count = count
        self.location = location
        self.observer = observer
        self.status = status
        self.updatedAt = updatedAt ?? end
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
        // v1 records have no updatedAt; backfill with `end` (the same rule the
        // backend applies, so all devices converge on identical timestamps).
        if let ms = try container.decodeIfPresent(Int64.self, forKey: .updatedAt) {
            updatedAt = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        } else {
            updatedAt = end
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(parentId, forKey: .parentId)
        try container.encode(taxonId, forKey: .taxonId)
        try container.encode(begin, forKey: .begin)
        try container.encode(end, forKey: .end)
        try container.encode(count, forKey: .count)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(observer, forKey: .observer)
        try container.encode(status, forKey: .status)
        try container.encode(Int64((updatedAt.timeIntervalSince1970 * 1000).rounded()), forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, parentId, taxonId, begin, end, count, location, observer, status, updatedAt
    }
}
