import SwiftUI

// MARK: - Google Health Settings Section

/// Connect/disconnect for Fitbit data via the Google Health API, plus the
/// one-time OAuth Client ID.
///
/// Its own view rather than more rows inside `SettingsView`'s `Form`: that body
/// already hit the Swift type-checker's time limit once, and this is a lot to
/// add to it.
struct GoogleHealthSettingsSection: View {

    @State private var clientID: String = GoogleHealthConfig.clientID
    @State private var isConnected: Bool = GoogleHealthTokenStore.isConnected
    @State private var isWorking = false
    @State private var message: String? = nil
    @FocusState private var clientIDFocused: Bool

    var body: some View {
        Section {
            if isConnected {
                connectedRows
            } else {
                setupRows
            }
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Fitbit")
        } footer: {
            Text(isConnected
                 ? "Sleep, heart rate, HRV, SpO₂ and activity come from your Fitbit via the Google Health API. Apple Health is used only when this isn't connected."
                 : "Fitbit data now comes through Google. Create a project at console.cloud.google.com, enable the Health API, add yourself as a test user on the OAuth consent screen, then create an iOS OAuth client and paste its Client ID here.")
        }
    }

    // MARK: Rows

    @ViewBuilder
    private var connectedRows: some View {
        HStack {
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
            Spacer()
            if isWorking { ProgressView() }
        }
        Button(role: .destructive) {
            disconnect()
        } label: {
            Text("Disconnect")
        }
        .disabled(isWorking)
    }

    @ViewBuilder
    private var setupRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OAuth Client ID")
                .font(.footnote)
                .foregroundColor(.secondary)
            TextField("123456-abc.apps.googleusercontent.com", text: $clientID)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused($clientIDFocused)
                .submitLabel(.done)
                .onSubmit { GoogleHealthConfig.clientID = clientID }
        }

        Button {
            GoogleHealthConfig.clientID = clientID
            connect()
        } label: {
            HStack {
                Label("Connect Fitbit", systemImage: "link")
                Spacer()
                if isWorking { ProgressView() }
            }
        }
        .disabled(isWorking || clientID.trimmingCharacters(in: .whitespaces).isEmpty)

        // The redirect Google needs is derived from the Client ID, so it can
        // only be shown once one has been entered.
        if !clientID.trimmingCharacters(in: .whitespaces).isEmpty {
            Button {
                GoogleHealthConfig.clientID = clientID
                UIPasteboard.general.string = GoogleHealthConfig.redirectURI
                message = "Copied \(GoogleHealthConfig.redirectURI)"
            } label: {
                Label("Copy redirect URI", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: Actions

    private func connect() {
        clientIDFocused = false
        isWorking = true
        message = nil
        Task {
            do {
                try await GoogleHealthAuth.shared.connect()
                isConnected = true
                message = "Connected. Open the Health tab and tap Sync to pull your history."
            } catch let error as GoogleHealthError {
                // Cancelling isn't a failure worth shouting about.
                if case .cancelled = error { message = nil } else { message = error.errorDescription }
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func disconnect() {
        isWorking = true
        message = nil
        Task {
            await GoogleHealthAuth.shared.disconnect()
            isConnected = false
            isWorking = false
            message = "Disconnected. Life will fall back to Apple Health."
        }
    }
}
