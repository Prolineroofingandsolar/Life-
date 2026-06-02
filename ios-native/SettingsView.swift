import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var nameInput: String = ""
    @State private var careSettings: CareSettings = CareSettings()
    @State private var workoutSettings: WorkoutSettings = WorkoutSettings()
    @State private var showResetConfirm = false
    @State private var showShareSheet = false
    @State private var exportURL: URL? = nil
    @State private var showImportPicker = false
    @State private var importErrorMessage: String? = nil
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
                                    _ = await NotificationsManager.shared.requestPermission()
                                    NotificationsManager.shared.scheduleWaterReminder(intervalMinutes: careSettings.waterReminderIntervalMinutes)
                                }
                            } else {
                                NotificationsManager.shared.cancelAll()
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

                // App info
                Section {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("App Group", value: "group.uk.co.prolineroofingandsolar.life")
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
            }
            .onChange(of: workoutSettings.weightUnit) { _, _ in
                appState.setWorkoutSettings(workoutSettings)
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
            // Export failed silently
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
