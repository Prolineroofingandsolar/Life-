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
    @State private var showResetConfirmation = false
    @State private var usage: CoachUsage.Snapshot?
    @State private var endpoint: String = CoachEndpoint.baseURL
    @FocusState private var endpointFocused: Bool

    private var settings: CoachSettings { appState.coachSettings }

    var body: some View {
        // Wrapped so the sheet has somewhere to live.
        //
        // `.sheet` was attached to one of the Sections below, and a Section
        // inside a Form is not a reliable presentation host — the modifier is
        // accepted and then quietly never fires. The visible symptom was the
        // "Use AI" toggle springing back to off with no consent screen
        // appearing, because the binding deliberately withholds consent until
        // the screen has been read, and the screen never opened.
        Group {
            mainSection
            if settings.enabled {
                cloudSection
                if settings.mayUseCloud {
                    usageSection
                }
                styleSection
                mutedSection
                dataSection
                historySection
            }
        }
        .sheet(isPresented: $showConsent) {
            CoachConsentView()
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

    /// Categories to stop being nudged about.
    ///
    /// Distinct from the data switches below: this one still lets the coach
    /// *use* the figures — a muted training category doesn't stop recovery
    /// advice taking your training load into account — it only stops the
    /// suggestion itself landing there.
    private var mutedSection: some View {
        Section {
            ForEach(CoachCategory.allCases, id: \.rawValue) { category in
                if category != .general {
                    Toggle(label(for: category), isOn: mutedBinding(category))
                }
            }
        } header: {
            Text("Suggest about")
        } footer: {
            Text("Turn one off and the coach won't suggest anything in that area — it still uses the figures to inform the rest.")
        }
    }

    private func label(for category: CoachCategory) -> String {
        switch category {
        case .sleep:     return "Sleep"
        case .recovery:  return "Recovery"
        case .activity:  return "Activity"
        case .training:  return "Training"
        case .tasks:     return "Tasks"
        case .habits:    return "Habits"
        case .nutrition: return "Nutrition"
        case .general:   return "General"
        }
    }

    /// Inverted on purpose: the row reads "Sleep" and is on when sleep
    /// suggestions are wanted, while the model underneath stores what's muted.
    /// A settings screen full of "Don't suggest sleep" toggles is a screen
    /// nobody parses correctly.
    private func mutedBinding(_ category: CoachCategory) -> Binding<Bool> {
        Binding(
            get: { !appState.coachSettings.mutedCategories.contains(category.rawValue) },
            set: { wanted in
                appState.setCoachSettings { settings in
                    var muted = Set(settings.mutedCategories)
                    if wanted { muted.remove(category.rawValue) } else { muted.insert(category.rawValue) }
                    settings.mutedCategories = muted.sorted()
                }
            }
        )
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

            Button("Reset coach preferences") { showResetConfirmation = true }
                .accessibilityHint("Puts every coach setting back to its default")

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
        .confirmationDialog(
            "Reset every coach setting?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                // Consent is withdrawn along with everything else, so the
                // screen is read again before anything is sent. Resetting
                // preferences while quietly keeping permission to transmit
                // would be the wrong way round.
                appState.setCoachSettings { $0 = CoachSettings() }
                CoachCache.shared.clear()
                HapticManager.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Including your consent to use AI, which you'll be asked for again.")
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
