import AuthenticationServices
import CryptoKit
import Foundation

/// Sign in with Apple via the Cognito hosted UI:
/// ASWebAuthenticationSession -> authorization code + PKCE -> user pool JWTs.
/// (With Apple as the only IdP the hosted UI skips straight to the Apple sheet.)
/// Tokens live in the Keychain; access tokens refresh silently via /oauth2/token.
@Observable
@MainActor
public final class CloudAuthService: NSObject {
    public private(set) var isSignedIn = false
    /// Email claim from the id token, for display in Settings.
    public private(set) var accountEmail: String?

    private let keychain = KeychainStore()
    private var webAuthSession: ASWebAuthenticationSession?

    private enum Key {
        static let accessToken = "accessToken"
        static let refreshToken = "refreshToken"
        static let idToken = "idToken"
        static let expiry = "accessTokenExpiry"
    }

    public enum AuthError: LocalizedError {
        case notSignedIn
        case badCallback
        case tokenEndpoint(String)

        public var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in"
            case .badCallback: return "Sign-in was cancelled or failed"
            case .tokenEndpoint(let detail): return "Sign-in failed: \(detail)"
            }
        }
    }

    override public init() {
        super.init()
        isSignedIn = keychain.string(for: Key.refreshToken) != nil
        accountEmail = Self.emailClaim(fromIdToken: keychain.string(for: Key.idToken))
    }

    // MARK: Sign in

    public func signIn() async throws {
        let verifier = Self.randomURLSafeString(bytes: 64)
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(url: CloudConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: CloudConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: CloudConfig.redirectURI),
            URLQueryItem(name: "scope", value: CloudConfig.scopes),
            URLQueryItem(name: "identity_provider", value: "SignInWithApple"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]

        let callbackURL = try await startWebAuth(url: components.url!)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.badCallback
        }

        let tokens = try await requestTokens(form: [
            "grant_type": "authorization_code",
            "client_id": CloudConfig.clientId,
            "code": code,
            "redirect_uri": CloudConfig.redirectURI,
            "code_verifier": verifier,
        ])
        store(tokens)
    }

    public func signOut() {
        [Key.accessToken, Key.refreshToken, Key.idToken, Key.expiry].forEach(keychain.delete)
        isSignedIn = false
        accountEmail = nil
    }

    /// A bearer token valid for at least the next minute, refreshing if needed.
    public func validAccessToken() async throws -> String {
        if let token = keychain.string(for: Key.accessToken),
           let expiry = keychain.string(for: Key.expiry).flatMap(TimeInterval.init),
           Date(timeIntervalSince1970: expiry) > Date().addingTimeInterval(60) {
            return token
        }
        guard let refreshToken = keychain.string(for: Key.refreshToken) else {
            throw AuthError.notSignedIn
        }
        let tokens = try await requestTokens(form: [
            "grant_type": "refresh_token",
            "client_id": CloudConfig.clientId,
            "refresh_token": refreshToken,
        ])
        store(tokens)
        guard let token = keychain.string(for: Key.accessToken) else { throw AuthError.notSignedIn }
        return token
    }

    // MARK: Token endpoint

    private struct TokenResponse: Decodable {
        let access_token: String
        let id_token: String?
        let refresh_token: String?
        let expires_in: Int
    }

    private func requestTokens(form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: CloudConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // On a failed refresh the session is over; require a fresh sign-in.
            if form["grant_type"] == "refresh_token" { signOut() }
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            throw AuthError.tokenEndpoint(detail)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func store(_ tokens: TokenResponse) {
        keychain.set(tokens.access_token, for: Key.accessToken)
        let expiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in)).timeIntervalSince1970
        keychain.set(String(expiry), for: Key.expiry)
        if let refresh = tokens.refresh_token { keychain.set(refresh, for: Key.refreshToken) }
        if let idToken = tokens.id_token {
            keychain.set(idToken, for: Key.idToken)
            accountEmail = Self.emailClaim(fromIdToken: idToken)
        }
        isSignedIn = true
    }

    // MARK: Web auth session

    private func startWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: CloudConfig.callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AuthError.badCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }
    }

    // MARK: PKCE helpers

    private static func randomURLSafeString(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    private static func emailClaim(fromIdToken idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }
}

extension CloudAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
