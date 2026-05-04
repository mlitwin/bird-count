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
        // Validate schema version
        guard payload.schemaVersion == 1 else {
            throw ImportError.unsupportedSchemaVersion(payload.schemaVersion)
        }
        
        // Group DTOs by parentId for reconstruction
        let parentRecords = payload.observations.filter { $0.parentId == nil }
        let childRecords = payload.observations.filter { $0.parentId != nil }
        
        // Create a map of childRecords by parentId for efficient lookup
        var childrenByParent: [UUID: [ObservationRecordDTO]] = [:]
        for child in childRecords {
            guard let parentId = child.parentId else { continue }
            childrenByParent[parentId, default: []].append(child)
        }
        
        // Build complete records with children and track statistics
        var recordsToImport: [ObservationRecord] = []
        var duplicatesSkipped = 0
        
        for parentDTO in parentRecords {
            // Skip if this record already exists (deduplicate by UUID)
            if store.findRecord(by: parentDTO.id) != nil {
                duplicatesSkipped += 1
                continue
            }
            
            // Create the parent record
            var parentRecord = ObservationRecord(
                id: parentDTO.id,
                taxonId: parentDTO.taxonId,
                begin: parentDTO.begin,
                end: parentDTO.end,
                count: parentDTO.count,
                location: parentDTO.location,
                observer: parentDTO.observer
            )
            
            // Add children if any exist
            if let children = childrenByParent[parentDTO.id] {
                for childDTO in children {
                    // Skip if this child record already exists
                    if store.findRecord(by: childDTO.id) != nil {
                        continue
                    }
                    
                    let childRecord = ObservationRecord(
                        id: childDTO.id,
                        taxonId: childDTO.taxonId,
                        begin: childDTO.begin,
                        end: childDTO.end,
                        count: childDTO.count,
                        location: childDTO.location,
                        observer: childDTO.observer
                    )
                    parentRecord.addChild(childRecord)
                }
            }
            
            recordsToImport.append(parentRecord)
        }
        
        // Attach children whose parent already exists in the store (not being imported in this batch).
        for child in childRecords {
            guard let parentId = child.parentId else { continue }
            guard store.findRecord(by: child.id) == nil else { continue }
            guard !recordsToImport.contains(where: { $0.id == parentId }) else { continue }
            _ = store.addChildObservation(
                parentId: parentId,
                taxonId: child.taxonId,
                begin: child.begin,
                end: child.end,
                count: child.count,
                location: child.location,
                observer: child.observer
            )
        }

        // Import the parent records (this triggers rebuild automatically)
        store.importObservations(recordsToImport)

        // Calculate statistics
        let totalProcessed = payload.observations.count
        let newRecordsImported = recordsToImport.count
        
        return ImportStatistics(
            totalRecordsProcessed: totalProcessed,
            newRecordsImported: newRecordsImported,
            duplicatesSkipped: duplicatesSkipped
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

