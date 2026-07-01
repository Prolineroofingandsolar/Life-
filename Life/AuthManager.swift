import FirebaseAuth
import FirebaseCore
import AuthenticationServices
import CryptoKit
import SwiftUI

// MARK: - Auth Manager

@MainActor
final class AuthManager: ObservableObject {
    @Published var user: FirebaseAuth.User? = nil
    @Published var isLoading = false
    private var handle: AuthStateDidChangeListenerHandle?

    /// Unhashed nonce stashed between starting an Apple sign-in request and
    /// receiving the credential. Firebase needs the raw nonce to verify
    /// Apple's ID token.
    private var currentAppleNonce: String?

    static var isFirebaseReady: Bool {
        FirebaseApp.app() != nil
    }

    init() {
        guard Self.isFirebaseReady else { return }
        isLoading = true
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isLoading = false
            }
        }
        // Watchdog: never let the splash hang forever if the auth listener
        // doesn't fire (slow/no network, misconfigured Firebase, etc.).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.isLoading == true { self?.isLoading = false }
        }
    }

    deinit {
        if let h = handle { Auth.auth().removeStateDidChangeListener(h) }
    }

    var isSignedIn: Bool { user != nil }

    // MARK: - Email / Password

    func signIn(email: String, password: String) async throws {
        guard Self.isFirebaseReady else { return }
        // The state-change listener will pick up the new user; no need to
        // assign self.user here (avoids the dual-write race noted in audit).
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        guard Self.isFirebaseReady else { return }
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signOut() throws {
        guard Self.isFirebaseReady else { return }
        try Auth.auth().signOut()
        // Listener will null this on the next tick, but clearing eagerly
        // closes a small window where the UI could still render as signed-in.
        self.user = nil
    }

    func resetPassword(email: String) async throws {
        guard Self.isFirebaseReady else { return }
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    // MARK: - Sign in with Apple

    /// Generate and stash a nonce for an Apple sign-in request, returning
    /// the SHA-256 hash to attach to the ASAuthorizationAppleIDRequest.
    /// Apple requires the hashed form; Firebase needs the raw form to verify.
    func prepareAppleSignIn() -> String {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        return Self.sha256(nonce)
    }

    /// Complete a Sign in with Apple flow by exchanging Apple's ID token for
    /// a Firebase credential. Must be called from the `onCompletion` of a
    /// `SignInWithAppleButton`.
    func completeAppleSignIn(result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .failure(let error):
            // User cancelled is the most common failure — propagate so the
            // caller can choose whether to surface it as an error.
            throw error
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let rawNonce = currentAppleNonce,
                  let idTokenData = credential.identityToken,
                  let idToken = String(data: idTokenData, encoding: .utf8) else {
                throw NSError(domain: "AuthManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Couldn't complete Sign in with Apple."
                ])
            }
            let oauthCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: rawNonce,
                fullName: credential.fullName
            )
            _ = try await Auth.auth().signIn(with: oauthCredential)
            currentAppleNonce = nil
        }
    }

    // MARK: - Friendly Error Messages
    //
    // Match on Firebase's typed AuthErrorCode rather than the English string
    // of `localizedDescription` (which breaks under non-English locales and
    // future SDK reword updates). For password reset we deliberately return
    // a neutral message regardless of outcome — this is account enumeration
    // mitigation.

    static func friendlyMessage(for error: Error) -> String {
        let ns = error as NSError
        if let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .invalidEmail:
                return "Please enter a valid email address."
            case .wrongPassword, .invalidCredential:
                return "Email or password is incorrect."
            case .userNotFound:
                return "Email or password is incorrect."
            case .emailAlreadyInUse:
                return "An account already exists with this email."
            case .weakPassword:
                return "Password is too weak — choose a longer one."
            case .networkError:
                return "Network error. Check your connection and try again."
            case .tooManyRequests:
                return "Too many attempts. Try again in a few minutes."
            case .userDisabled:
                return "This account has been disabled."
            case .operationNotAllowed:
                return "This sign-in method is not enabled."
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: - Nonce Utilities (private)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var byte: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
                return byte
            }
            for random in randoms where remainingLength > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}
