import Foundation
import Observation

@Observable final class TaxonomyStore {
    private(set) var species: [Taxon] = []
    private(set) var loaded: Bool = false
    private(set) var error: String? = nil // taxonomy load error only
    var checklistError: String? = nil // non-fatal checklist issues
    var enableAbbreviationSearch: Bool = true

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

    func search(_ text: String, minCommonness: Int? = nil, maxCommonness: Int? = nil) -> [Taxon] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        let isAbbr = enableAbbreviationSearch && !needle.isEmpty && needle.range(of: "^[a-zA-Z]+$", options: .regularExpression) != nil
        return species.filter { taxon in
            if let minC = minCommonness, let maxC = maxCommonness, let c = taxon.commonness, (c < minC || c > maxC) { return false }
            if trimmed.isEmpty { return true }
            if isAbbr { return taxon.abbreviations.contains { $0.lowercased().hasPrefix(needle) } }
            return taxon.commonName.lowercased().contains(needle) || taxon.scientificName.lowercased().contains(needle)
        }
    }
}

#if DEBUG
extension TaxonomyStore { func loadPreview(species: [Taxon]) { self.species = species; self.loaded = true; self.error = nil } }
#endif
