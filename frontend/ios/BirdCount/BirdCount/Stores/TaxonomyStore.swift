import Foundation
import Observation

@Observable final class TaxonomyStore {
    private(set) var species: [Taxon] = []
    private(set) var loaded: Bool = false
    private(set) var error: String? = nil
    // Added runtime switch for abbreviation search; default true
    var enableAbbreviationSearch: Bool = true

    // Checklist support
    private(set) var checklistSpeciesCommonness: [String:Int] = [:] // taxonId -> commonness
    private(set) var activeChecklistId: String? = nil

    func load() {
        guard !loaded else { return }
        do {
            guard let url = Bundle.main.url(forResource: "ios_taxonomy_min", withExtension: "json") else {
                self.error = "Missing taxonomy resource"
                return
            }
            let data = try Data(contentsOf: url)
            var decoded = try JSONDecoder().decode([Taxon].self, from: data)
            // Generate abbreviations analogous to web logic
            for i in decoded.indices {
                decoded[i].abbreviations = makeAbbreviations(common: decoded[i].commonName, scientific: decoded[i].scientificName)
                // Attach current checklist commonness if available
                if let c = checklistSpeciesCommonness[decoded[i].id] { decoded[i].commonness = c }
            }
            species = decoded.sorted { $0.order < $1.order }
            loaded = true
        } catch let DecodingError.dataCorrupted(ctx) {
            self.error = "Data corrupted: \(ctx.debugDescription)"
        } catch let DecodingError.keyNotFound(key, ctx) {
            self.error = "Key not found: \(key.stringValue) at path \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
        } catch let DecodingError.typeMismatch(type, ctx) {
            self.error = "Type mismatch: \(type) at path \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
        } catch let DecodingError.valueNotFound(value, ctx) {
            self.error = "Value not found: \(value) at path \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Load a checklist resource named like checklist-US-CA-041.json in bundle
    func loadChecklist(id: String) {
        // If same id ignore unless we want to force refresh
        guard activeChecklistId != id else { return }
        activeChecklistId = id
        checklistSpeciesCommonness.removeAll()
        if let url = Bundle.main.url(forResource: id, withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                if let root = try JSONSerialization.jsonObject(with: data) as? [String:Any], let speciesDict = root["species"] as? [String:Any] {
                    for (taxonId, val) in speciesDict {
                        if let obj = val as? [String:Any], let c = obj["commonness"] as? Int {
                            checklistSpeciesCommonness[taxonId] = c
                        }
                    }
                }
            } catch {
                self.error = "Checklist load failed: \(error.localizedDescription)"
            }
        } else {
            self.error = "Checklist file not found: \(id)"
        }
        // Re-annotate species array if already loaded
        if loaded {
            for i in species.indices { species[i].commonness = checklistSpeciesCommonness[species[i].id] }
        }
    }

    private func makeAbbreviations(common: String, scientific: String) -> [String] {
        func nameToAbbreviation(_ name: String) -> String {
            // Uppercase, remove non-letters, split to words, take first letter each
            let cleaned = name.uppercased()
                .replacingOccurrences(of: "[^-A-Za-z /]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[^A-Za-z]", with: " ", options: .regularExpression)
            let parts = cleaned.split { !$0.isLetter }
            return parts.map { String($0.first!) }.joined()
        }
        return [nameToAbbreviation(common), nameToAbbreviation(scientific)]
            .filter { !$0.isEmpty }
    }

    // Case-insensitive substring search across names; if pattern is all letters with no spaces treat as abbreviation sequence.
    func search(_ text: String, minCommonness: Int? = nil, maxCommonness: Int? = nil) -> [Taxon] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        let isAbbr = enableAbbreviationSearch && !needle.isEmpty && needle.range(of: "^[a-zA-Z]+$", options: .regularExpression) != nil
        return species.filter { taxon in
            // Checklist commonness filter first
            if let minC = minCommonness, let maxC = maxCommonness, let c = taxon.commonness {
                if c < minC || c > maxC { return false }
            }
            if trimmed.isEmpty { return true }
            if isAbbr {
                return taxon.abbreviations.contains { $0.lowercased().hasPrefix(needle) }
            } else {
                return taxon.commonName.lowercased().contains(needle) || taxon.scientificName.lowercased().contains(needle)
            }
        }
    }
}

#if DEBUG
extension TaxonomyStore {
    func loadPreview(species: [Taxon]) {
        self.species = species
        self.loaded = true
        self.error = nil
    }
}
#endif
