import Foundation
import Observation

@Observable final class ObservationStore {
    // counts keyed by taxon id
    private(set) var counts: [String:Int] = [:] {
        didSet { persist() }
    }
    private let persistenceKey = "ObservationCounts"

    struct Recent: Identifiable, Codable, Equatable { let id: String; var lastUpdated: Date }
    private(set) var recent: [Recent] = [] // most-recent first
    private let recentLimit = 20

    init() { load() }

    func count(for id: String) -> Int { counts[id] ?? 0 }

    func increment(_ id: String, by delta: Int = 1) {
        let new = max(0, count(for: id) + delta)
        counts[id] = new
        touchRecent(id)
    }

    func set(_ id: String, to value: Int) {
        counts[id] = max(0, value)
        touchRecent(id)
    }

    func reset(_ id: String) { 
        counts[id] = 0
        touchRecent(id)
    }
    
    func clearAll() { 
        counts.removeAll()
        recent.removeAll() 
    }

    var totalIndividuals: Int { counts.values.reduce(0, +) }
    var totalSpeciesObserved: Int { counts.values.filter { $0 > 0 }.count }

    // MARK: Recent handling
    private func touchRecent(_ id: String) {
        let now = Date()
        if let idx = recent.firstIndex(where: { $0.id == id }) {
            recent[idx].lastUpdated = now
        } else {
            recent.insert(Recent(id: id, lastUpdated: now), at: 0)
        }
        recent.sort { $0.lastUpdated > $1.lastUpdated }
        if recent.count > recentLimit {
            recent.removeLast(recent.count - recentLimit)
        }
    }

    // MARK: Persistence
    private func persist() {
        // Only store positive counts to minimize size
        let positive = counts.filter { $0.value > 0 }
        UserDefaults.standard.set(positive, forKey: persistenceKey)
    }

    private func load() {
        if let stored = UserDefaults.standard.dictionary(forKey: persistenceKey) as? [String:Int] {
            counts = stored
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
