import Foundation
import Observation

@Observable final class TaxonomyStore {
    private(set) var species: [Taxon] = []
    private(set) var loaded: Bool = false
    private(set) var error: String? = nil

    func load() {
        guard !loaded else { return }
        do {
            guard let url = Bundle.main.url(forResource: "ios_taxonomy_min", withExtension: "json") else {
                error = "Missing taxonomy resource"
                return
            }
            let data = try Data(contentsOf: url)
            var decoded = try JSONDecoder().decode([Taxon].self, from: data)
            // Generate abbreviations analogous to web logic
            for i in decoded.indices {
                decoded[i].abbreviations = makeAbbreviations(common: decoded[i].commonName, scientific: decoded[i].scientificName)
            }
            species = decoded.sorted { $0.order < $1.order }
            loaded = true
        } catch let DecodingError.dataCorrupted(ctx) {
            error = "Data corrupted: \(ctx.debugDescription)"
        } catch let DecodingError.keyNotFound(key, ctx) {
            error = "Key not found: \(key.stringValue) at path \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
        } catch let DecodingError.typeMismatch(type, ctx) {
            error = "Type mismatch: \(type) at path \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
        } catch let DecodingError.valueNotFound(value, ctx) {
            error = "Value not found: \(value) at path \(ctx.codingPath.map{ $0.stringValue }.joined(separator: "."))"
        } catch {
            self.error = error.localizedDescription
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
    func search(_ text: String) -> [Taxon] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return species }
        let needle = trimmed.lowercased()
        let isAbbr = needle.range(of: "^[a-zA-Z]+$", options: .regularExpression) != nil
        return species.filter { taxon in
            if isAbbr {
                // abbreviation match: any generated abbreviation starts with the needle characters in order
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
