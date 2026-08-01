import SwiftUI

// MARK: - Fitbit Settings Section

/// Connect/disconnect for the Fitbit account, plus the one-time Client ID.
///
/// Its own view rather than more rows inside `SettingsView`'s `Form`: that body
/// already hit the Swift type-checker's time limit once, and this is a lot to
/// add to it.
struct FitbitSettingsSection: View {

    @State private var clientID: String = FitbitConfig.clientID
    @State private var isConnected: Bool = FitbitTokenStore.isConnected
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
                 ? "Sleep, heart rate, HRV, SpO₂ and activity come straight from Fitbit. Apple Health is used only when Fitbit isn't connected."
                 : "Fitbit has closed new registrations on the legacy Web API this connection uses, and switches it off in September 2026. Its replacement is the Google Health API, registered through Google Cloud. Use Apple Health for now.")
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
            Text("Disconnect Fitbit")
        }
        .disabled(isWorking)
    }

    @ViewBuilder
    private var setupRows: some View {
        HStack {
            Text("Client ID")
            Spacer()
            TextField("22XXXX", text: $clientID)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($clientIDFocused)
                .submitLabel(.done)
                .onSubmit { FitbitConfig.clientID = clientID }
        }

        Button {
            FitbitConfig.clientID = clientID
            connect()
        } label: {
            HStack {
                Label("Connect Fitbit", systemImage: "link")
                Spacer()
                if isWorking { ProgressView() }
            }
        }
        .disabled(isWorking || clientID.trimmingCharacters(in: .whitespaces).isEmpty)

        Button {
            UIPasteboard.general.string = FitbitConfig.redirectURI
            message = "Copied \(FitbitConfig.redirectURI) — paste it as the Redirect URL on your Fitbit app."
        } label: {
            Label("Copy redirect URL", systemImage: "doc.on.doc")
        }
    }

    // MARK: Actions

    private func connect() {
        clientIDFocused = false
        isWorking = true
        message = nil
        Task {
            do {
                try await FitbitAuth.shared.connect()
                isConnected = true
                message = "Connected. Open the Health tab and tap Sync to pull your history."
            } catch let error as FitbitError {
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
            await FitbitAuth.shared.disconnect()
            isConnected = false
            isWorking = false
            message = "Disconnected. Life will fall back to Apple Health."
        }
    }
}
