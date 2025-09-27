import Foundation

/// Lightweight, stateless cache for values derived from ObservationStore.observations
/// Holds only derived data and pure calculations. The owning store is responsible for
/// invoking `rebuild(from:)` when the observations array changes.
struct ObservationStoreCache {
    private(set) var counts: [String:Int] = [:]
    private(set) var lastObservedAt: [String:Date] = [:]

    /// Static method to compute counts for observations within a date range
    /// This encapsulates the common filtering logic used by both HomeView and SummaryView
    static func countsInRange(_ range: DateRange, from allObservations: [ObservationRecord]) -> [String: Int] {
        // Filter top-level observations first, then let rebuild() handle flattening
        let filteredObservations = allObservations.compactMap { record -> ObservationRecord? in
            // Check if record overlaps with the range: record.end >= range.begin && record.begin <= range.end
            if record.end >= range.begin && record.begin <= range.end {
                return record
            }
            return nil
        }
        
        // Build cache from filtered observations (this handles flattening internally)
        var tempCache = ObservationStoreCache()
        tempCache.rebuild(from: filteredObservations)
        return tempCache.counts
    }

    mutating func rebuild(from observations: [ObservationRecord]) {
        // Recompute counts map: species id -> sum of all counts (including negative child adjustments)
        // and lastObservedAt: most recent end date per species.
        // Uses the same flattening logic as SummaryView for consistency.
        counts = [:]
        lastObservedAt = [:]
        
        // Flatten nested observations so counting happens per node (parent and children)
        let flattened = flatten(observations)
        
        // Sum raw counts (children may be negative to adjust parent totals)
        for record in flattened {
            counts[record.taxonId, default: 0] += record.count
            
            let ts = record.end
            if let existing = lastObservedAt[record.taxonId] {
                if ts > existing { lastObservedAt[record.taxonId] = ts }
            } else {
                lastObservedAt[record.taxonId] = ts
            }
        }
    }
    
    // Flatten nested observations so filtering/counting happens per node (parent and children)
    private func flatten(_ records: [ObservationRecord]) -> [ObservationRecord] {
        var result: [ObservationRecord] = []
        result.reserveCapacity(records.count)
        func walk(_ r: ObservationRecord) {
            result.append(r)
            if !r.children.isEmpty { r.children.forEach(walk) }
        }
        records.forEach(walk)
        return result
    }

    func count(for id: String) -> Int { counts[id] ?? 0 }
    func lastObservedDate(for id: String) -> Date? { lastObservedAt[id] }

    var totalIndividuals: Int { counts.values.reduce(0, +) }
    var totalSpeciesObserved: Int { counts.values.filter { $0 > 0 }.count }
}
