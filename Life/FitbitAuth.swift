import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Configuration

/// Where the Fitbit connection gets its Client ID.
///
/// Stored in `UserDefaults` and entered in Settings rather than compiled in, so
/// it survives app updates and doesn't need a code change to set up. A Client ID
/// is **not** a secret under PKCE — it's designed to be visible in a public
/// client, which is exactly what an iOS app is. No client secret is used or
/// needed anywhere in this flow.
enum FitbitConfig {

    private static let clientIDKey = "fitbit.clientID"

    static var clientID: String {
        get { UserDefaults.standard.string(forKey: clientIDKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespaces), forKey: clientIDKey) }
    }

    static var isConfigured: Bool { !clientID.isEmpty }

    /// Must match the redirect URI registered on the Fitbit app exactly. The
    /// `life` scheme is already declared in Info.plist for the widgets.
    static let redirectURI = "life://fitbit"
    static let callbackScheme = "life"

    static let authorizeURL = "https://www.fitbit.com/oauth2/authorize"
    static let tokenURL = "https://api.fitbit.com/oauth2/token"
    static let revokeURL = "https://api.fitbit.com/oauth2/revoke"
    static let apiBase = "https://api.fitbit.com"

    /// Everything Life reads. `temperature` is requested even though skin
    /// temperature isn't currently stored (see `FitbitService`), so enabling it
    /// later doesn't force the user through consent again.
    static let scopes = [
        "activity",
        "heartrate",
        "sleep",
        "weight",
        "profile",
        "oxygen_saturation",
        "respiratory_rate",
        "temperature",
        "cardio_fitness"
    ]
}

// MARK: - Token Storage

/// Keychain-backed token storage.
///
/// The refresh token is long-lived and grants access to a year of personal
/// health history, so it does not belong in `UserDefaults` alongside the app
/// state — and definitely not in the Firestore snapshot, which is why none of
/// this touches `AppState`.
enum FitbitTokenStore {

    private static let service = "uk.co.prolineroofingandsolar.life.fitbit"

    struct Tokens {
        var accessToken: String
        var refreshToken: String
        /// When the access token stops working. Fitbit's are short-lived (hours).
        var expiresAt: Date

        var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
    }

    static func save(_ tokens: Tokens) {
        write("access", tokens.accessToken)
        write("refresh", tokens.refreshToken)
        UserDefaults.standard.set(tokens.expiresAt, forKey: "fitbit.expiresAt")
    }

    static func load() -> Tokens? {
        guard let access = read("access"),
              let refresh = read("refresh"),
              let expiry = UserDefaults.standard.object(forKey: "fitbit.expiresAt") as? Date
        else { return nil }
        return Tokens(accessToken: access, refreshToken: refresh, expiresAt: expiry)
    }

    static func clear() {
        delete("access")
        delete("refresh")
        UserDefaults.standard.removeObject(forKey: "fitbit.expiresAt")
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
            // Tokens are only ever refreshed while the app is in use, so the
            // strictest accessibility that still survives a reboot is right.
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

enum FitbitError: LocalizedError {
    case notConfigured
    case notConnected
    case cancelled
    case badResponse(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add your Fitbit Client ID in Settings first."
        case .notConnected:
            return "Not connected to Fitbit."
        case .cancelled:
            return "Sign-in cancelled."
        case .badResponse(let detail):
            return "Unexpected response from Fitbit: \(detail)"
        case .http(let code, let body):
            if code == 401 { return "Fitbit sign-in expired. Reconnect in Settings." }
            if code == 429 { return "Fitbit rate limit reached (150 requests/hour). Try again shortly." }
            return "Fitbit returned \(code). \(body)"
        }
    }
}

// MARK: - Auth

/// OAuth 2.0 Authorization Code Grant with PKCE.
///
/// PKCE is what lets this work with no backend and no client secret: the app
/// generates a random verifier, sends only its SHA-256 hash to Fitbit, then
/// proves possession of the original when exchanging the code. Without it,
/// exchanging a code would require a client secret, which can't be shipped
/// safely in an app and would have meant standing up a server.
@MainActor
final class FitbitAuth: NSObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = FitbitAuth()

    private var session: ASWebAuthenticationSession?

    /// Guards against two sync calls both refreshing at once. Fitbit rotates the
    /// refresh token on every use, so a concurrent second refresh would present
    /// a token that the first call had already invalidated.
    private var refreshTask: Task<String, Error>?

    var isConnected: Bool { FitbitTokenStore.isConnected }

    // MARK: Connect

    func connect() async throws {
        guard FitbitConfig.isConfigured else { throw FitbitError.notConfigured }

        let verifier = Self.makeCodeVerifier()
        var components = URLComponents(string: FitbitConfig.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: FitbitConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: FitbitConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "redirect_uri", value: FitbitConfig.redirectURI),
            URLQueryItem(name: "prompt", value: "login consent")
        ]
        guard let url = components.url else { throw FitbitError.badResponse("bad authorize URL") }

        let callback = try await presentWebAuth(url: url)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw FitbitError.badResponse("no authorisation code in callback")
        }

        try await exchange(code: code, verifier: verifier)
    }

    func disconnect() async {
        if let tokens = FitbitTokenStore.load() {
            // Best effort — clear locally regardless of whether Fitbit answers.
            var request = URLRequest(url: URL(string: FitbitConfig.revokeURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": tokens.accessToken, "client_id": FitbitConfig.clientID])
            _ = try? await URLSession.shared.data(for: request)
        }
        FitbitTokenStore.clear()
    }

    // MARK: Access token

    /// A usable access token, refreshing first if the current one has expired.
    func accessToken() async throws -> String {
        guard let tokens = FitbitTokenStore.load() else { throw FitbitError.notConnected }
        guard tokens.isExpired else { return tokens.accessToken }

        if let existing = refreshTask { return try await existing.value }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw FitbitError.notConnected }
            defer { self.refreshTask = nil }
            return try await self.refresh(using: tokens.refreshToken)
        }
        refreshTask = task
        return try await task.value
    }

    // MARK: Private

    private func exchange(code: String, verifier: String) async throws {
        let body = Self.form([
            "client_id": FitbitConfig.clientID,
            "grant_type": "authorization_code",
            "redirect_uri": FitbitConfig.redirectURI,
            "code": code,
            "code_verifier": verifier
        ])
        try await postToken(body)
    }

    private func refresh(using refreshToken: String) async throws -> String {
        let body = Self.form([
            "client_id": FitbitConfig.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ])
        try await postToken(body)
        guard let tokens = FitbitTokenStore.load() else { throw FitbitError.notConnected }
        return tokens.accessToken
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
    }

    private func postToken(_ body: Data) async throws {
        var request = URLRequest(url: URL(string: FitbitConfig.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // A failed refresh means the stored token is dead; drop it so the UI
            // shows "not connected" rather than retrying a token that can't work.
            if http.statusCode == 400 || http.statusCode == 401 { FitbitTokenStore.clear() }
            throw FitbitError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw FitbitError.badResponse("could not read token response")
        }
        FitbitTokenStore.save(.init(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: Date().addingTimeInterval(decoded.expires_in)
        ))
    }

    private func presentWebAuth(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: FitbitConfig.callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: FitbitError.cancelled)
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: FitbitError.badResponse("empty callback"))
                }
            }
            session.presentationContextProvider = self
            // A fresh session each time, so a previous Fitbit login doesn't get
            // silently reused when reconnecting a different account.
            session.prefersEphemeralWebBrowserSession = true
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
        return Data(bytes).base64URLEncoded
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }

    private static func form(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }
}

private extension Data {
    /// base64url per RFC 7636 — standard base64 with the URL-unsafe characters
    /// swapped and padding stripped. Fitbit rejects ordinary base64 here.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
