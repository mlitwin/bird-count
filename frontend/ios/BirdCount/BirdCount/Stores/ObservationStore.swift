import Foundation
import Observation

@Observable final class ObservationStore {
    // counts keyed by taxon id
    private(set) var counts: [String:Int] = [:]

    func count(for id: String) -> Int { counts[id] ?? 0 }

    func increment(_ id: String, by delta: Int = 1) {
        let new = max(0, count(for: id) + delta)
        counts[id] = new
    }

    func set(_ id: String, to value: Int) {
        counts[id] = max(0, value)
    }

    func reset(_ id: String) { counts[id] = 0 }

    func clearAll() { counts.removeAll() }

    var totalIndividuals: Int { counts.values.reduce(0, +) }
    var totalSpeciesObserved: Int { counts.values.filter { $0 > 0 }.count }
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
