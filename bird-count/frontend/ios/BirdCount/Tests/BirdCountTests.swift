import Testing
@testable import BirdCount

struct BirdCountTests {
    @Test func decodeTaxonomy() async throws {
        let json = """[{\"id\":\"amecro\",\"commonName\":\"American Crow\",\"scientificName\":\"Corvus brachyrhynchos\",\"order\":1,\"rank\":\"species\"}]"""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([Taxon].self, from: data)
        #expect(decoded.count == 1)
        #expect(decoded.first?.id == "amecro")
    }
}
