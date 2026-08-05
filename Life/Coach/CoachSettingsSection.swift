import SwiftUI

// MARK: - Coach Settings Section

/// Everything the user controls about the coach.
///
/// Its own view, and split into small computed sections inside it, for the
/// reason `GoogleHealthSettingsSection` gives: `SettingsView`'s body has hit
/// the Swift type-checker's time limit before, and a dozen toggles with
/// computed bindings is exactly the kind of thing that pushes it over.
struct CoachSettingsSection: View {

    @Environment(AppState.self) private var appState

    @State private var showConsent = false
    @State private var showClearConfirmation = false
    @State private var usage: CoachUsage.Snapshot?
    @State private var endpoint: String = CoachEndpoint.baseURL
    @FocusState private var endpointFocused: Bool

    private var settings: CoachSettings { appState.coachSettings }

    var body: some View {
        mainSection
        if settings.enabled {
            cloudSection
            if settings.mayUseCloud {
                usageSection
            }
            styleSection
            dataSection
            historySection
        }
    }

    // MARK: Bindings
    //
    // One per toggle, written out rather than generated, so each read and write
    // goes through `setCoachSettings` and therefore through `save()`.

    private func binding(
        _ keyPath: WritableKeyPath<CoachSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { appState.coachSettings[keyPath: keyPath] },
            set: { value in appState.setCoachSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private var styleBinding: Binding<CoachSettings.Style> {
        Binding(
            get: { appState.coachSettings.style },
            set: { value in appState.setCoachSettings { $0.style = value } }
        )
    }

    // MARK: Sections

    private var mainSection: some View {
        Section {
            Toggle("Life Coach", isOn: binding(\.enabled))
                .accessibilityHint("Shows a suggested next action on the Today screen")
        } header: {
            Text("Coach")
        } footer: {
            Text(settings.enabled
                 ? "One suggestion a day on Today, with the figures behind it."
                 : "The coach is off. Nothing is shown and nothing is sent.")
        }
    }

    private var cloudSection: some View {
        Section {
            Toggle("Use AI", isOn: cloudBinding)
                .accessibilityHint("Sends a summary of your day to Gemini to write the wording")

            if !settings.hasConsented {
                Button("Read what gets sent") { showConsent = true }
                    .accessibilityHint("Opens the consent details")
            }
        } header: {
            Text("AI")
        } footer: {
            // Says what turning it *off* gets you, not just what it costs.
            // "Off" here is a working feature, not a disabled one.
            Text(settings.mayUseCloud
                 ? "A short summary of your day goes to Google's Gemini. Your name, raw health records and sign-ins never leave this phone."
                 : "The coach works entirely on this phone from your own data. Nothing is sent anywhere. Suggestions are plainer, and free.")
        }
    }

    /// Turning AI on for the first time routes through consent rather than
    /// flipping silently — the switch is not the agreement.
    private var cloudBinding: Binding<Bool> {
        Binding(
            get: { appState.coachSettings.mayUseCloud },
            set: { value in
                if value && !appState.coachSettings.hasConsented {
                    showConsent = true
                } else {
                    appState.setCoachSettings { $0.cloudEnabled = value }
                }
            }
        )
    }

    private var usageSection: some View {
        Section {
            if let usage {
                LabeledContent("This month", value: usage.costDescription)
                LabeledContent("Requests", value: "\(usage.calls)")
                if usage.ceiling > 0 {
                    LabeledContent("Monthly cap", value: String(format: "£%.2f", usage.ceiling))
                }
                if usage.isOverCeiling {
                    Text("The cap has been reached. The coach is using local rules until next month.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No requests yet.")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Usage")
        } footer: {
            Text("An estimate from the tokens each request used. The cap is enforced on the server, so it holds even if this figure is out of date.")
        }
        .task { usage = CoachUsage.shared.snapshot() }
    }

    private var styleSection: some View {
        Section {
            Picker("Style", selection: styleBinding) {
                ForEach(CoachSettings.Style.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            Toggle("Morning briefing", isOn: binding(\.morningBriefingEnabled))
            Toggle("Evening review", isOn: binding(\.eveningReviewEnabled))
        } header: {
            Text("What you see")
        } footer: {
            Text("The briefing appears before midday and the review after six. One of each per day.")
        }
    }

    private var dataSection: some View {
        Section {
            Toggle("Sleep and recovery", isOn: binding(\.allowHealth))
            Toggle("Activity", isOn: binding(\.allowActivity))
            Toggle("Training", isOn: binding(\.allowTraining))
            Toggle("Tasks", isOn: binding(\.allowTasks))
            Toggle("Habits", isOn: binding(\.allowHabits))
            Toggle("Include task and habit names", isOn: binding(\.shareTitles))
                .accessibilityHint("When off, the coach knows how many are outstanding but not what they are called")
        } header: {
            Text("What the coach may use")
        } footer: {
            // The reason for the last toggle, in the words that make it obvious.
            Text("Switching a category off means it is never sent, not merely ignored. Names are separate because a task can name a real person — with it off, the coach knows you have two important tasks left but not what they say.")
        }
    }

    private var historySection: some View {
        Section {
            Button("Clear coach history") { showClearConfirmation = true }
                .accessibilityHint("Deletes cached suggestions and briefings")

            NavigationLink {
                CoachEndpointView(endpoint: $endpoint)
            } label: {
                LabeledContent("Backend", value: endpointHost)
            }
        } header: {
            Text("Data and setup")
        } footer: {
            Text("Suggestions are cached on this phone so the same question isn't paid for twice. Clearing them costs nothing but a fresh request.")
        }
        .confirmationDialog(
            "Clear everything the coach has said?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                CoachCache.shared.clear()
                HapticManager.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your health, task and habit data is untouched. Only the coach's cached wording is removed.")
        }
        .sheet(isPresented: $showConsent) {
            CoachConsentView()
        }
    }

    private var endpointHost: String {
        URL(string: CoachEndpoint.baseURL)?.host ?? "Not set"
    }
}

// MARK: - Endpoint

/// Where the deployed function lives.
///
/// Editable because a Cloud Functions URL depends on the project, the region
/// and the runtime generation, and a wrong one produces a feature that fails
/// with no clue why. Not a secret: it is an address, and it refuses anyone
/// without a valid Firebase token.
private struct CoachEndpointView: View {

    @Binding var endpoint: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("https://…", text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("Backend address")
            } header: {
                Text("Coach backend")
            } footer: {
                Text("The base URL of your deployed Cloud Function, without the function name. Leave it alone unless you've deployed to a different project or region.")
            }

            Section {
                Button("Reset to default") {
                    endpoint = CoachEndpoint.defaultURL
                }
            }
        }
        .navigationTitle("Backend")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            // An empty box means "use the default", not "no backend".
            CoachEndpoint.baseURL = trimmed.isEmpty ? CoachEndpoint.defaultURL : trimmed
        }
    }
}
