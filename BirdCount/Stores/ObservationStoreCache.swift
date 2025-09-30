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
        // Recompute counts map: species id -> sum of all counts per taxonId
        // Process each record and its children individually by their own taxonId
        counts = [:]
        lastObservedAt = [:]
        
        for record in observations {
            processRecord(record)
        }
    }
    
    private mutating func processRecord(_ record: ObservationRecord) {
        // Add this record's count to its taxonId
        let previousCount = counts[record.taxonId, default: 0]
        counts[record.taxonId, default: 0] += record.count
        let newCount = counts[record.taxonId]!
        print("🐦 Cache: taxonId=\(record.taxonId), count=\(record.count), \(previousCount) -> \(newCount) (+\(record.count))")
        
        // Update lastObservedAt
        let ts = record.end
        if let existing = lastObservedAt[record.taxonId] {
            if ts > existing { lastObservedAt[record.taxonId] = ts }
        } else {
            lastObservedAt[record.taxonId] = ts
        }
        
        // Recursively process children
        for child in record.children {
            processRecord(child)
        }
    }

    func count(for id: String) -> Int { counts[id] ?? 0 }
    func lastObservedDate(for id: String) -> Date? { lastObservedAt[id] }

    var totalIndividuals: Int { counts.values.reduce(0, +) }
    var totalSpeciesObserved: Int { counts.values.filter { $0 > 0 }.count }
}
