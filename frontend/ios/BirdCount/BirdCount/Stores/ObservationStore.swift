import Foundation
import Observation

@Observable final class ObservationStore {
    // Fundamental model: each observation is its own record.
    struct RecordedObservation: Identifiable, Codable { let id: UUID; let taxonId: String; let timestamp: Date }

    private(set) var observations: [RecordedObservation] = [] { didSet { persist() ; rebuildDerived() } }

    // Derived counts map (species -> count) rebuilt when observations change
    private(set) var counts: [String:Int] = [:]

    struct Recent: Identifiable, Codable, Equatable { let id: String; var lastUpdated: Date }
    private(set) var recent: [Recent] = [] // most-recent first
    private let recentLimit = 20

    private let persistenceKey = "ObservationRecords"

    init() { load(); rebuildDerived() }

    // MARK: Derived helpers
    private func rebuildDerived() {
        counts = observations.reduce(into: [:]) { $0[$1.taxonId, default: 0] += 1 }
    }

    func count(for id: String) -> Int { counts[id] ?? 0 }

    // MARK: Mutations
    func addObservation(_ taxonId: String, timestamp: Date = Date()) {
        observations.append(RecordedObservation(id: UUID(), taxonId: taxonId, timestamp: timestamp))
        touchRecent(taxonId)
    }

    func increment(_ id: String, by delta: Int = 1) {
        guard delta > 0 else { return } // negative increments not supported directly
        for _ in 0..<delta { addObservation(id) }
    }

    // Adjust to target value by adding or removing most recent observations for that species.
    func set(_ id: String, to value: Int) {
        let current = count(for: id)
        if value > current {
            increment(id, by: value - current)
        } else if value < current {
            // Remove newest observations first for that species
            var toRemove = current - value
            for idx in observations.indices.reversed() where toRemove > 0 {
                if observations[idx].taxonId == id { observations.remove(at: idx); toRemove -= 1 }
            }
        }
        // touch recent even if unchanged for consistency
        touchRecent(id)
    }

    func reset(_ id: String) { set(id, to: 0) }

    func clearAll() { observations.removeAll(); recent.removeAll() }

    var totalIndividuals: Int { observations.count }
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
            do { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; observations = try decoder.decode([RecordedObservation].self, from: data) } catch { observations = [] }
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
