import FirebaseAuth
import FirebaseCore
import SwiftUI

// MARK: - Auth Manager

@Observable
final class AuthManager {
    var user: FirebaseAuth.User? = nil
    var isLoading = false
    private var handle: AuthStateDidChangeListenerHandle?

    static var isFirebaseReady: Bool {
        FirebaseApp.app() != nil
    }

    init() {
        guard Self.isFirebaseReady else { return }
        isLoading = true
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isLoading = false
            }
        }
    }

    deinit {
        if let h = handle { Auth.auth().removeStateDidChangeListener(h) }
    }

    var isSignedIn: Bool { user != nil }

    func signIn(email: String, password: String) async throws {
        guard Self.isFirebaseReady else { return }
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        guard Self.isFirebaseReady else { return }
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signOut() throws {
        guard Self.isFirebaseReady else { return }
        try Auth.auth().signOut()
    }

    func resetPassword(email: String) async throws {
        guard Self.isFirebaseReady else { return }
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }
}
