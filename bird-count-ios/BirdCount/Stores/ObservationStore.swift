import Foundation
import Observation

@Observable public final class ObservationStore {
    // Fundamental model is defined in Models/Observation.swift
    public var observations: [ObservationRecord] = [] { didSet { persist() ; rebuildDerived() } }

    // Derived data cache
    private var cache = ObservationStoreCache()
    
    // Settings store dependency for observer info
    private var settingsStore: SettingsStore?
    
    // Backward-compat published accessors for existing call sites
    private(set) var counts: [String:Int] = [:]

    struct Recent: Identifiable, Codable, Equatable { let id: String; var lastUpdated: Date }
    private(set) var recent: [Recent] = [] // most-recent first

    private let persistenceKey = "ObservationRecords"
    private let dirtyIdsKey = "CloudDirtyIds"
    private let cursorKey = "CloudSyncCursor"
    private let orphansKey = "CloudOrphanDTOs"

    // MARK: Cloud sync state
    /// Ids of records created or mutated locally (or received via P2P) that
    /// have not yet been pushed to the cloud. Persisted so offline changes
    /// survive relaunch.
    public private(set) var dirtyIds: Set<UUID> = []

    /// Max serverUpdatedAt this device has seen, as a decimal string.
    /// nil means never synced: the first sync uploads everything.
    public var cloudSyncCursor: String? {
        didSet { defaults.set(cloudSyncCursor, forKey: cursorKey) }
    }

    /// Cloud-delivered children whose parent has not arrived yet (pagination
    /// can deliver a child before its parent); reattached on later merges.
    private var pendingOrphanDTOs: [ObservationRecordDTO] = []

    /// Injectable so tests can isolate persistence (suites run concurrently
    /// in one process; sharing .standard makes them clobber each other).
    private let defaults: UserDefaults

    public init() {
        defaults = .standard
        load()
        rebuildDerived()
    }

    /// Test initializer that starts with empty data (doesn't load from UserDefaults)
    public init(testing: Bool, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if !testing {
            load()
        }
        rebuildDerived()
    }
    
    /// Set the SettingsStore dependency for observer information
    public func setSettingsStore(_ store: SettingsStore) {
        self.settingsStore = store
    }

    // MARK: Derived helpers
    private func rebuildDerived() {
        cache.rebuild(from: observations)
        counts = cache.counts
    }

    func count(for id: String) -> Int { cache.count(for: id) }
    func lastObservedDate(for id: String) -> Date? { cache.lastObservedDate(for: id) }

    // MARK: Mutations
    public func addObservation(_ taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil) {
        let observer = settingsStore?.loginEmail ?? ""
        let record = ObservationRecord(id: UUID(), taxonId: taxonId, begin: begin, end: end, count: max(0, count), location: location, observer: observer)
        observations.append(record)
        markDirty(record.id)
        touchRecent(taxonId)
    }
    
    public func updateLocation(for id: UUID, location: ObservationLocation) {
        if let index = observations.firstIndex(where: { $0.id == id }) {
            var record = observations[index]
            record.location = location
            observations[index] = record
        }
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

    /// Local device reset. NOT a ledger operation and never propagated to
    /// sync peers; also clears cloud sync state so the device re-pulls
    /// everything on its next sync.
    func clearAll() {
        observations.removeAll()
        recent.removeAll()
        dirtyIds.removeAll()
        pendingOrphanDTOs.removeAll()
        cloudSyncCursor = nil
        persistCloudState()
    }

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
    func observationsInRange(_ range: DateRange) -> [ObservationRecord] {
        return observations.compactMap { record -> ObservationRecord? in
            // Check if record overlaps with the range: record.end >= range.begin && record.begin <= range.end
            if record.end >= range.begin && record.begin <= range.end {
                return record
            }
            return nil
        }
    }

    /// Return a flat list of all records (top-level and children) whose end date falls within
    /// [cutoff, rangeEnd] and whose individual count > 0.
    func observationsInWindow(from cutoff: Date, to rangeEnd: Date) -> [ObservationRecord] {
        var result: [ObservationRecord] = []
        func collect(_ records: [ObservationRecord]) {
            for record in records {
                if record.count > 0 && record.end >= cutoff && record.end <= rangeEnd {
                    result.append(record)
                }
                collect(record.children)
            }
        }
        collect(observations)
        return result
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
    
    /// Update an observation record by UUID at the top level.
    /// Returns true if the record was found and updated.
    @discardableResult
    public func updateRecord(by id: UUID, updater: (inout ObservationRecord) -> Void) -> Bool {
        for idx in observations.indices {
            if observations[idx].id == id {
                updater(&observations[idx])
                markDirty(id)
                persist()
                rebuildDerived()
                return true
            }
        }
        return false
    }
    
    /// Update a child observation record by parent and child UUID.
    /// Returns true if the child record was found and updated.
    @discardableResult
    public func updateChildRecord(parentId: UUID, childId: UUID, updater: (inout ObservationRecord) -> Void) -> Bool {
        func updateInChildren(of parent: inout ObservationRecord) -> Bool {
            for idx in parent.children.indices {
                if parent.children[idx].id == childId {
                    updater(&parent.children[idx])
                    return true
                }
                if updateInChildren(of: &parent.children[idx]) {
                    return true
                }
            }
            return false
        }
        
        for idx in observations.indices {
            if observations[idx].id == parentId {
                if updateInChildren(of: &observations[idx]) {
                    markDirty(childId)
                    persist()
                    rebuildDerived()
                    return true
                }
            }
        }
        return false
    }

    /// Attach a child observation record to an existing record identified by `parentId`.
    /// Returns true if the parent was found and the child added.
    @discardableResult
    public func addChildObservation(parentId: UUID, taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1, location: ObservationLocation? = nil, observer: String = "", status: ObservationStatus = .completed) -> Bool {
        let newChild = ObservationRecord(id: UUID(), taxonId: taxonId, begin: begin, end: end, count: count, location: location, observer: observer, status: status)
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
            markDirty(newChild.id)
            touchRecent(taxonId)
            // Mutating nested children does not trigger observations.didSet
            persist()
            rebuildDerived()
        }
        return didAttach
    }
    
    // MARK: Location-aware observation methods
    
    #if os(iOS)
    /// Add observation with automatic location capture if permissions allow
    /// Creates the observation immediately in pending status, then updates with location when available
    public func addObservationWithLocation(_ taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) {
        let observer = settingsStore?.loginEmail ?? ""
        let locationManager = LocationManager.shared
        
        // Create the observation immediately in pending status
        let newObservation = ObservationRecord(taxonId: taxonId, begin: begin, end: end, count: count, location: nil, observer: observer, status: .pending)
        let observationId = newObservation.id
        observations.append(newObservation)
        touchRecent(taxonId)
        
        if locationManager.isAuthorized {
            // Check if we have a recent location (within 5 minutes)
            if let currentLocation = locationManager.currentObservationLocation,
               Date().timeIntervalSince(currentLocation.timestamp) < 300 {
                // Use existing recent location and mark as completed
                updateRecord(by: observationId) { record in
                    record.updateWithLocation(currentLocation)
                }
            } else {
                // Request fresh location and update observation when received
                locationManager.requestLocation { [weak self] result in
                    switch result {
                    case .success(let location):
                        self?.updateRecord(by: observationId) { record in
                            record.updateWithLocation(location)
                        }
                    case .failure(_):
                        // Failed to get location, mark as completed without location
                        self?.updateRecord(by: observationId) { record in
                            record.updateWithLocation(nil)
                        }
                    }
                }
            }
        } else {
            // No location permission, mark as completed without location
            updateRecord(by: observationId) { record in
                record.updateWithLocation(nil)
            }
        }
    }
    
    /// Add child observation with automatic location capture if permissions allow
    /// Creates the child observation immediately in pending status, then updates with location when available
    @discardableResult
    public func addChildObservationWithLocation(parentId: UUID, taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) -> Bool {
        let observer = settingsStore?.loginEmail ?? ""
        let locationManager = LocationManager.shared
        
        // Create child observation immediately in pending status
        let wasAttached = addChildObservation(parentId: parentId, taxonId: taxonId, begin: begin, end: end, count: count, location: nil, observer: observer, status: .pending)
        
        if wasAttached {
            // Find the child we just added to get its ID
            guard let parentRecord = findRecord(by: parentId),
                  let addedChild = parentRecord.children.last else {
                return true // Child was added but we couldn't find it for location update
            }
            
            let childId = addedChild.id
            
            if locationManager.isAuthorized {
                // Check if we have a recent location (within 5 minutes)
                if let currentLocation = locationManager.currentObservationLocation,
                   Date().timeIntervalSince(currentLocation.timestamp) < 300 {
                    // Use existing recent location
                    updateChildRecord(parentId: parentId, childId: childId) { record in
                        record.updateWithLocation(currentLocation)
                    }
                } else {
                    // Request fresh location and update child when received
                    locationManager.requestLocation { [weak self] result in
                        switch result {
                        case .success(let location):
                            self?.updateChildRecord(parentId: parentId, childId: childId) { record in
                                record.updateWithLocation(location)
                            }
                        case .failure(_):
                            // Failed to get location, mark as completed without location
                            self?.updateChildRecord(parentId: parentId, childId: childId) { record in
                                record.updateWithLocation(nil)
                            }
                        }
                    }
                }
            } else {
                // No location permission, mark as completed without location
                updateChildRecord(parentId: parentId, childId: childId) { record in
                    record.updateWithLocation(nil)
                }
            }
        }
        
        return wasAttached
    }
    #else
    /// Add observation with automatic location capture - not available on this platform
    public func addObservationWithLocation(_ taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) {
        // Fall back to adding without location on non-iOS platforms
        addObservation(taxonId, begin: begin, end: end, count: count, location: nil)
    }
    
    /// Add child observation with automatic location capture - not available on this platform
    @discardableResult
    public func addChildObservationWithLocation(parentId: UUID, taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) -> Bool {
        let observer = settingsStore?.loginEmail ?? ""
        // Fall back to adding without location on non-iOS platforms
        return addChildObservation(parentId: parentId, taxonId: taxonId, begin: begin, end: end, count: count, location: nil, observer: observer)
    }
    #endif

    // MARK: Cloud sync support

    public struct MergeStatistics: Equatable {
        public var imported = 0
        public var updated = 0
        public var duplicatesSkipped = 0
        public var orphansHeld = 0
    }

    /// Posted after local mutations add dirty ids; the cloud sync service
    /// listens and schedules a debounced auto-sync.
    public static let didMarkDirtyNotification = Notification.Name("ObservationStoreDidMarkDirty")

    /// Posted whenever records are created or updated, from ANY source (local
    /// edit, cloud pull, P2P import), with the affected ids in userInfo under
    /// `changedIdsUserInfoKey`. PairedPeersStore listens to queue records for
    /// paired devices. Distinct from didMarkDirty, which is cloud-upload
    /// specific and intentionally not posted for cloud pulls.
    public static let didChangeRecordsNotification = Notification.Name("ObservationStoreDidChangeRecords")
    public static let changedIdsUserInfoKey = "changedIds"

    public func markDirty(_ id: UUID) {
        dirtyIds.insert(id)
        persistCloudState()
        NotificationCenter.default.post(name: Self.didMarkDirtyNotification, object: self)
        NotificationCenter.default.post(
            name: Self.didChangeRecordsNotification,
            object: self,
            userInfo: [Self.changedIdsUserInfoKey: [id]]
        )
    }

    /// Current updatedAt for a record (top-level or child), or nil if absent.
    /// Used to detect "edited while a sync was in flight": a record whose
    /// updatedAt no longer matches the pushed copy must stay queued.
    /// For bulk checks use updatedAtById() — this walks the tree per call.
    public func updatedAt(for id: UUID) -> Date? {
        findRecord(by: id)?.updatedAt
    }

    /// One-pass updatedAt snapshot of every record (top-level and children).
    public func updatedAtById() -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        func visit(_ records: [ObservationRecord]) {
            for record in records {
                result[record.id] = record.updatedAt
                visit(record.children)
            }
        }
        visit(observations)
        return result
    }

    /// First-sync bootstrap: everything this device has needs to upload.
    public func markAllDirty() {
        dirtyIds.formUnion(allRecordIds)
        persistCloudState()
    }

    public func clearDirty(_ ids: some Sequence<UUID>) {
        dirtyIds.subtract(ids)
        persistCloudState()
    }

    /// All record ids, top-level and children, flattened.
    public var allRecordIds: [UUID] { flatDTOs().map { $0.id } }

    /// All records as wire DTOs, parents before their children.
    public func flatDTOs() -> [ObservationRecordDTO] {
        var result: [ObservationRecordDTO] = []
        func collect(_ records: [ObservationRecord]) {
            for record in records {
                result.append(record.data)
                collect(record.children)
            }
        }
        collect(observations)
        return result
    }

    /// Merge incoming DTOs (from cloud or P2P sync): put-if-absent by UUID,
    /// whole-record last-writer-wins on updatedAt for existing records.
    /// Children whose parent is absent are held and reattached when the
    /// parent arrives (cloud pagination can deliver a child first).
    /// - Parameter markDirty: true for P2P imports (received records still
    ///   need to flow up to the cloud); false when applying cloud pulls.
    @discardableResult
    public func mergeDTOs(_ dtos: [ObservationRecordDTO], markDirty: Bool) -> MergeStatistics {
        var stats = MergeStatistics()
        var changedIds: [UUID] = []
        // Include previously-held orphans, but let fresher incoming copies win.
        var pending = dtos
        let incomingIds = Set(dtos.map { $0.id })
        pending.append(contentsOf: pendingOrphanDTOs.filter { !incomingIds.contains($0.id) })
        pendingOrphanDTOs.removeAll()

        // Merge into a LOCAL tree and write back once. Both halves matter for
        // scale — paired-device sync merges entire ledgers at once:
        // - the id indices make each DTO O(depth) instead of an O(store)
        //   tree walk;
        // - the local copy makes mutations truly in-place. Mutating the
        //   @Observable `observations` property directly goes through its
        //   get/set accessors, which copy the whole top-level array per
        //   mutation — quadratic again, and what froze devices on pairing.
        var working = observations
        var newDirty: Set<UUID> = []
        var touchedTaxa: [String] = []

        var pathById: [UUID: [Int]] = [:]
        var updatedAtById: [UUID: Date] = [:]
        func indexTree(_ records: [ObservationRecord], prefix: [Int]) {
            for (i, record) in records.enumerated() {
                let path = prefix + [i]
                pathById[record.id] = path
                updatedAtById[record.id] = record.updatedAt
                indexTree(record.children, prefix: path)
            }
        }
        indexTree(working, prefix: [])

        var madeProgress = true
        while madeProgress && !pending.isEmpty {
            madeProgress = false
            var held: [ObservationRecordDTO] = []
            for dto in pending {
                if let existingUpdatedAt = updatedAtById[dto.id] {
                    // Whole-record LWW: replace stored data when the incoming
                    // copy is newer. Children are untouched (separate entries).
                    if dto.updatedAt > existingUpdatedAt, let path = pathById[dto.id] {
                        mutateRecord(at: path, in: &working) { $0.data = dto }
                        updatedAtById[dto.id] = dto.updatedAt
                        stats.updated += 1
                        changedIds.append(dto.id)
                        newDirty.insert(dto.id)
                    } else {
                        stats.duplicatesSkipped += 1
                    }
                    madeProgress = true
                } else if dto.parentId == nil {
                    working.append(ObservationRecord(data: dto))
                    pathById[dto.id] = [working.count - 1]
                    updatedAtById[dto.id] = dto.updatedAt
                    stats.imported += 1
                    changedIds.append(dto.id)
                    newDirty.insert(dto.id)
                    touchedTaxa.append(dto.taxonId)
                    madeProgress = true
                } else if let parentId = dto.parentId, let parentPath = pathById[parentId] {
                    var childPath = parentPath
                    mutateRecord(at: parentPath, in: &working) { parent in
                        parent.children.append(ObservationRecord(data: dto))
                        childPath = parentPath + [parent.children.count - 1]
                    }
                    pathById[dto.id] = childPath
                    updatedAtById[dto.id] = dto.updatedAt
                    stats.imported += 1
                    changedIds.append(dto.id)
                    newDirty.insert(dto.id)
                    touchedTaxa.append(dto.taxonId)
                    madeProgress = true
                } else {
                    held.append(dto)
                }
            }
            pending = held
        }

        observations = working
        if markDirty && !newDirty.isEmpty {
            dirtyIds.formUnion(newDirty)
        }
        // One touch per distinct taxon (touchRecent sorts per call).
        for taxonId in Set(touchedTaxa) {
            touchRecent(taxonId)
        }

        pendingOrphanDTOs = pending
        stats.orphansHeld = pending.count
        persistCloudState()
        persist()
        rebuildDerived()
        if markDirty && (stats.imported > 0 || stats.updated > 0) {
            NotificationCenter.default.post(name: Self.didMarkDirtyNotification, object: self)
        }
        if !changedIds.isEmpty {
            NotificationCenter.default.post(
                name: Self.didChangeRecordsNotification,
                object: self,
                userInfo: [Self.changedIdsUserInfoKey: changedIds]
            )
        }
        return stats
    }

    /// Apply a mutation to the record at an index path in the tree (as built
    /// by mergeDTOs' indexTree). No-op when the path is invalid.
    private func mutateRecord(at path: [Int], in array: inout [ObservationRecord], _ body: (inout ObservationRecord) -> Void) {
        guard let first = path.first, array.indices.contains(first) else { return }
        if path.count == 1 {
            body(&array[first])
        } else {
            mutateRecord(at: Array(path.dropFirst()), in: &array[first].children, body)
        }
    }

    private func persistCloudState() {
        defaults.set(dirtyIds.map { $0.uuidString }, forKey: dirtyIdsKey)
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            defaults.set(try encoder.encode(pendingOrphanDTOs), forKey: orphansKey)
        } catch { /* ignore */ }
    }

    private func loadCloudState() {
        if let strings = defaults.stringArray(forKey: dirtyIdsKey) {
            dirtyIds = Set(strings.compactMap(UUID.init(uuidString:)))
        }
        cloudSyncCursor = defaults.string(forKey: cursorKey)
        if let data = defaults.data(forKey: orphansKey) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            pendingOrphanDTOs = (try? decoder.decode([ObservationRecordDTO].self, from: data)) ?? []
        }
    }

    // MARK: Recent handling
    private func touchRecent(_ id: String) {
        let now = Date()
        if let idx = recent.firstIndex(where: { $0.id == id }) { recent[idx].lastUpdated = now } else { recent.insert(Recent(id: id, lastUpdated: now), at: 0) }
        recent.sort { $0.lastUpdated > $1.lastUpdated }
    }

    // MARK: Persistence
    private func persist() {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(observations)
            defaults.set(data, forKey: persistenceKey)
        } catch { /* ignore */ }
    }

    private func load() {
        if let data = defaults.data(forKey: persistenceKey) {
            do { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; observations = try decoder.decode([ObservationRecord].self, from: data) } catch { observations = [] }
        }
        loadCloudState()
    }
}

// MARK: - Lightweight proxy to expose observation data without coupling stores
final class ObservationStoreProxy {
    static let shared = ObservationStoreProxy()
    private weak var store: ObservationStore?
    func register(_ store: ObservationStore) { self.store = store }
    func observationsInRange(_ range: DateRange) -> [ObservationRecord] { store?.observationsInRange(range) ?? [] }
    func observationsInWindow(from cutoff: Date, to rangeEnd: Date) -> [ObservationRecord] {
        store?.observationsInWindow(from: cutoff, to: rangeEnd) ?? []
    }
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
