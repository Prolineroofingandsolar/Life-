import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Configuration

/// Google Health API connection settings.
///
/// This replaces the legacy Fitbit Web API, which stopped accepting new app
/// registrations and is decommissioned in September 2026. Fitbit data now comes
/// through Google's unified health API, authorised with a Google account.
///
/// The Client ID is entered in Settings rather than compiled in, so it survives
/// app updates without a code change. Under PKCE a Client ID is not a secret —
/// it's designed to be visible in a public client, which an iOS app is. No
/// client secret is used anywhere in this flow.
enum GoogleHealthConfig {

    private static let clientIDKey = "googlehealth.clientID"

    /// The iOS OAuth client for this app's Google Cloud project.
    ///
    /// Compiled in so the connection works without setup on a fresh install.
    /// This is not a secret: Google's iOS client IDs carry no client secret and
    /// are embedded in every copy of a distributed app by design. It also grants
    /// nothing on its own — the consent screen is in Testing mode, so only
    /// accounts listed as test users can authorise, and each only ever reaches
    /// their own data.
    private static let defaultClientID =
        "669385744983-j9h2iaeu5bjtr8bglnklu7engcopkr4t.apps.googleusercontent.com"

    /// Anything entered in Settings wins, so a different Cloud project can be
    /// pointed at without a code change.
    static var clientID: String {
        get {
            let stored = UserDefaults.standard.string(forKey: clientIDKey) ?? ""
            return stored.isEmpty ? defaultClientID : stored
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: clientIDKey) }
    }

    static var isConfigured: Bool { !clientID.isEmpty }

    /// Google's iOS OAuth clients redirect to the *reversed* client ID. For
    /// `123-abc.apps.googleusercontent.com` that's
    /// `com.googleusercontent.apps.123-abc`.
    ///
    /// This scheme deliberately isn't declared in Info.plist:
    /// `ASWebAuthenticationSession` intercepts its own callback, so it doesn't
    /// need to be — which is what lets the Client ID be entered at runtime
    /// instead of baked into the bundle.
    static var callbackScheme: String {
        let id = clientID
        guard let dot = id.firstIndex(of: ".") else { return "" }
        return "com.googleusercontent.apps." + id[id.startIndex..<dot]
    }

    static var redirectURI: String { callbackScheme + ":/oauth2redirect" }

    static let authorizeURL = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenURL = "https://oauth2.googleapis.com/token"
    static let revokeURL = "https://oauth2.googleapis.com/revoke"
    static let apiBase = "https://health.googleapis.com/v4"

    /// Read-only scopes covering everything Life shows. Taken from the v4
    /// discovery document rather than guessed.
    static let scopes = [
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly"
    ]
}

// MARK: - Token Storage

/// Keychain-backed token storage.
///
/// The refresh token grants ongoing access to a year of personal health
/// history, so it doesn't belong in `UserDefaults` beside the app state — and
/// certainly not in the Firestore snapshot, which is why none of this touches
/// `AppState`.
enum GoogleHealthTokenStore {

    private static let service = "uk.co.prolineroofingandsolar.life.googlehealth"

    struct Tokens {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
    }

    static func save(access: String, refresh: String?, expiresIn: Double) {
        write("access", access)
        // A refresh response doesn't always return a new refresh token; keep the
        // existing one when it doesn't, or the connection dies after an hour.
        if let refresh = refresh { write("refresh", refresh) }
        UserDefaults.standard.set(Date().addingTimeInterval(expiresIn), forKey: "googlehealth.expiresAt")
    }

    static func load() -> Tokens? {
        guard let access = read("access"),
              let refresh = read("refresh"),
              let expiry = UserDefaults.standard.object(forKey: "googlehealth.expiresAt") as? Date
        else { return nil }
        return Tokens(accessToken: access, refreshToken: refresh, expiresAt: expiry)
    }

    static func clear() {
        delete("access")
        delete("refresh")
        UserDefaults.standard.removeObject(forKey: "googlehealth.expiresAt")
    }

    static var isConnected: Bool { load() != nil }

    // MARK: Keychain primitives

    private static func write(_ key: String, _ value: String) {
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum GoogleHealthError: LocalizedError {
    case notConfigured
    case notConnected
    case cancelled
    case badResponse(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Google Cloud OAuth Client ID in Settings first."
        case .notConnected:
            return "Not connected to Google Health."
        case .cancelled:
            return "Sign-in cancelled."
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        case .http(let code, let body):
            switch code {
            case 401: return "Sign-in expired. Reconnect in Settings."
            case 403:
                return "Google refused the request (403). Check the Health API is enabled on your Cloud project and that your account is added as a test user on the OAuth consent screen."
            case 429: return "Rate limit reached. Try again shortly."
            default:  return "Google returned \(code). \(body.prefix(200))"
            }
        }
    }
}

// MARK: - Auth

/// Google OAuth 2.0 with PKCE, entirely on-device.
///
/// PKCE is what lets this work without a backend: the app sends only a hash of
/// a random verifier, then proves possession of the original when exchanging
/// the code. Without it the exchange needs a client secret, which can't ship
/// safely in an app.
@MainActor
final class GoogleHealthAuth: NSObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = GoogleHealthAuth()

    private var session: ASWebAuthenticationSession?

    /// Serialises refreshes. Two syncs refreshing at once would race, and the
    /// second would present a token the first had already replaced.
    private var refreshTask: Task<String, Error>?

    var isConnected: Bool { GoogleHealthTokenStore.isConnected }

    // MARK: Connect

    func connect() async throws {
        guard GoogleHealthConfig.isConfigured else { throw GoogleHealthError.notConfigured }

        let verifier = Self.makeCodeVerifier()
        var components = URLComponents(string: GoogleHealthConfig.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleHealthConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: GoogleHealthConfig.redirectURI),
            URLQueryItem(name: "scope", value: GoogleHealthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Both are needed to be issued a refresh token; without them the
            // connection would expire in an hour and never come back.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components.url else { throw GoogleHealthError.badResponse("bad authorize URL") }

        let callback = try await presentWebAuth(url: url)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        if let error = items?.first(where: { $0.name == "error" })?.value {
            throw GoogleHealthError.badResponse(error)
        }
        guard let code = items?.first(where: { $0.name == "code" })?.value else {
            throw GoogleHealthError.badResponse("no authorisation code in callback")
        }

        try await exchange(code: code, verifier: verifier)
    }

    func disconnect() async {
        if let tokens = GoogleHealthTokenStore.load() {
            var request = URLRequest(url: URL(string: GoogleHealthConfig.revokeURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": tokens.refreshToken])
            _ = try? await URLSession.shared.data(for: request)
        }
        GoogleHealthTokenStore.clear()
    }

    // MARK: Access token

    func accessToken() async throws -> String {
        guard let tokens = GoogleHealthTokenStore.load() else { throw GoogleHealthError.notConnected }
        guard tokens.isExpired else { return tokens.accessToken }

        if let existing = refreshTask { return try await existing.value }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw GoogleHealthError.notConnected }
            defer { self.refreshTask = nil }
            return try await self.refresh(using: tokens.refreshToken)
        }
        refreshTask = task
        return try await task.value
    }

    // MARK: Private

    private func exchange(code: String, verifier: String) async throws {
        try await postToken([
            "client_id": GoogleHealthConfig.clientID,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleHealthConfig.redirectURI,
            "code": code,
            "code_verifier": verifier
        ])
    }

    private func refresh(using refreshToken: String) async throws -> String {
        try await postToken([
            "client_id": GoogleHealthConfig.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
        guard let tokens = GoogleHealthTokenStore.load() else { throw GoogleHealthError.notConnected }
        return tokens.accessToken
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }

    private func postToken(_ fields: [String: String]) async throws {
        var request = URLRequest(url: URL(string: GoogleHealthConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // A rejected refresh means the stored token is dead — drop it so the
            // UI shows "not connected" instead of retrying something that can't
            // work. Google expires refresh tokens for unverified apps after
            // about a week, which is the usual reason to land here.
            if http.statusCode == 400 || http.statusCode == 401 { GoogleHealthTokenStore.clear() }
            throw GoogleHealthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw GoogleHealthError.badResponse("could not read token response")
        }
        GoogleHealthTokenStore.save(
            access: decoded.access_token,
            refresh: decoded.refresh_token,
            expiresIn: decoded.expires_in
        )
    }

    private func presentWebAuth(url: URL) async throws -> URL {
        let scheme = GoogleHealthConfig.callbackScheme
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleHealthError.cancelled)
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleHealthError.badResponse("empty callback"))
                }
            }
            session.presentationContextProvider = self
            // Not ephemeral: reusing the Google session means not retyping the
            // password, and the consent screen still appears because of
            // `prompt=consent`.
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }

    // MARK: PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).googleBase64URL
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).googleBase64URL
    }

    private static func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

private extension Data {
    /// base64url per RFC 7636 — ordinary base64 with the URL-unsafe characters
    /// swapped and padding stripped. Google rejects standard base64 here.
    var googleBase64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
