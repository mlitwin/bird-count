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
        // Location services status will be checked asynchronously via delegate callbacks
        // Don't call CLLocationManager.locationServicesEnabled() synchronously to avoid blocking main thread
    }
    
    // MARK: - Setup
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Only update if moved 10+ meters
        
        // Authorization status will be updated via didChangeAuthorization delegate callback
        // Don't call locationManager.authorizationStatus synchronously to avoid blocking main thread
    }
    
    // MARK: - Public Methods
    
    /// Check if location services are enabled on the device (asynchronously)
    /// - Parameter completion: Called with the result on the main thread
    public func checkLocationServicesEnabled(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let enabled = CLLocationManager.locationServicesEnabled()
            DispatchQueue.main.async {
                self?.locationServicesEnabled = enabled
                completion(enabled)
            }
        }
    }
    
    /// Request location permissions from the user
    /// This should be called when the user first tries to capture location
    public func requestLocationPermission() {
        // Check location services status first if we don't have a recent check
        checkLocationServicesEnabled { [weak self] enabled in
            guard let self else { return }
            
            guard enabled else {
                self.lastError = LocationError.servicesDisabled
                return
            }
            
            switch self.authorizationStatus {
            case .notDetermined:
                self.hasRequestedInitialPermission = true
                // Dispatch authorization request to avoid blocking main thread
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.locationManager.requestWhenInUseAuthorization()
                }
                
            case .denied, .restricted:
                self.lastError = LocationError.permissionDenied
                
            case .authorizedAlways, .authorizedWhenInUse:
                // Already authorized, no action needed
                break
                
            @unknown default:
                self.lastError = LocationError.unknownAuthorizationStatus
            }
        }
    }
    
    /// Request a one-time location update
    /// - Parameter completion: Called with the result of the location request
    public func requestLocation(completion: @escaping (Result<ObservationLocation, Error>) -> Void) {
        // Check location services status first if we don't have a recent check
        checkLocationServicesEnabled { [weak self] enabled in
            guard let self else { return }
            
            guard enabled else {
                completion(.failure(LocationError.servicesDisabled))
                return
            }
            
            switch self.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                // Store completion handler and request location
                self.locationCompletionHandlers.append(completion)
                
                if !self.isRequestingLocation {
                    self.isRequestingLocation = true
                    self.lastError = nil
                    // Dispatch location request to avoid blocking main thread
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        self?.locationManager.requestLocation()
                    }
                }
                
            case .notDetermined:
                // Request permission first, then location
                self.locationCompletionHandlers.append(completion)
                self.requestLocationPermission()
                
            case .denied, .restricted:
                completion(.failure(LocationError.permissionDenied))
                
            @unknown default:
                completion(.failure(LocationError.unknownAuthorizationStatus))
            }
        }
    }
    
    /// Start continuous location updates (for when app is actively being used for observations)
    public func startLocationUpdates() {
        checkLocationServicesEnabled { [weak self] enabled in
            guard let self else { return }
            
            guard enabled else {
                self.lastError = LocationError.servicesDisabled
                return
            }
            
            guard self.authorizationStatus == .authorizedAlways || self.authorizationStatus == .authorizedWhenInUse else {
                self.lastError = LocationError.permissionDenied
                return
            }
            
            // Dispatch location updates to avoid blocking main thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.locationManager.startUpdatingLocation()
            }
        }
    }
    
    /// Stop continuous location updates
    public func stopLocationUpdates() {
        // Dispatch stop request to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.locationManager.stopUpdatingLocation()
        }
    }
    
    /// Clear any stored error
    public func clearError() {
        lastError = nil
    }
    
    /// Ensure we have a current location for observations
    /// This will request location permission if needed, or update current location if stale
    public func ensureLocationForObservation() {
        checkLocationServicesEnabled { [weak self] enabled in
            guard let self else { return }
            guard enabled else { return }
            
            if self.canRequestPermission {
                // First time - request permission
                self.requestLocationPermission()
            } else if self.isAuthorized {
                // Check if we need a fresh location (older than 5 minutes)
                if let currentLocation = self.currentLocation,
                   Date().timeIntervalSince(currentLocation.timestamp) < 300 { // 5 minutes
                    // Current location is fresh enough, no action needed
                    return
                } else {
                    // Need a fresh location
                    self.requestLocation { _ in
                        // Location will be stored automatically in currentObservationLocation
                    }
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
        
        // Ensure UI updates happen on main thread for @Observable properties
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            // Update current location
            self.currentLocation = location
            self.currentObservationLocation = ObservationLocation(from: location)
            
            // If this was a one-time request, complete all pending handlers
            if self.isRequestingLocation {
                self.isRequestingLocation = false
                let observationLocation = ObservationLocation(from: location)
                
                for handler in self.locationCompletionHandlers {
                    handler(.success(observationLocation))
                }
                self.locationCompletionHandlers.removeAll()
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Ensure UI updates happen on main thread for @Observable properties
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            self.lastError = error
            
            // Complete any pending location requests with error
            if self.isRequestingLocation {
                self.isRequestingLocation = false
                
                for handler in self.locationCompletionHandlers {
                    handler(.failure(error))
                }
                self.locationCompletionHandlers.removeAll()
            }
        }
    }
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Ensure UI updates happen on main thread for @Observable properties
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            
            let authStatus = manager.authorizationStatus
            self.authorizationStatus = authStatus
            
            // Don't check CLLocationManager.locationServicesEnabled() here to avoid blocking main thread
            // This will be checked asynchronously when needed in other methods
            
            // If permission was just granted and we have pending requests, fulfill them
            if (authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse) && !self.locationCompletionHandlers.isEmpty {
                self.requestLocation { _ in }
            }
            
            // If permission was denied, complete pending requests with error
            if (authStatus == .denied || authStatus == .restricted) && !self.locationCompletionHandlers.isEmpty {
                for handler in self.locationCompletionHandlers {
                    handler(.failure(LocationError.permissionDenied))
                }
                self.locationCompletionHandlers.removeAll()
            }
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
