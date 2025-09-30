import Foundation

/// Service for importing observations from JSON export data.
/// Converts JSON export format to internal format and uses ObservationImportService.
public class ObservationJSONImportService {
    
    /// Import observations from JSON export data into the observation store.
    /// - Parameter jsonData: The JSON data string from export
    /// - Parameter into: The observation store to import into
    /// - Throws: ImportError for various failure conditions
    public static func importFromJSON(_ jsonData: String, into store: ObservationStore) throws {
        // Parse JSON
        guard let data = jsonData.data(using: .utf8) else {
            throw ImportError.invalidJSONFormat("Unable to convert string to data")
        }
        
        let jsonObject: [String: Any]
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw ImportError.invalidJSONFormat("Invalid JSON: \(error.localizedDescription)")
        }
        
        // Extract observations array
        guard let observationsArray = jsonObject["observations"] as? [[String: Any]] else {
            throw ImportError.invalidJSONFormat("Missing or invalid 'observations' array")
        }
        
        // Convert JSON observations to DTOs (handle flattened format only)
        var observationDTOs: [ObservationRecordDTO] = []
        let dateFormatter = ISO8601DateFormatter()
        
        for observationJSON in observationsArray {
            do {
                let dto = try convertJSONToDTO(observationJSON, dateFormatter: dateFormatter)
                observationDTOs.append(dto)
            } catch {
                // Skip invalid records but continue processing
                continue
            }
        }
        
        // Create a PayloadV1 for the existing import service
        let payload = PayloadV1(
            schemaVersion: 1,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            senderDisplayName: "JSON Import",
            rangeStart: Date.distantPast,
            rangeEnd: Date.distantFuture,
            observations: observationDTOs
        )
        
        // Use existing import service
        try ObservationImportService.importFromSync(payload, into: store)
    }
    
    /// Convert a JSON observation object to ObservationRecordDTO
    private static func convertJSONToDTO(_ json: [String: Any], dateFormatter: ISO8601DateFormatter) throws -> ObservationRecordDTO {
        // Extract required fields
        guard let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let taxonId = json["taxonId"] as? String,
              let beginString = json["begin"] as? String,
              let endString = json["end"] as? String,
              let count = json["count"] as? Int else {
            throw ImportError.invalidRecord("Missing required fields in observation record")
        }
        
        // Convert dates with explicit error checking
        guard let begin = dateFormatter.date(from: beginString) else {
            throw ImportError.invalidRecord("Invalid begin date format: '\(beginString)'")
        }
        
        guard let end = dateFormatter.date(from: endString) else {
            throw ImportError.invalidRecord("Invalid end date format: '\(endString)'")
        }
        
        // Extract optional parent ID
        var parentId: UUID? = nil
        if let parentIdString = json["parentId"] as? String {
            parentId = UUID(uuidString: parentIdString)
        }
        
        // Extract optional location
        var location: ObservationLocation? = nil
        if let locationJSON = json["location"] as? [String: Any] {
            location = try parseLocation(locationJSON, dateFormatter: dateFormatter)
        }
        
        // Extract optional observer
        let observer = json["observer"] as? String ?? ""
        
        return ObservationRecordDTO(
            id: id,
            parentId: parentId,
            taxonId: taxonId,
            begin: begin,
            end: end,
            count: count,
            location: location,
            observer: observer,
            status: .completed
        )
    }
    
    /// Parse location data from JSON
    private static func parseLocation(_ locationJSON: [String: Any], dateFormatter: ISO8601DateFormatter) throws -> ObservationLocation {
        guard let latitude = locationJSON["latitude"] as? Double,
              let longitude = locationJSON["longitude"] as? Double,
              let horizontalAccuracy = locationJSON["horizontalAccuracy"] as? Double,
              let timestampString = locationJSON["timestamp"] as? String else {
            throw ImportError.invalidRecord("Invalid location data: missing required fields")
        }
        
        // Convert timestamp with explicit error checking
        guard let timestamp = dateFormatter.date(from: timestampString) else {
            throw ImportError.invalidRecord("Invalid location timestamp format: '\(timestampString)'")
        }
        
        // Optional fields
        let altitude = locationJSON["altitude"] as? Double
        let verticalAccuracy = locationJSON["verticalAccuracy"] as? Double
        let name = locationJSON["name"] as? String
        let notes = locationJSON["notes"] as? String
        
        return ObservationLocation(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            timestamp: timestamp,
            altitude: altitude,
            verticalAccuracy: verticalAccuracy,
            name: name,
            notes: notes
        )
    }
    
    /// Errors that can occur during JSON import
    public enum ImportError: Error, LocalizedError {
        case invalidJSONFormat(String)
        case invalidRecord(String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidJSONFormat(let message):
                return "Invalid JSON format: \(message)"
            case .invalidRecord(let message):
                return "Invalid record data: \(message)"
            }
        }
    }
}