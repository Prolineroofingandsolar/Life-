import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var nameInput: String = ""
    @State private var careSettings: CareSettings = CareSettings()
    @State private var workoutSettings: WorkoutSettings = WorkoutSettings()
    @State private var moneySettings: MoneySettings = MoneySettings()
    @State private var showResetConfirm = false
    @State private var showCalculators = false
    @State private var showShareSheet = false
    @State private var exportURL: URL? = nil
    @State private var showImportPicker = false
    @State private var importErrorMessage: String? = nil
    @State private var exportErrorMessage: String? = nil
    @FocusState private var isNameFocused: Bool

    // App version from bundle
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Profile
                Section("Profile") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Your name", text: $nameInput)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                appState.setName(nameInput)
                            }
                    }
                }

                // Body / Weight
                Section("Units") {
                    Picker("Weight Unit", selection: $workoutSettings.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    Picker("Currency", selection: $moneySettings.currency) {
                        ForEach(CurrencyCode.allCases) { currency in
                            Text("\(currency.rawValue) (\(currency.symbol))").tag(currency)
                        }
                    }
                }

                // Workout
                Section("Workout") {
                    Toggle("Rest Timer", isOn: $workoutSettings.restTimerEnabled)

                    if workoutSettings.restTimerEnabled {
                        Stepper(
                            "Rest Duration: \(workoutSettings.defaultRestSeconds)s",
                            value: $workoutSettings.defaultRestSeconds,
                            in: 15...600,
                            step: 15
                        )
                    }
                }

                // Care / Hydration
                Section("Daily Care") {
                    Stepper("Water Goal: \(careSettings.waterGoal) glasses", value: $careSettings.waterGoal, in: 1...20)
                    Stepper("Meal Goal: \(careSettings.mealGoal) meals", value: $careSettings.mealGoal, in: 1...10)
                    Toggle("Water Reminder", isOn: $careSettings.waterReminderEnabled)
                        .onChange(of: careSettings.waterReminderEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let granted = await NotificationsManager.shared.requestPermission()
                                    if granted {
                                        NotificationsManager.shared.scheduleWaterReminder(intervalMinutes: careSettings.waterReminderIntervalMinutes)
                                    } else {
                                        careSettings.waterReminderEnabled = false
                                    }
                                }
                            } else {
                                NotificationsManager.shared.cancelWaterReminder()
                            }
                        }
                    if careSettings.waterReminderEnabled {
                        Stepper(
                            "Every \(careSettings.waterReminderIntervalMinutes) min",
                            value: $careSettings.waterReminderIntervalMinutes,
                            in: 15...240,
                            step: 15
                        )
                    }

                    Toggle("Break Reminder", isOn: $careSettings.breakReminderEnabled)
                        .onChange(of: careSettings.breakReminderEnabled) { _, enabled in
                            if enabled {
                                Task {
                                    let granted = await NotificationsManager.shared.requestPermission()
                                    if granted {
                                        NotificationsManager.shared.scheduleBreakReminder(intervalMinutes: careSettings.breakIntervalMinutes)
                                    } else {
                                        careSettings.breakReminderEnabled = false
                                    }
                                }
                            } else {
                                NotificationsManager.shared.cancelBreakReminder()
                            }
                        }
                    if careSettings.breakReminderEnabled {
                        Stepper(
                            "Every \(careSettings.breakIntervalMinutes) min",
                            value: $careSettings.breakIntervalMinutes,
                            in: 15...240,
                            step: 15
                        )
                        .onChange(of: careSettings.breakIntervalMinutes) { _, minutes in
                            NotificationsManager.shared.scheduleBreakReminder(intervalMinutes: minutes)
                        }
                    }
                }

                HealthSettingsSection()

                // Habit Reminders
                Section("Habit Reminders") {
                    Toggle("Morning Summary", isOn: $careSettings.morningSummaryEnabled)
                    Toggle("Evening Nudge", isOn: $careSettings.eveningNudgeEnabled)
                    Text("Morning Summary lists today's habits at 8am. Evening Nudge lists what's still unfinished at 9pm.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Tools
                Section("Tools") {
                    Button {
                        showCalculators = true
                    } label: {
                        Label("Calculators", systemImage: "function")
                    }
                }

                // Data
                Section("Data") {
                    Button {
                        exportData()
                    } label: {
                        Label("Export Data (JSON)", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showImportPicker = true
                    } label: {
                        Label("Import Data (JSON)", systemImage: "square.and.arrow.down")
                    }

                    if let error = importErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    if let error = exportErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Reset All Data", systemImage: "trash.fill")
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will delete all tasks, habits, workouts, body logs, and bills.")
                }

                // Account
                Section {
                    if let user = authManager.user {
                        InfoRow(label: "Signed in as", value: user.email ?? "—")
                        Button(role: .destructive) {
                            try? authManager.signOut()
                            dismiss()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Account")
                }

                // App info
                Section {
                    InfoRow(label: "Version", value: appVersion)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAll()
                        dismiss()
                    }
                }
            }
            .onAppear {
                nameInput = appState.userName
                careSettings = appState.careSettings
                workoutSettings = appState.workoutSettings
                moneySettings = appState.moneySettings
            }
            .onChange(of: workoutSettings.weightUnit) { _, _ in
                appState.setWorkoutSettings(workoutSettings)
            }
            .onChange(of: moneySettings.currency) { _, _ in
                appState.setMoneySettings(moneySettings)
            }
            .onChange(of: workoutSettings.restTimerEnabled) { _, _ in
                appState.setWorkoutSettings(workoutSettings)
            }
            .onChange(of: workoutSettings.defaultRestSeconds) { _, _ in
                appState.setWorkoutSettings(workoutSettings)
            }
            .onChange(of: careSettings.waterGoal) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .onChange(of: careSettings.mealGoal) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .onChange(of: careSettings.waterReminderEnabled) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .onChange(of: careSettings.waterReminderIntervalMinutes) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .onChange(of: careSettings.breakReminderEnabled) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .onChange(of: careSettings.breakIntervalMinutes) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .onChange(of: careSettings.morningSummaryEnabled) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .onChange(of: careSettings.eveningNudgeEnabled) { _, _ in
                appState.setCareSettings(careSettings)
            }
            .alert("Reset All Data?", isPresented: $showResetConfirm) {
                Button("Reset", role: .destructive) {
                    appState.resetAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone. All your data will be permanently deleted and default data will be restored.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $showCalculators) {
                CalculatorsView()
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
        }
    }

    private func saveAll() {
        appState.setName(nameInput)
        appState.setCareSettings(careSettings)
        appState.setWorkoutSettings(workoutSettings)
    }

    private func exportData() {
        guard let data = appState.exportData else { return }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("life_backup_\(Date().dayKey).json")

        do {
            try data.write(to: fileURL, options: .atomic)
            exportURL = fileURL
            showShareSheet = true
        } catch {
            exportErrorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        importErrorMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try appState.importData(from: data)
            } catch {
                importErrorMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            importErrorMessage = "Could not open file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Health Settings Section

/// Split out of `SettingsView` rather than inlined into its `Form`.
///
/// That body is already a long chain of sections and `onChange` handlers, and
/// adding this to it tipped the Swift type-checker past "unable to type-check
/// this expression in reasonable time". Anything further added to Settings is
/// best written as its own small view for the same reason.
///
/// It also writes straight through to `AppState` instead of mirroring into
/// `@State` and syncing back on change, which is what the rest of the screen
/// does. Fewer moving parts, and no risk of a stale copy overwriting
/// `hasBackfilled` behind a sync that finished while Settings was open.
private struct HealthSettingsSection: View {

    @Environment(AppState.self) private var appState

    private var settings: HealthSettings { appState.healthSettings }

    private var sleepGoalText: String {
        let minutes = settings.sleepGoalMinutes
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private var sleepGoal: Binding<Int> {
        Binding(
            get: { appState.healthSettings.sleepGoalMinutes },
            set: { value in appState.setHealthSettings { $0.sleepGoalMinutes = value } }
        )
    }

    private var exerciseGoal: Binding<Int> {
        Binding(
            get: { appState.healthSettings.exerciseGoalMinutes },
            set: { value in appState.setHealthSettings { $0.exerciseGoalMinutes = value } }
        )
    }

    private var showRecoveryTile: Binding<Bool> {
        Binding(
            get: { appState.healthSettings.showRecoveryTile },
            set: { value in appState.setHealthSettings { $0.showRecoveryTile = value } }
        )
    }

    var body: some View {
        Section {
            Stepper("Sleep Goal: \(sleepGoalText)", value: sleepGoal, in: 240...720, step: 15)
            Stepper("Active Minutes Goal: \(settings.exerciseGoalMinutes)", value: exerciseGoal, in: 5...180, step: 5)
            Toggle("Recovery Tile on Today", isOn: showRecoveryTile)
        } header: {
            Text("Health")
        } footer: {
            Text("Sleep, heart rate, HRV and activity are read from Apple Health. Anything your tracker writes there shows up under Body ▸ Vitals.")
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
