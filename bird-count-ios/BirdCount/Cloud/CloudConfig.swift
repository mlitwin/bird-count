import Foundation

/// Cloud backend endpoints and OAuth client configuration.
/// Values come from `terraform output` in bird-count-backend (dev environment).
enum CloudConfig {
    static let apiBaseURL = URL(string: "https://mpet543s3g.execute-api.us-east-1.amazonaws.com")!
    static let hostedUIDomain = "birdcount-dev.auth.us-east-1.amazoncognito.com"
    static let clientId = "2td6vh9ru533alouqibidn8sij"
    static let redirectURI = "birdcount://auth/callback"
    static let callbackScheme = "birdcount"
    static let scopes = "openid email"

    static var authorizeURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = hostedUIDomain
        components.path = "/oauth2/authorize"
        return components.url!
    }

    static var tokenURL: URL {
        URL(string: "https://\(hostedUIDomain)/oauth2/token")!
    }
}
