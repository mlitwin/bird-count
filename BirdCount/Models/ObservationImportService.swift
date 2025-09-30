import Foundation

/// Service for importing observation data from sync operations.
/// Handles deduplication, parent-child relationship reconstruction, and atomic imports.
public class ObservationImportService {
    
    /// Import observations from a sync payload into the observation store.
    /// - Parameter payload: The PayloadV1 containing observations to import
    /// - Parameter into: The observation store to import into
    /// - Throws: ImportError for various failure conditions
    public static func importFromSync(_ payload: PayloadV1, into store: ObservationStore) throws {
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
        
        // Build complete records with children
        var recordsToImport: [ObservationRecord] = []
        
        for parentDTO in parentRecords {
            // Skip if this record already exists (deduplicate by UUID)
            if store.findRecord(by: parentDTO.id) != nil {
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
        
        // Handle orphaned children (children whose parents weren't in the payload or were duplicates)
        var orphanedChildren: [ObservationRecordDTO] = []
        for child in childRecords {
            guard let parentId = child.parentId else { continue }
            
            // Skip if this child already exists
            if store.findRecord(by: child.id) != nil {
                continue
            }
            
            // Skip if parent is being imported in this batch (already handled above)
            if recordsToImport.contains(where: { $0.id == parentId }) {
                continue
            }
            
            // Check if parent exists in store only (not being imported)
            if store.findRecord(by: parentId) != nil {
                // Try to attach to existing parent in store
                if store.addChildObservation(
                    parentId: parentId,
                    taxonId: child.taxonId,
                    begin: child.begin,
                    end: child.end,
                    count: child.count,
                    location: child.location,
                    observer: child.observer
                ) {
                    // Successfully attached to existing parent
                    continue
                }
            }
            
            // Parent doesn't exist or attachment failed, skip this child
            continue
        }
        
        // Import the parent records (this triggers rebuild automatically)
        store.importObservations(recordsToImport)
        
        // Attach orphaned children to newly imported parents (if any)
        for child in orphanedChildren {
            guard let parentId = child.parentId else { continue }
            store.addChildObservation(
                parentId: parentId,
                taxonId: child.taxonId,
                begin: child.begin,
                end: child.end,
                count: child.count,
                location: child.location,
                observer: child.observer
            )
        }
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

// MARK: - ObservationStore Extension
extension ObservationStore {
    /// Public access to rebuildDerived for sync operations
    public func rebuildDerivedPublic() {
        // Force a rebuild by modifying the observations array
        let currentObservations = observations
        observations = currentObservations
    }
}
