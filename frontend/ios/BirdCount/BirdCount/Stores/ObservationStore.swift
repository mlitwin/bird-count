import Foundation
import Observation

@Observable final class ObservationStore {
    // counts keyed by taxon id
    private(set) var counts: [String:Int] = [:] {
        didSet { persistCounts() }
    }
    private let persistenceKeyCounts = "ObservationCounts"

    struct Recent: Identifiable, Codable, Equatable { let id: String; var lastUpdated: Date }
    private(set) var recent: [Recent] = [] // most-recent first
    private let recentLimit = 20

    // Event log
    struct Event: Identifiable, Codable { let id: UUID; let taxonId: String; let delta: Int; let newValue: Int; let timestamp: Date }
    private(set) var events: [Event] = [] { didSet { persistEvents() } }
    private let persistenceKeyEvents = "ObservationEvents"
    private let maxPersistedEvents = 2000

    init() { load() }

    func count(for id: String) -> Int { counts[id] ?? 0 }

    func increment(_ id: String, by delta: Int = 1) {
        let old = count(for: id)
        let new = max(0, old + delta)
        guard new != old else { return }
        counts[id] = new
        logChange(id: id, old: old, new: new)
        touchRecent(id)
    }

    func set(_ id: String, to value: Int) {
        let old = count(for: id)
        let new = max(0, value)
        guard new != old else { return }
        counts[id] = new
        logChange(id: id, old: old, new: new)
        touchRecent(id)
    }

    func reset(_ id: String) {
        let old = count(for: id)
        guard old != 0 else { return }
        counts[id] = 0
        logChange(id: id, old: old, new: 0)
        touchRecent(id)
    }
    
    func clearAll() {
        counts.keys.forEach { id in
            let old = counts[id] ?? 0
            if old != 0 { logChange(id: id, old: old, new: 0) }
        }
        counts.removeAll()
        recent.removeAll()
    }

    var totalIndividuals: Int { counts.values.reduce(0, +) }
    var totalSpeciesObserved: Int { counts.values.filter { $0 > 0 }.count }

    // MARK: Event logging
    private func logChange(id: String, old: Int, new: Int) {
        let delta = new - old
        guard delta != 0 else { return }
        events.append(Event(id: UUID(), taxonId: id, delta: delta, newValue: new, timestamp: Date()))
        if events.count > maxPersistedEvents { events.removeFirst(events.count - maxPersistedEvents) }
    }

    // MARK: Recent handling
    private func touchRecent(_ id: String) {
        let now = Date()
        if let idx = recent.firstIndex(where: { $0.id == id }) {
            recent[idx].lastUpdated = now
        } else {
            recent.insert(Recent(id: id, lastUpdated: now), at: 0)
        }
        recent.sort { $0.lastUpdated > $1.lastUpdated }
        if recent.count > recentLimit { recent.removeLast(recent.count - recentLimit) }
    }

    // MARK: Persistence
    private func persistCounts() {
        // Only store positive counts to minimize size
        let positive = counts.filter { $0.value > 0 }
        UserDefaults.standard.set(positive, forKey: persistenceKeyCounts)
    }

    private func persistEvents() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let slice = events.suffix(maxPersistedEvents)
            let data = try encoder.encode(Array(slice))
            UserDefaults.standard.set(data, forKey: persistenceKeyEvents)
        } catch { /* ignore */ }
    }

    private func load() {
        // counts
        if let stored = UserDefaults.standard.dictionary(forKey: persistenceKeyCounts) as? [String:Int] { counts = stored }
        // events
        if let data = UserDefaults.standard.data(forKey: persistenceKeyEvents) {
            do {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                events = try decoder.decode([Event].self, from: data)
            } catch { events = [] }
        }
    }
}

#if DEBUG
extension ObservationStore {
    static var previewInstance: ObservationStore {
        let s = ObservationStore()
        s.set("amecro", to: 3)
        s.set("norbla", to: 1)
        return s
    }
}
#endif
