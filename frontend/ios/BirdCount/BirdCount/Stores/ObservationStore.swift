import Foundation
import Observation

@Observable final class ObservationStore {
    // Fundamental model is defined in Models/Observation.swift
    private(set) var observations: [ObservationRecord] = [] { didSet { persist() ; rebuildDerived() } }

    // Derived counts map (species -> count) rebuilt when observations change
    private(set) var counts: [String:Int] = [:]

    struct Recent: Identifiable, Codable, Equatable { let id: String; var lastUpdated: Date }
    private(set) var recent: [Recent] = [] // most-recent first
    private let recentLimit = 20

    private let persistenceKey = "ObservationRecords"

    init() { load(); rebuildDerived() }

    // MARK: Derived helpers
    private func rebuildDerived() {
    counts = observations.reduce(into: [:]) { $0[$1.taxonId, default: 0] += max(0, $1.count) }
    }

    func count(for id: String) -> Int { counts[id] ?? 0 }

    // MARK: Mutations
    func addObservation(_ taxonId: String, begin: Date = Date(), end: Date? = nil, count: Int = 1) {
        observations.append(ObservationRecord(id: UUID(), taxonId: taxonId, begin: begin, end: end, count: max(0, count)))
        touchRecent(taxonId)
    }

    func increment(_ id: String, by delta: Int = 1) {
        guard delta > 0 else { return } // negative increments not supported directly
    addObservation(id, begin: Date(), end: nil, count: delta)
    }

    // Adjust to target value by adding or removing most recent observations for that species.
    func set(_ id: String, to value: Int) {
        let current = count(for: id)
        if value > current {
            increment(id, by: value - current)
        } else if value < current {
            // Decrease from newest records first for that species
            var toRemove = current - value
            var idx = observations.count - 1
            while idx >= 0 && toRemove > 0 {
                let rec = observations[idx]
                if rec.taxonId == id {
                    let c = max(0, rec.count)
                    if c > toRemove {
                        observations[idx].count = c - toRemove
                        toRemove = 0
                    } else {
                        toRemove -= c
                        observations.remove(at: idx)
                    }
                }
                idx -= 1
            }
        }
        // touch recent even if unchanged for consistency
        touchRecent(id)
    }

    func reset(_ id: String) { set(id, to: 0) }

    func clearAll() { observations.removeAll(); recent.removeAll() }

    var totalIndividuals: Int { observations.reduce(0) { $0 + max(0, $1.count) } }
    var totalSpeciesObserved: Int { counts.keys.count }

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
