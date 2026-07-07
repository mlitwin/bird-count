import Foundation

/// Statistics about an import operation
public struct ImportStatistics {
    public let totalRecordsProcessed: Int
    public let newRecordsImported: Int
    public let duplicatesSkipped: Int
    
    public init(totalRecordsProcessed: Int, newRecordsImported: Int, duplicatesSkipped: Int) {
        self.totalRecordsProcessed = totalRecordsProcessed
        self.newRecordsImported = newRecordsImported
        self.duplicatesSkipped = duplicatesSkipped
    }
}

/// Service for importing observation data from sync operations.
/// Handles deduplication, parent-child relationship reconstruction, and atomic imports.
public class ObservationImportService {
    
    /// Import observations from a sync payload into the observation store.
    /// - Parameter payload: The PayloadV1 containing observations to import
    /// - Parameter into: The observation store to import into
    /// - Returns: ImportStatistics with details about the import operation
    /// - Throws: ImportError for various failure conditions
    public static func importFromSync(_ payload: PayloadV1, into store: ObservationStore) throws -> ImportStatistics {
        // v1 payloads are accepted: the DTO decoder backfills updatedAt = end,
        // the same rule the backend applies, so all devices converge.
        guard payload.schemaVersion == 1 || payload.schemaVersion == 2 else {
            throw ImportError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        // Put-if-absent + last-writer-wins on updatedAt (covers the location
        // backfill overwrite). markDirty so P2P-received records flow up to
        // the cloud on the next cloud sync.
        let stats = store.mergeDTOs(payload.observations, markDirty: true)

        return ImportStatistics(
            totalRecordsProcessed: payload.observations.count,
            newRecordsImported: stats.imported + stats.updated,
            duplicatesSkipped: stats.duplicatesSkipped
        )
    }
    
    public enum ImportError: Error, Equatable, LocalizedError {
        case unsupportedSchemaVersion(Int)
        case invalidPayload
        
        public var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let version):
                return "Unsupported sync format version: \(version)"
            case .invalidPayload:
                return "Invalid sync data received"
            }
        }
    }
}

