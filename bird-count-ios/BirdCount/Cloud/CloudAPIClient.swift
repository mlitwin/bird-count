import Foundation

/// Wire types and transport for the sync API
/// (see bird-count-schema/schemas/sync.schema.json).
struct SyncRequestBody: Encodable {
    var schemaVersion = 2
    let clientId: String
    var cursor: String?
    let changes: [ObservationRecordDTO]
}

struct SyncAppliedResult: Decodable {
    let id: UUID
    let result: String // "applied" | "stale" | "invalid"
}

struct SyncResponseBody: Decodable {
    let serverTime: Int64
    let cursor: String
    let applied: [SyncAppliedResult]
    let changes: [ObservationRecordDTO]
    let hasMore: Bool
}

struct PullResponseBody: Decodable {
    let changes: [ObservationRecordDTO]
    let cursor: String
    let hasMore: Bool
}

/// Authenticated HTTP client for the sync API.
@MainActor
struct CloudAPIClient {
    let auth: CloudAuthService

    enum APIError: LocalizedError {
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .http(let status, let body): return "Sync failed (\(status)): \(body)"
            }
        }
    }

    func sync(_ body: SyncRequestBody) async throws -> SyncResponseBody {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try await send(path: "/v1/sync", method: "POST", body: try encoder.encode(body))
    }

    func observations(since cursor: String, limit: Int = 200) async throws -> PullResponseBody {
        try await send(path: "/v1/observations?since=\(cursor)&limit=\(limit)", method: "GET", body: nil)
    }

    private func send<Response: Decodable>(path: String, method: String, body: Data?) async throws -> Response {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: CloudConfig.apiBaseURL.appending(path: path.split(separator: "?")[0])
            .appending(queryItems: Self.queryItems(of: path)))
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Response.self, from: data)
    }

    private static func queryItems(of path: String) -> [URLQueryItem] {
        guard let query = path.split(separator: "?").dropFirst().first else { return [] }
        return query.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            return URLQueryItem(name: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : nil)
        }
    }
}
