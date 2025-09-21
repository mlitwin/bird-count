import Foundation
import CoreLocation
import Observation

/// Location services manager that handles GPS permissions and location requests
/// Uses Swift Observation pattern for reactive updates across the app
@Observable
public final class LocationManager: NSObject {
    
    // MARK: - Published Properties
    
    /// Current authorization status for location services
    public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    /// Current location if available and authorized
    public private(set) var currentLocation: CLLocation?
    
    /// Current location as ObservationLocation if available and authorized
    public private(set) var currentObservationLocation: ObservationLocation?
    
    /// Whether location services are enabled on the device
    public private(set) var locationServicesEnabled: Bool = false
    
    /// Whether we're currently requesting a location update
    public private(set) var isRequestingLocation: Bool = false
    
    /// Last error encountered during location operations
    public private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private let locationManager = CLLocationManager()
    private var locationCompletionHandlers: [(Result<ObservationLocation, Error>) -> Void] = []
    private var hasRequestedInitialPermission = false
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationManager()
        updateLocationServicesStatus()
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Only update if moved 10+ meters
        
        // Update initial authorization status
        authorizationStatus = locationManager.authorizationStatus
    }
    
    private func updateLocationServicesStatus() {
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
    }
    
    // MARK: - Public Methods
    
    /// Request location permissions from the user
    /// This should be called when the user first tries to capture location
    public func requestLocationPermission() {
        guard locationServicesEnabled else {
            lastError = LocationError.servicesDisabled
            return
        }
        
        switch authorizationStatus {
        case .notDetermined:
            hasRequestedInitialPermission = true
            // Dispatch authorization request to avoid blocking main thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.locationManager.requestWhenInUseAuthorization()
            }
            
        case .denied, .restricted:
            lastError = LocationError.permissionDenied
            
        case .authorizedAlways, .authorizedWhenInUse:
            // Already authorized, no action needed
            break
            
        @unknown default:
            lastError = LocationError.unknownAuthorizationStatus
        }
    }
    
    /// Request a one-time location update
    /// - Parameter completion: Called with the result of the location request
    public func requestLocation(completion: @escaping (Result<ObservationLocation, Error>) -> Void) {
        guard locationServicesEnabled else {
            completion(.failure(LocationError.servicesDisabled))
            return
        }
        
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // Store completion handler and request location
            locationCompletionHandlers.append(completion)
            
            if !isRequestingLocation {
                isRequestingLocation = true
                lastError = nil
                locationManager.requestLocation()
            }
            
        case .notDetermined:
            // Request permission first, then location
            locationCompletionHandlers.append(completion)
            requestLocationPermission()
            
        case .denied, .restricted:
            completion(.failure(LocationError.permissionDenied))
            
        @unknown default:
            completion(.failure(LocationError.unknownAuthorizationStatus))
        }
    }
    
    /// Start continuous location updates (for when app is actively being used for observations)
    public func startLocationUpdates() {
        guard locationServicesEnabled else {
            lastError = LocationError.servicesDisabled
            return
        }
        
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            lastError = LocationError.permissionDenied
            return
        }
        
        locationManager.startUpdatingLocation()
    }
    
    /// Stop continuous location updates
    public func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    /// Clear any stored error
    public func clearError() {
        lastError = nil
    }
    
    /// Ensure we have a current location for observations
    /// This will request location permission if needed, or update current location if stale
    public func ensureLocationForObservation() {
        guard locationServicesEnabled else { return }
        
        if canRequestPermission {
            // First time - request permission
            requestLocationPermission()
        } else if isAuthorized {
            // Check if we need a fresh location (older than 5 minutes)
            if let currentLocation = currentLocation,
               Date().timeIntervalSince(currentLocation.timestamp) < 300 { // 5 minutes
                // Current location is fresh enough, no action needed
                return
            } else {
                // Need a fresh location
                requestLocation { _ in
                    // Location will be stored automatically in currentObservationLocation
                }
            }
        }
    }
    
    // MARK: - Convenience Properties
    
    /// Whether location permission has been granted
    public var isAuthorized: Bool {
        return authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }
    
    /// Whether location permission has been denied
    public var isDenied: Bool {
        return authorizationStatus == .denied || authorizationStatus == .restricted
    }
    
    /// Whether we can request location permission
    public var canRequestPermission: Bool {
        return locationServicesEnabled && authorizationStatus == .notDetermined
    }
    
    /// Whether the user should be directed to settings to enable location
    public var shouldShowSettingsPrompt: Bool {
        return locationServicesEnabled && isDenied && hasRequestedInitialPermission
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update current location
        currentLocation = location
        currentObservationLocation = ObservationLocation(from: location)
        
        // If this was a one-time request, complete all pending handlers
        if isRequestingLocation {
            isRequestingLocation = false
            let observationLocation = ObservationLocation(from: location)
            
            for handler in locationCompletionHandlers {
                handler(.success(observationLocation))
            }
            locationCompletionHandlers.removeAll()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error
        
        // Complete any pending location requests with error
        if isRequestingLocation {
            isRequestingLocation = false
            
            for handler in locationCompletionHandlers {
                handler(.failure(error))
            }
            locationCompletionHandlers.removeAll()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        // If permission was just granted and we have pending requests, fulfill them
        if (status == .authorizedAlways || status == .authorizedWhenInUse) && !locationCompletionHandlers.isEmpty {
            requestLocation { _ in }
        }
        
        // If permission was denied, complete pending requests with error
        if (status == .denied || status == .restricted) && !locationCompletionHandlers.isEmpty {
            for handler in locationCompletionHandlers {
                handler(.failure(LocationError.permissionDenied))
            }
            locationCompletionHandlers.removeAll()
        }
    }
}

// MARK: - Location Errors

public enum LocationError: LocalizedError, CaseIterable {
    case servicesDisabled
    case permissionDenied
    case unknownAuthorizationStatus
    case locationUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .servicesDisabled:
            return Strings.Location.Error.servicesDisabled.string
        case .permissionDenied:
            return Strings.Location.Error.permissionDenied.string
        case .unknownAuthorizationStatus:
            return Strings.Location.Error.unknownStatus.string
        case .locationUnavailable:
            return Strings.Location.Error.unavailable.string
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .servicesDisabled:
            return Strings.Location.Error.Recovery.enableServices.string
        case .permissionDenied:
            return Strings.Location.Error.Recovery.grantPermission.string
        case .unknownAuthorizationStatus, .locationUnavailable:
            return Strings.Location.Error.Recovery.tryAgain.string
        }
    }
}

// MARK: - Singleton Access

extension LocationManager {
    /// Shared instance for app-wide location management
    public static let shared = LocationManager()
}
