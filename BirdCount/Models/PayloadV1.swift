import Foundation

/// Data structure for syncing observations between devices via MultipeerConnectivity.
/// Version 1 of the sync payload format.
public struct PayloadV1: Codable {
    public let schemaVersion: Int
    public let appVersion: String
    public let senderDisplayName: String
    public let rangeStart: Date
    public let rangeEnd: Date
    public let observations: [ObservationRecordDTO]
    
    public init(
        schemaVersion: Int = 1,
        appVersion: String,
        senderDisplayName: String,
        rangeStart: Date,
        rangeEnd: Date,
        observations: [ObservationRecordDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.senderDisplayName = senderDisplayName
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.observations = observations
    }
}
