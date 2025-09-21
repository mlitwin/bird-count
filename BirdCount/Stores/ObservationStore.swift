import Foundation
import Observation

@Observable public final class ObservationStore {
    // Fundamental model is defined in Models/Observation.swift
    public var observations: [ObservationRecord] = [] { didSet { persist() ; rebuildDerived() } }

    // Derived data cache
    private var cache = ObservationStoreCache()
    // Backward-compat published accessors for existing call sites
    private(set) var counts: [String:Int] = [:]

    struct Recent: Identifiable, Codable, Equatable { let id: String; var lastUpdated: Date }
    private(set) var recent: [Recent] = [] // most-recent first
    private let recentLimit = 20

    private let persistenceKey = "ObservationRecords"

    public init() { load(); rebuildDerived() }

    // MARK: Derived helpers
    private func rebuildDerived() {
        cache.rebuild(from: observations)
        counts = cache.counts
    }

    func count(for id: String) -> Int { cache.count(for: id) }
    func lastObservedDate(for id: String) -> Date? { cache.lastObservedDate(for: id) }

    // MARK: Mutations
    public func addObservation(_ taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil) {
        observations.append(ObservationRecord(id: UUID(), taxonId: taxonId, begin: begin, end: end, count: max(0, count), location: location))
        touchRecent(taxonId)
    }
    
    /// Import multiple observations at once (used by sync operations)
    public func importObservations(_ records: [ObservationRecord]) {
        observations.append(contentsOf: records)
        // Note: didSet on observations will automatically trigger persist() and rebuildDerived()
        
        // Update recent list for all imported taxa
        for record in records {
            touchRecent(record.taxonId)
            // Also handle children
            for child in record.children {
                touchRecent(child.taxonId)
            }
        }
    }

    func increment(_ id: String, by delta: Int = 1) {
        guard delta > 0 else { return } // negative increments not supported directly
    addObservation(id, begin: Date(), end: nil, count: delta)
    }

    func clearAll() { observations.removeAll(); recent.removeAll() }

    var totalIndividuals: Int { cache.totalIndividuals }
    var totalSpeciesObserved: Int { cache.totalSpeciesObserved }
    
    /// Calculate total individuals within a specific date range
    func totalIndividuals(in range: DateRange) -> Int {
        let filteredObservations = observationsInRange(range)
        var tempCache = ObservationStoreCache()
        tempCache.rebuild(from: filteredObservations)
        return tempCache.totalIndividuals
    }
    
    /// Calculate total species observed within a specific date range
    func totalSpeciesObserved(in range: DateRange) -> Int {
        let filteredObservations = observationsInRange(range)
        var tempCache = ObservationStoreCache()
        tempCache.rebuild(from: filteredObservations)
        return tempCache.totalSpeciesObserved
    }
    
    /// Filter observations to only include those that overlap with the given date range
    private func observationsInRange(_ range: DateRange) -> [ObservationRecord] {
        return observations.compactMap { record -> ObservationRecord? in
            // Check if record overlaps with the range: record.end >= range.begin && record.begin <= range.end
            if record.end >= range.begin && record.begin <= range.end {
                return record
            }
            return nil
        }
    }

    /// Find an observation record by UUID, searching recursively through children.
    public func findRecord(by id: UUID) -> ObservationRecord? {
        func search(in array: [ObservationRecord]) -> ObservationRecord? {
            for rec in array {
                if rec.id == id { return rec }
                if let found = search(in: rec.children) { return found }
            }
            return nil
        }
        return search(in: observations)
    }

    /// Attach a child observation record to an existing record identified by `parentId`.
    /// Returns true if the parent was found and the child added.
    @discardableResult
    public func addChildObservation(parentId: UUID, taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil) -> Bool {
    let newChild = ObservationRecord(id: UUID(), taxonId: taxonId, begin: begin, end: end, count: count, location: location)
        var didAttach = false
        func attach(into array: inout [ObservationRecord]) {
            for idx in array.indices {
                if array[idx].id == parentId {
                    array[idx].addChild(newChild)
                    didAttach = true
                    return
                }
                // Recurse into children
                attach(into: &array[idx].children)
                if didAttach { return }
            }
        }
        attach(into: &observations)
        if didAttach {
            touchRecent(taxonId)
            // Mutating nested children does not trigger observations.didSet
            persist()
            rebuildDerived()
        }
        return didAttach
    }
    
    // MARK: Location-aware observation methods
    
    /// Add observation with automatic location capture if permissions allow
    public func addObservationWithLocation(_ taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) {
        let locationManager = LocationManager.shared
        
        if locationManager.isAuthorized {
            // Check if we have a recent location (within 5 minutes)
            if let currentLocation = locationManager.currentObservationLocation,
               Date().timeIntervalSince(currentLocation.timestamp) < 300 {
                // Use existing recent location
                addObservation(taxonId, begin: begin, end: end, count: count, location: currentLocation)
            } else {
                // Request fresh location and add observation when received
                locationManager.requestLocation { [weak self] result in
                    switch result {
                    case .success(let location):
                        self?.addObservation(taxonId, begin: begin, end: end, count: count, location: location)
                    case .failure(_):
                        // Failed to get location, add without it
                        self?.addObservation(taxonId, begin: begin, end: end, count: count, location: nil)
                    }
                }
                return // Don't add the observation synchronously, wait for location callback
            }
        } else {
            // No location permission, add without location
            addObservation(taxonId, begin: begin, end: end, count: count, location: nil)
        }
    }
    
    /// Add child observation with automatic location capture if permissions allow
    @discardableResult
    public func addChildObservationWithLocation(parentId: UUID, taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) -> Bool {
        let locationManager = LocationManager.shared
        
        if locationManager.isAuthorized {
            // Check if we have a recent location (within 5 minutes)
            if let currentLocation = locationManager.currentObservationLocation,
               Date().timeIntervalSince(currentLocation.timestamp) < 300 {
                // Use existing recent location
                return addChildObservation(parentId: parentId, taxonId: taxonId, begin: begin, end: end, count: count, location: currentLocation)
            } else {
                // Request fresh location and add child observation when received
                locationManager.requestLocation { [weak self] result in
                    switch result {
                    case .success(let location):
                        _ = self?.addChildObservation(parentId: parentId, taxonId: taxonId, begin: begin, end: end, count: count, location: location)
                    case .failure(_):
                        // Failed to get location, add without it
                        _ = self?.addChildObservation(parentId: parentId, taxonId: taxonId, begin: begin, end: end, count: count, location: nil)
                    }
                }
                return true // Optimistically return true since we're adding async
            }
        } else {
            // No location permission, add without location
            return addChildObservation(parentId: parentId, taxonId: taxonId, begin: begin, end: end, count: count, location: nil)
        }
    }

    // MARK: Recent handling
    private func touchRecent(_ id: String) {
        let now = Date()
        if let idx = recent.firstIndex(where: { $0.id == id }) { recent[idx].lastUpdated = now } else { recent.insert(Recent(id: id, lastUpdated: now), at: 0) }
        recent.sort { $0.lastUpdated > $1.lastUpdated }
        if recent.count > recentLimit { recent.removeLast(recent.count - recentLimit) }
    }

    // MARK: Persistence
    private func persist() {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(observations)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch { /* ignore */ }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey) {
            do { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; observations = try decoder.decode([ObservationRecord].self, from: data) } catch { observations = [] }
        }
    }
}

// MARK: - Lightweight proxy to expose last-observed snapshot without coupling stores
final class ObservationStoreProxy {
    static let shared = ObservationStoreProxy()
    private weak var store: ObservationStore?
    func register(_ store: ObservationStore) { self.store = store }
    func lastDatesSnapshot() -> [String:Date] { store?.cacheSnapshotLastObserved() ?? [:] }
}

private extension ObservationStore {
    func cacheSnapshotLastObserved() -> [String:Date] { cache.lastObservedAt }
}

#if DEBUG
extension ObservationStore {
    static var previewInstance: ObservationStore {
        let s = ObservationStore()
        s.addObservation("amecro")
        s.addObservation("amecro")
        s.addObservation("norbla")
        return s
    }
}
#endif
