import Foundation
import CoreLocation

/// Represents a location where an observation was recorded, sourced from Core Location services
public struct ObservationLocation: Codable, Equatable, Hashable {
    /// Latitude in degrees
    public let latitude: Double
    
    /// Longitude in degrees
    public let longitude: Double
    
    /// Accuracy of the location measurement in meters (horizontal)
    public let horizontalAccuracy: Double
    
    /// Timestamp when the location was recorded
    public let timestamp: Date
    
    /// Optional altitude in meters above sea level
    public let altitude: Double?
    
    /// Optional accuracy of the altitude measurement in meters (vertical)
    public let verticalAccuracy: Double?
    
    /// Optional human-readable description of the location (e.g., "Central Park", "Home")
    public let name: String?
    
    /// Optional notes about the location context
    public let notes: String?
    
    // MARK: - Initializers
    
    /// Initialize with Core Location CLLocation object
    public init(from clLocation: CLLocation, name: String? = nil, notes: String? = nil) {
        self.latitude = clLocation.coordinate.latitude
        self.longitude = clLocation.coordinate.longitude
        self.horizontalAccuracy = clLocation.horizontalAccuracy
        self.timestamp = clLocation.timestamp
        
        // Only include altitude data if it's valid
        if clLocation.verticalAccuracy >= 0 {
            self.altitude = clLocation.altitude
            self.verticalAccuracy = clLocation.verticalAccuracy
        } else {
            self.altitude = nil
            self.verticalAccuracy = nil
        }
        
        self.name = name
        self.notes = notes
    }
    
    /// Initialize with explicit coordinates
    public init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double = 0.0,
        timestamp: Date = Date(),
        altitude: Double? = nil,
        verticalAccuracy: Double? = nil,
        name: String? = nil,
        notes: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.name = name
        self.notes = notes
    }
    
    // MARK: - Computed Properties
    
    /// Returns a CLLocationCoordinate2D for use with MapKit/Core Location
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// Returns a CLLocation object for distance calculations
    public var clLocation: CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude ?? 0.0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy ?? -1.0,
            timestamp: timestamp
        )
    }
    
    /// Returns true if the location has valid coordinates
    public var isValid: Bool {
        CLLocationCoordinate2DIsValid(coordinate) && horizontalAccuracy >= 0
    }
    
    /// Returns a human-readable description of the location accuracy
    public var accuracyDescription: String {
        if horizontalAccuracy < 0 {
            return "Invalid"
        } else if horizontalAccuracy < 5 {
            return "Excellent"
        } else if horizontalAccuracy < 10 {
            return "Good"
        } else if horizontalAccuracy < 50 {
            return "Fair"
        } else {
            return "Poor"
        }
    }
    
    // MARK: - Methods
    
    /// Calculate distance to another location in meters
    public func distance(to other: ObservationLocation) -> Double {
        return clLocation.distance(from: other.clLocation)
    }
    
    /// Returns a formatted string representation of the coordinates
    public func formattedCoordinates() -> String {
        let latDirection = latitude >= 0 ? "N" : "S"
        let lonDirection = longitude >= 0 ? "E" : "W"
        
        return String(format: "%.6f°%@ %.6f°%@", 
                     abs(latitude), latDirection,
                     abs(longitude), lonDirection)
    }
    
    /// Returns a display name, falling back to coordinates if no name is set
    public var displayName: String {
        return name ?? formattedCoordinates()
    }
}

// MARK: - CustomStringConvertible
extension ObservationLocation: CustomStringConvertible {
    public var description: String {
        var components = [displayName]
        components.append("(\(accuracyDescription) accuracy)")
        
        if let notes = notes, !notes.isEmpty {
            components.append(notes)
        }
        
        return components.joined(separator: " ")
    }
}

// MARK: - Static Factory Methods
extension ObservationLocation {
    /// Create a location for testing or when actual location is unavailable
    public static func mock(
        name: String = "Mock Location",
        latitude: Double = 40.7831,
        longitude: Double = -73.9712
    ) -> ObservationLocation {
        ObservationLocation(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: 5.0,
            name: name
        )
    }
    
    /// Create a location representing "unknown" or unavailable location
    public static var unknown: ObservationLocation {
        ObservationLocation(
            latitude: 0.0,
            longitude: 0.0,
            horizontalAccuracy: -1.0,
            name: "Unknown Location"
        )
    }
}
