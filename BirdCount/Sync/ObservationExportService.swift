import Foundation

/// Service for exporting observation data for sync operations.
/// Handles filtering records by date range and converting to sync payload format.
public class ObservationExportService {

    /// Compute a lightweight summary of what would be sent (without building the full payload).
    static func summaryForSync(in range: DateRange, from store: ObservationStore) -> SyncSendSummary {
        let filtered = filterRecords(from: store.observations, in: range)
        let flat = flattenToDTO(records: filtered)
        let speciesCount = Set(flat.map { $0.taxonId }).count
        return SyncSendSummary(
            observationCount: flat.count,
            speciesCount: speciesCount,
            dateRangeBegin: range.begin,
            dateRangeEnd: range.end
        )
    }

    /// Export observations for sync within the specified date range.
    /// - Parameter displayName: The sender's display name to embed in the payload.
    /// - Parameter range: The date range to filter observations.
    /// - Parameter from: The observation store to export from.
    public static func exportForSync(displayName: String, in range: DateRange, from store: ObservationStore) -> PayloadV1 {
        let filteredRecords = filterRecords(from: store.observations, in: range)
        let flattenedDTOs = flattenToDTO(records: filteredRecords)
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"

        return PayloadV1(
            schemaVersion: 1,
            appVersion: appVersion,
            senderDisplayName: displayName,
            rangeStart: range.begin,
            rangeEnd: range.end,
            observations: flattenedDTOs
        )
    }
    
    /// Filter observation records that overlap with the given date range.
    /// Uses the rule: record.end >= range.begin && record.begin <= range.end
    private static func filterRecords(from records: [ObservationRecord], in range: DateRange) -> [ObservationRecord] {
        return records.compactMap { record in
            if record.end >= range.begin && record.begin <= range.end {
                // Include this record, and filter its children recursively
                var filteredRecord = record
                filteredRecord.children = filterRecords(from: record.children, in: range)
                return filteredRecord
            }
            return nil
        }
    }
    
    /// Flatten parent and child records into a single list of DTOs.
    /// Children carry their parentId for reconstruction during import.
    private static func flattenToDTO(records: [ObservationRecord]) -> [ObservationRecordDTO] {
        var result: [ObservationRecordDTO] = []
        
        func addRecursively(_ record: ObservationRecord) {
            result.append(record.data)
            for child in record.children {
                addRecursively(child)
            }
        }
        
        for record in records {
            addRecursively(record)
        }
        
        return result
    }
}
