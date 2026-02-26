import Foundation
import Observation

@Observable final class TaxonomyStore {
    private(set) var species: [Taxon] = []
    private(set) var loaded: Bool = false
    private(set) var error: String? = nil // taxonomy load error only
    var checklistError: String? = nil // non-fatal checklist issues
    private(set) var checklistSpeciesCommonness: [String:Int] = [:]
    private(set) var activeChecklistId: String? = nil
    private var lastChecklistIds: Set<String> = [] // for incremental updates
    private var speciesIndexById: [String:Int] = [:] // id -> index for fast updates

    // MARK: - Performance caches / infra
    private static var taxonomyLoaded = false
    private static var checklistCache: [String:[String:Int]] = [:] // id -> taxonId:commonness
    private static let decodeQueue = DispatchQueue(label: "TaxonomyDecode", qos: .userInitiated)

    // Lightweight decoded model for checklist file
    private struct ChecklistRoot: Decodable {
        struct Entry: Decodable { let commonness: Int? }
        let species: [String:Entry]
    }

    func load() {
        guard !loaded else { return }
        do {
            guard let url = Bundle.main.url(forResource: "ios_taxonomy_min", withExtension: "json") else {
                self.error = "Missing taxonomy resource"
                return
            }
            // Memory-map large file for faster & lower-peak memory decoding
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            var decoded = try JSONDecoder().decode([Taxon].self, from: data)
            for i in decoded.indices {
                decoded[i].abbreviations = makeAbbreviations(common: decoded[i].commonName, scientific: decoded[i].scientificName)
                if let c = checklistSpeciesCommonness[decoded[i].id] { decoded[i].commonness = c }
            }
            species = decoded.sorted { $0.order < $1.order }
            rebuildSpeciesIndex()
            loaded = true
            Self.taxonomyLoaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadChecklist(id rawId: String) {
        let id = rawId.replacingOccurrences(of: ".json", with: "")
        guard activeChecklistId != id else { return }
        activeChecklistId = id
        checklistError = nil

        // Cached fast path
        if let cached = Self.checklistCache[id] {
            applyChecklistCommonness(cached)
            return
        }

        // Decode off main thread to avoid blocking UI
        Self.decodeQueue.async { [weak self] in
            guard let self else { return }
            guard let url = Bundle.main.url(forResource: id, withExtension: "json") else {
                DispatchQueue.main.async { self.checklistError = "Checklist file not found: \(id).json" }
                return
            }
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                // Decode only what we need
                let root = try JSONDecoder().decode(ChecklistRoot.self, from: data)
                var map: [String:Int] = [:]; map.reserveCapacity(root.species.count)
                for (taxonId, entry) in root.species { if let c = entry.commonness { map[taxonId] = c } }
                Self.checklistCache[id] = map // cache
                DispatchQueue.main.async { self.applyChecklistCommonness(map) }
            } catch {
                DispatchQueue.main.async { self.checklistError = "Checklist load failed: \(error.localizedDescription)" }
            }
        }
    }

    private func applyChecklistCommonness(_ map: [String:Int]) {
        checklistSpeciesCommonness = map
        // Incremental updates: clear only taxa that previously had a commonness but no longer do
        let newIds = Set(map.keys)
        let removed = lastChecklistIds.subtracting(newIds)
        if loaded {
            // Fast dictionary lookups once
            if !removed.isEmpty {
                for id in removed { if let idx = speciesIndexById[id] { species[idx].commonness = nil } }
            }
            // Apply new / changed values
            for (taxonId, val) in map { if let idx = speciesIndexById[taxonId] { species[idx].commonness = val } }
        }
        lastChecklistIds = newIds
    }

    private func rebuildSpeciesIndex() {
        speciesIndexById.removeAll(keepingCapacity: true)
        speciesIndexById.reserveCapacity(species.count)
        for (i, taxon) in species.enumerated() { speciesIndexById[taxon.id] = i }
    }

    private func makeAbbreviations(common: String, scientific: String) -> [String] {
        func nameToAbbreviation(_ name: String) -> String {
            let cleaned = name.uppercased()
                .replacingOccurrences(of: "[^-A-Za-z /]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[^A-Za-z]", with: " ", options: .regularExpression)
            let parts = cleaned.split { !$0.isLetter }
            return parts.map { String($0.first!) }.joined()
        }
        return [nameToAbbreviation(common), nameToAbbreviation(scientific)].filter { !$0.isEmpty }
    }

    func search(_ text: String, minCommonness: Int? = nil, maxCommonness: Int? = nil, dateRange: DateRange? = nil) -> [Taxon] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        // Two-phase filter:
        // 1) Fast pass: commonness + abbreviations prefix only (no full-text contains)
        // 2) If empty and query is non-empty, fallback to full-text contains on names
        func withinCommonness(_ taxon: Taxon) -> Bool {
            if let minC = minCommonness, let maxC = maxCommonness, let c = taxon.commonness, (c < minC || c > maxC) { return false }
            return true
        }
        var filtered = species.filter { taxon in
            guard withinCommonness(taxon) else { return false }
            if trimmed.isEmpty { return true }
            if taxon.abbreviations.contains(where: { $0.lowercased().hasPrefix(needle) }) { return true }
            return false
        }
        if filtered.isEmpty && !trimmed.isEmpty {
            filtered = species.filter { taxon in
                guard withinCommonness(taxon) else { return false }
                if taxon.abbreviations.contains(where: { $0.lowercased().hasPrefix(needle) }) { return true }
                return taxon.commonName.lowercased().contains(needle) || taxon.scientificName.lowercased().contains(needle)
            }
        }
        // Then sort by derived order with a recency bucket:
        // 1) Species seen within the current date range are always at the bottom, ordered older→newer so the most recent are last.
        // 2) All others are ordered as before: least→most common; tie-break by recency older→newer; then taxonomy order, then name.
        let effectiveDateRange = dateRange ?? DateRange.defaultRange()
        let observationsInRange = ObservationStoreProxy.shared.observationsInRange(effectiveDateRange)
            .filter { $0.totalCount > 0 }
        
        // Get taxon IDs and their latest dates within the date range
        let recentTaxonIds = Set(observationsInRange.map { $0.taxonId })
        let lastDatesInRange: [String:Date] = {
            var latestDates: [String:Date] = [:]
            for obs in observationsInRange {
                let currentLatest = latestDates[obs.taxonId] ?? Date.distantPast
                if obs.end > currentLatest {
                    latestDates[obs.taxonId] = obs.end
                }
            }
            return latestDates
        }()
        
        // Compute proximate context: species observed within 14 days of dateRange.end,
        // at locations within 32 km of the most recent located observation in that window.
        let proximateWindowSeconds: TimeInterval = 14 * 24 * 3600
        let proximateMaxDistanceMeters: Double = 32_187 // ~20 miles
        let windowCutoff = effectiveDateRange.end.addingTimeInterval(-proximateWindowSeconds)
        let windowRecords = ObservationStoreProxy.shared.observationsInWindow(from: windowCutoff, to: effectiveDateRange.end)

        // Proximate anchor: location of the most recent located record in the window
        let proximateAnchor: ObservationLocation? = windowRecords
            .filter { $0.location != nil }
            .max(by: { $0.end < $1.end })?.location

        var proximateTaxonIds: Set<String> = []
        var proximateFrequency: [String: Int] = [:]
        var lastProximateDates: [String: Date] = [:]
        if let anchor = proximateAnchor {
            for record in windowRecords {
                guard let loc = record.location else { continue }
                guard loc.distance(to: anchor) <= proximateMaxDistanceMeters else { continue }
                guard !recentTaxonIds.contains(record.taxonId) else { continue }
                proximateTaxonIds.insert(record.taxonId)
                proximateFrequency[record.taxonId, default: 0] += 1
                let current = lastProximateDates[record.taxonId] ?? .distantPast
                if record.end > current { lastProximateDates[record.taxonId] = record.end }
            }
        }

        return filtered.sorted { compareTaxa($0, $1, recentTaxonIds: recentTaxonIds, lastDatesInRange: lastDatesInRange, proximateTaxonIds: proximateTaxonIds, proximateFrequency: proximateFrequency, lastProximateDates: lastProximateDates) }
    }
}

private extension TaxonomyStore {
    /// Comparison used for species sorting in search results.
    /// - Bucket A (bottom): observed within the active date range, ordered older→newer.
    /// - Bucket C (middle): proximate — observed within 14 days of dateRange.end and within
    ///   32 km of the proximate anchor, ordered by frequency ascending (most frequent at bottom),
    ///   tie-broken by last proximate date older→newer.
    /// - Bucket B (top): everything else, ordered by commonness ascending then taxonomy then name.
    func compareTaxa(_ a: Taxon, _ b: Taxon, recentTaxonIds: Set<String>, lastDatesInRange: [String:Date], proximateTaxonIds: Set<String>, proximateFrequency: [String:Int], lastProximateDates: [String:Date]) -> Bool {
        let ra = recentTaxonIds.contains(a.id)
        let rb = recentTaxonIds.contains(b.id)

        // Bucket A: recent species go to bottom, ordered older→newer within bucket
        if ra != rb { return !ra && rb }
        if ra && rb { return compareByLastObservedDate(dateA: lastDatesInRange[a.id], dateB: lastDatesInRange[b.id]) }

        let pa = proximateTaxonIds.contains(a.id)
        let pb = proximateTaxonIds.contains(b.id)

        // Bucket C: proximate species sort above bucket B, below bucket A
        if pa != pb { return !pa && pb }
        if pa && pb {
            let fa = proximateFrequency[a.id, default: 0]
            let fb = proximateFrequency[b.id, default: 0]
            if fa != fb { return fa < fb } // lower frequency first; highest frequency at bottom
            return compareByLastObservedDate(dateA: lastProximateDates[a.id], dateB: lastProximateDates[b.id])
        }

        // Bucket B: stable sort by commonness, taxonomy order, name
        return applyStableTieBreakers(a, b)
    }

    
    /// Compare two taxa by their last observed dates (older first)
    private func compareByLastObservedDate(dateA: Date?, dateB: Date?) -> Bool {
        return (dateA ?? .distantPast) < (dateB ?? .distantPast)
    }
    
    /// Apply stable tie-breakers in order: commonness, taxonomy order, common name
    private func applyStableTieBreakers(_ a: Taxon, _ b: Taxon) -> Bool {
        let ca = a.commonness ?? Int.max
        let cb = b.commonness ?? Int.max
        
        // 1. Compare by commonness (rare to common)
        if ca != cb { return ca < cb }
        
        // 2. Compare by taxonomy order
        if a.order != b.order { return a.order < b.order }
        
        // 3. Compare by common name (alphabetical)
        return a.commonName < b.commonName
    }
}

#if DEBUG
extension TaxonomyStore { func loadPreview(species: [Taxon]) { self.species = species; self.loaded = true; self.error = nil } }
#endif
