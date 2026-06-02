import SwiftUI

// MARK: - Auth View

struct AuthView: View {

    @Environment(AuthManager.self) private var authManager

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showResetAlert = false
    @State private var resetEmail = ""
    @State private var resetSent = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password, confirm }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 60)

                // Logo
                VStack(spacing: 10) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Color(hex: "#30d158"))
                    Text("Life")
                        .font(.largeTitle.bold())
                    Text(isSignUp ? "Create your account" : "Welcome back")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 44)

                // Fields
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                    if isSignUp {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirm)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    // Primary action button
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canSubmit ? Color(hex: "#30d158") : Color(hex: "#30d158").opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                    .disabled(!canSubmit || isLoading)
                }
                .padding(.horizontal, 24)

                // Switch between sign in / sign up
                Button {
                    withAnimation(.spring(response: 0.35)) {
                        isSignUp.toggle()
                        errorMessage = nil
                        confirmPassword = ""
                        password = ""
                    }
                    HapticManager.selection()
                } label: {
                    HStack(spacing: 4) {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .foregroundColor(.secondary)
                        Text(isSignUp ? "Sign In" : "Sign Up")
                            .foregroundColor(Color(hex: "#30d158"))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                .padding(.top, 24)

                if !isSignUp {
                    Button("Forgot password?") {
                        resetEmail = email
                        showResetAlert = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, 10)
                }

                Spacer().frame(height: 60)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .alert("Reset Password", isPresented: $showResetAlert) {
            TextField("Email address", text: $resetEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            Button("Send Reset Link") {
                Task {
                    try? await authManager.resetPassword(email: resetEmail)
                    resetSent = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll email you a link to reset your password.")
        }
        .alert("Email Sent", isPresented: $resetSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your inbox for a password reset link.")
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 1
    }

    private func submit() async {
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }

        if isSignUp {
            if password.count < 6 {
                errorMessage = "Password must be at least 6 characters."
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
        } catch {
            errorMessage = friendlyError(error)
            HapticManager.impact(.light)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.contains("email address is badly formatted") { return "Please enter a valid email address." }
        if msg.contains("password is invalid") || msg.contains("wrong password") { return "Incorrect password. Please try again." }
        if msg.contains("no user record") { return "No account found with that email." }
        if msg.contains("email address is already in use") { return "An account already exists with this email." }
        if msg.contains("network error") { return "Network error. Check your connection." }
        return msg
    }
}
