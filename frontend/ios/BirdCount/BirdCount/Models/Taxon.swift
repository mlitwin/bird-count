import Foundation

struct Taxon: Identifiable, Decodable {
    let id: String
    let commonName: String
    let scientificName: String
    let order: Int
    let rank: String
    var abbreviations: [String] = [] // generated after decode

    enum CodingKeys: String, CodingKey { case id, commonName, scientificName, order, rank }

    init(id: String, commonName: String, scientificName: String, order: Int, rank: String, abbreviations: [String] = []) {
        self.id = id; self.commonName = commonName; self.scientificName = scientificName; self.order = order; self.rank = rank; self.abbreviations = abbreviations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Use decodeIfPresent to avoid keyNotFound crashes on any missing field.
        let id = try c.decodeIfPresent(String.self, forKey: .id) ?? "<missing-id>"
        let common = try c.decodeIfPresent(String.self, forKey: .commonName) ?? "<missing-commonName>"
        let sci = try c.decodeIfPresent(String.self, forKey: .scientificName) ?? "<missing-scientificName>"
        let order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        let rank = try c.decodeIfPresent(String.self, forKey: .rank) ?? "species"
        self.init(id: id, commonName: common, scientificName: sci, order: order, rank: rank)
    }
}
