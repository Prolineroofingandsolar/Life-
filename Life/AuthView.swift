import SwiftUI
import AuthenticationServices

// MARK: - Auth View

struct AuthView: View {

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var showResetAlert = false
    @State private var resetEmail = ""
    @State private var showResetConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password, confirm }

    /// Minimum password length for sign-up. Above the Firebase default of 6
    /// to give the user's data a sensible baseline of protection.
    private static let minPasswordLength = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 60)
                logo
                fields
                appleButton
                modeSwitch
                forgotPasswordButton
                Spacer().frame(height: 60)
            }
        }
        .background(AppTheme.pageBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .alert("Reset password", isPresented: $showResetAlert) {
            TextField("Email address", text: $resetEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Send reset link") {
                Task { await submitPasswordReset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the email associated with your account.")
        }
        .alert("Check your inbox", isPresented: $showResetConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            // Neutral message — never reveals whether the email exists in our
            // database. This mitigates account-enumeration attacks.
            Text("If an account exists for that address, we've sent a password reset link.")
        }
    }

    // MARK: - Subviews

    private var logo: some View {
        VStack(spacing: 10) {
            Image("life_logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 96, maxHeight: 96)
                .accessibilityHidden(true)
            Text("Life")
                .font(.largeTitle.bold())
            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 44)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .padding()
                .background(AppTheme.cardBg)
                .cornerRadius(12)
                .accessibilityLabel("Email address")

            SecureField("Password", text: $password)
                .textContentType(isSignUp ? .newPassword : .password)
                .focused($focusedField, equals: .password)
                .submitLabel(isSignUp ? .next : .go)
                .onSubmit {
                    if isSignUp { focusedField = .confirm }
                    else { Task { await submit() } }
                }
                .padding()
                .background(AppTheme.cardBg)
                .cornerRadius(12)
                .accessibilityLabel("Password")

            if isSignUp {
                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .confirm)
                    .submitLabel(.go)
                    .onSubmit { Task { await submit() } }
                    .padding()
                    .background(AppTheme.cardBg)
                    .cornerRadius(12)
                    .accessibilityLabel("Confirm password")
                    .transition(.opacity.combined(with: .move(edge: .top)))

                passwordRequirements
                    .transition(.opacity)
            }

            messages

            primaryButton
        }
        .padding(.horizontal, 24)
    }

    private var passwordRequirements: some View {
        HStack(spacing: 6) {
            Image(systemName: password.count >= Self.minPasswordLength ? "checkmark.circle.fill" : "circle")
                .foregroundColor(password.count >= Self.minPasswordLength ? AppTheme.primary : .secondary)
                .font(.caption)
            Text("At least \(Self.minPasswordLength) characters")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var messages: some View {
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
        } else if let success = successMessage {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(AppTheme.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(isSignUp ? "Create account" : "Sign in")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(canSubmit ? AppTheme.primary : AppTheme.primary.opacity(0.4))
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .disabled(!canSubmit || isLoading)
        .accessibilityLabel(isSignUp ? "Create account" : "Sign in")
    }

    private var appleButton: some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
            }
            .padding(.vertical, 8)

            SignInWithAppleButton(
                isSignUp ? .signUp : .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = authManager.prepareAppleSignIn()
                },
                onCompletion: { result in
                    Task { await completeAppleSignIn(result) }
                }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .cornerRadius(12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var modeSwitch: some View {
        Button {
            withAnimation(.spring(response: 0.35)) {
                isSignUp.toggle()
                errorMessage = nil
                successMessage = nil
                confirmPassword = ""
                password = ""
            }
            HapticManager.selection()
        } label: {
            HStack(spacing: 4) {
                Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                    .foregroundColor(.secondary)
                Text(isSignUp ? "Sign in" : "Sign up")
                    .foregroundColor(AppTheme.primary)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .padding(.top, 24)
        .accessibilityLabel(isSignUp ? "Switch to sign in" : "Switch to sign up")
    }

    @ViewBuilder
    private var forgotPasswordButton: some View {
        if !isSignUp {
            Button("Forgot password?") {
                resetEmail = email
                showResetAlert = true
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 10)
        }
    }

    // MARK: - Validation

    private var canSubmit: Bool {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !password.isEmpty else { return false }
        if isSignUp {
            guard password.count >= Self.minPasswordLength else { return false }
            guard password == confirmPassword else { return false }
        }
        return true
    }

    /// Minimal client-side email format validation. Catches obvious typos
    /// (missing @, missing TLD) without firing a Firebase round-trip.
    private static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Submit

    private func submit() async {
        errorMessage = nil
        successMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }

        guard Self.isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address."
            HapticManager.impact(.light)
            return
        }

        if isSignUp {
            if password.count < Self.minPasswordLength {
                errorMessage = "Password must be at least \(Self.minPasswordLength) characters."
                return
            }
            if password != confirmPassword {
                errorMessage = "Passwords don't match."
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if isSignUp {
                try await authManager.signUp(email: trimmedEmail, password: password)
            } else {
                try await authManager.signIn(email: trimmedEmail, password: password)
            }
            HapticManager.success()
            // RootView watches authManager.user and will switch to ContentView
            // automatically; no UI cleanup needed here.
        } catch {
            errorMessage = AuthManager.friendlyMessage(for: error)
            HapticManager.impact(.light)
        }
    }

    private func submitPasswordReset() async {
        let trimmed = resetEmail.trimmingCharacters(in: .whitespaces)
        guard Self.isValidEmail(trimmed) else {
            // Still show the confirmation alert — never reveal whether the
            // email was valid or registered (account enumeration mitigation).
            showResetConfirmation = true
            return
        }
        // Fire and forget; surface the same neutral confirmation regardless
        // of outcome. Errors are intentionally swallowed for the same reason.
        _ = try? await authManager.resetPassword(email: trimmed)
        showResetConfirmation = true
    }

    private func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await authManager.completeAppleSignIn(result: result)
            HapticManager.success()
        } catch {
            // ASAuthorizationError.canceled is the most common path — user
            // tapped Cancel on Apple's sheet. Don't show an error for that.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            errorMessage = AuthManager.friendlyMessage(for: error)
            HapticManager.impact(.light)
        }
    }
}
