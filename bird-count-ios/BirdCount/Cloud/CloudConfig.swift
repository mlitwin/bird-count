import Foundation

/// Cloud backend endpoints and OAuth client configuration, loaded from the
/// bundled `cloud-config.json` (values come from `terraform output` in
/// bird-count-backend; update the JSON, not code, when endpoints change).
///
/// Environment selection: Debug builds use "dev", Release/AdHoc use "prod".
/// For ad-hoc testing, `UserDefaults` key `CloudEnvOverride` ("dev"/"prod")
/// takes precedence (set before launch; read once at startup).
struct CloudConfig: Decodable {
    let apiBaseURL: URL
    let hostedUIDomain: String
    let clientId: String
    let redirectURI: String
    let callbackScheme: String
    let scopes: String

    var authorizeURL: URL {
        URL(string: "https://\(hostedUIDomain)/oauth2/authorize")!
    }

    var tokenURL: URL {
        URL(string: "https://\(hostedUIDomain)/oauth2/token")!
    }

    // MARK: Loading

    static let current: CloudConfig = load(environment: activeEnvironment)

    static var activeEnvironment: String {
        if let override = UserDefaults.standard.string(forKey: "CloudEnvOverride"),
           ["dev", "prod"].contains(override) {
            return override
        }
        #if DEBUG
        return "dev"
        #else
        return "prod"
        #endif
    }

    /// A malformed or missing config is a build defect — fail fast and loudly.
    static func load(environment: String, bundle: Bundle = .main) -> CloudConfig {
        guard let url = bundle.url(forResource: "cloud-config", withExtension: "json") else {
            fatalError("cloud-config.json is not bundled")
        }
        do {
            let data = try Data(contentsOf: url)
            let environments = try JSONDecoder().decode([String: CloudConfig].self, from: data)
            guard let config = environments[environment] else {
                fatalError("cloud-config.json has no \"\(environment)\" environment")
            }
            return config
        } catch {
            fatalError("cloud-config.json failed to load: \(error)")
        }
    }
}
