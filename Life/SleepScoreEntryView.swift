import SwiftUI

// MARK: - Google score entry

/// Lets the user tell Life what Google Health scored a night, so the estimate
/// can learn how it differs from theirs.
///
/// Deliberately shows our estimate alongside the input: the point is the
/// comparison, and seeing both makes an obvious typo obvious.
struct SleepScoreEntryView: View {

    let day: HealthDay
    let estimate: Int?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var entry: String = ""
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    private var existing: SleepScoreComparison? { appState.sleepComparisons[day.dayKey] }

    private var formattedDate: String {
        guard let date = DayKey.date(from: day.dayKey) else { return day.dayKey }
        return date.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InfoRow(label: "Date", value: formattedDate)
                    InfoRow(label: "Our Estimated Sleep Score", value: estimate.map(String.init) ?? "—")
                }

                Section {
                    HStack {
                        Text("Google Health Sleep Score")
                        Spacer()
                        TextField("0–100", text: $entry)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focused)
                    }
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } footer: {
                    Text("Enter the score exactly as Google Health shows it — a number from 0 to 100, no percent sign. Life uses these to learn how its estimate differs from Google's.")
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            appState.removeSleepComparison(for: day.dayKey)
                            dismiss()
                        } label: {
                            Text("Remove this score")
                        }
                    }
                }
            }
            .navigationTitle("Google Health score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(entry.isEmpty)
                }
            }
            .onAppear {
                if let existing { entry = String(existing.googleScore) }
                focused = true
            }
        }
    }

    private func save() {
        guard let value = Int(entry.trimmingCharacters(in: .whitespaces)) else {
            error = "Enter a whole number between 0 and 100."
            return
        }
        if let rejection = appState.saveSleepComparison(googleScore: value, for: day) {
            error = rejection.message
            return
        }
        dismiss()
    }
}

// MARK: - Debug screen

/// Everything behind one night's score, for diagnosing a disagreement without
/// reverse-engineering it from the UI.
struct SleepScoreDebugView: View {

    let day: HealthDay

    @Environment(AppState.self) private var appState
    @State private var copied = false

    private var payload: SleepNightDiagnostics? {
        let history = appState.healthHistory
        let baselines = SleepFeatureBuilder.baselines(from: history, excluding: day.dayKey)
        let features = SleepFeatureBuilder.features(for: day, history: history, baselines: baselines)
        guard let result = SleepScore.calculate(features: features, baselines: baselines) else { return nil }
        let model = appState.sleepCalibrationModel
        let adjusted = SleepScoreCalibration.apply(model: model, to: result, features: features)
        return SleepDiagnosticsBuilder.build(
            day: day, features: features, result: result,
            adjusted: adjusted, model: model,
            comparison: appState.sleepComparisons[day.dayKey]
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let payload {
                    Text(SleepDiagnosticsBuilder.json(payload))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        UIPasteboard.general.string = SleepDiagnosticsBuilder.json(payload)
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy diagnostics", systemImage: "doc.on.doc")
                    }
                } else {
                    Text("This night couldn't be scored, so there are no diagnostics to show. That normally means sleep stages weren't recorded.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Score diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
