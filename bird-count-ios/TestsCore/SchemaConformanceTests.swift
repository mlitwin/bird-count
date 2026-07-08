import Foundation
import Testing
@testable import BirdCountCore

/// Drift gate against bird-count-schema: the same golden fixtures the backend
/// validates with ajv must decode/encode cleanly here. A field added to the
/// schema but not the DTO (or vice versa) fails these tests in the same
/// commit that changed the schema.
private final class FixtureLocator {}

struct SchemaConformanceTests {
    static let validObservationFixtures = [
        "observation-minimal", "observation-full",
        "observation-adjustment-child", "observation-legacy-v1",
    ]

    // extra-field.json is intentionally absent: Swift decoders ignore unknown
    // keys by design; the strict boundary is the backend's ajv validation.
    static let invalidObservationFixtures = [
        "missing-id", "bad-status", "bad-count-type", "bad-uuid", "bad-date",
    ]

    private func fixtureData(_ name: String) throws -> Data {
        // Xcode run: fixtures are bundled test resources (see project.yml).
        if let url = Bundle(for: FixtureLocator.self).url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        // `swift test` run: SPM can't bundle resources from outside the
        // package root, so resolve them relative to this source file.
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // TestsCore/
            .deletingLastPathComponent()            // bird-count-ios/
            .deletingLastPathComponent()            // repo root
            .appendingPathComponent("bird-count-schema/fixtures")
        for subdir in ["valid", "invalid"] {
            let url = fixturesDir.appendingPathComponent("\(subdir)/\(name).json")
            if FileManager.default.fileExists(atPath: url.path) {
                return try Data(contentsOf: url)
            }
        }
        throw TestError("fixture \(name).json not found in bundle or \(fixturesDir.path)")
    }

    private struct TestError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    @Test(arguments: validObservationFixtures)
    func decodesValidFixture(name: String) throws {
        let dto = try decoder.decode(ObservationRecordDTO.self, from: try fixtureData(name))
        #expect(!dto.taxonId.isEmpty)
    }

    @Test(arguments: invalidObservationFixtures)
    func rejectsInvalidFixture(name: String) throws {
        let data = try fixtureData(name)
        #expect(throws: (any Error).self) {
            _ = try decoder.decode(ObservationRecordDTO.self, from: data)
        }
    }

    @Test
    func legacyV1BackfillsUpdatedAtFromEnd() throws {
        let dto = try decoder.decode(ObservationRecordDTO.self, from: try fixtureData("observation-legacy-v1"))
        #expect(dto.updatedAt == dto.end)
    }

    @Test
    func adjustmentChildKeepsNegativeCountAndParent() throws {
        let dto = try decoder.decode(ObservationRecordDTO.self, from: try fixtureData("observation-adjustment-child"))
        #expect(dto.count == -3)
        #expect(dto.parentId != nil)
    }

    /// Encode the fully-populated golden record and compare key-for-key with
    /// the fixture the backend validates against.
    @Test
    func encodedFullRecordMatchesGoldenFixture() throws {
        let goldenData = try fixtureData("observation-full")
        let dto = try decoder.decode(ObservationRecordDTO.self, from: goldenData)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(dto)

        let golden = try #require(try JSONSerialization.jsonObject(with: goldenData) as? [String: Any])
        let ours = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(Set(ours.keys) == Set(golden.keys),
                "key drift: ours \(Set(ours.keys).symmetricDifference(Set(golden.keys)))")
        for (key, goldenValue) in golden {
            let oursValue = try #require(ours[key], "missing key \(key)")
            #expect(Self.jsonEqual(oursValue, goldenValue), "value drift at \(key): \(oursValue) != \(goldenValue)")
        }
    }

    @Test
    func syncRequestFixtureObservationsDecode() throws {
        let data = try fixtureData("sync-request")
        struct Request: Decodable { let schemaVersion: Int; let changes: [ObservationRecordDTO] }
        let request = try decoder.decode(Request.self, from: data)
        #expect(request.schemaVersion == 2)
        #expect(!request.changes.isEmpty)
    }

    @Test
    func syncResponseFixtureObservationsDecode() throws {
        let data = try fixtureData("sync-response")
        struct Response: Decodable {
            let cursor: String
            let changes: [ObservationRecordDTO]
            let hasMore: Bool
        }
        let response = try decoder.decode(Response.self, from: data)
        #expect(response.changes.contains { $0.count < 0 })
    }

    private static func jsonEqual(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case let (a, b) as (NSNumber, NSNumber): return a == b
        case let (a, b) as (String, String): return a == b
        case let (a, b) as ([String: Any], [String: Any]):
            return Set(a.keys) == Set(b.keys) && a.allSatisfy { key, value in
                b[key].map { jsonEqual(value, $0) } ?? false
            }
        case let (a, b) as ([Any], [Any]):
            return a.count == b.count && zip(a, b).allSatisfy(jsonEqual)
        case (is NSNull, is NSNull): return true
        default: return false
        }
    }
}
