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

    func load() {
        guard !loaded else { return }
        do {
            guard let url = Bundle.main.url(forResource: "ios_taxonomy_min", withExtension: "json") else {
                self.error = "Missing taxonomy resource"
                return
            }
            let data = try Data(contentsOf: url)
            var decoded = try JSONDecoder().decode([Taxon].self, from: data)
            for i in decoded.indices {
                decoded[i].abbreviations = makeAbbreviations(common: decoded[i].commonName, scientific: decoded[i].scientificName)
                if let c = checklistSpeciesCommonness[decoded[i].id] { decoded[i].commonness = c }
            }
            species = decoded.sorted { $0.order < $1.order }
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadChecklist(id rawId: String) {
        let id = rawId.replacingOccurrences(of: ".json", with: "")
        guard activeChecklistId != id else { return }
        activeChecklistId = id
        checklistSpeciesCommonness.removeAll()
        checklistError = nil
        guard let url = Bundle.main.url(forResource: id, withExtension: "json") else {
            self.checklistError = "Checklist file not found: \(id).json"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String:Any], let speciesDict = root["species"] as? [String:Any] {
                for (taxonId, val) in speciesDict {
                    if let obj = val as? [String:Any], let c = obj["commonness"] as? Int { checklistSpeciesCommonness[taxonId] = c }
                }
            }
        } catch {
            self.checklistError = "Checklist load failed: \(error.localizedDescription)"
        }
        if loaded { for i in species.indices { species[i].commonness = checklistSpeciesCommonness[species[i].id] } }
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
            if let minC = minCommonness, let maxC = maxCommonness, let c = taxon.commonness { if c < minC || c > maxC { return false } }
            if trimmed.isEmpty { return true }
            if isAbbr { return taxon.abbreviations.contains { $0.lowercased().hasPrefix(needle) } }
            return taxon.commonName.lowercased().contains(needle) || taxon.scientificName.lowercased().contains(needle)
        }
    }
}

#if DEBUG
extension TaxonomyStore { func loadPreview(species: [Taxon]) { self.species = species; self.loaded = true; self.error = nil } }
#endif
