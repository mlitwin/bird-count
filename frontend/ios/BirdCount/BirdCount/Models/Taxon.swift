import Foundation

struct Taxon: Identifiable, Decodable {
    let id: String
    let commonName: String
    let scientificName: String
    let order: Int
    let rank: String
}
