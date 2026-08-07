import SwiftUI

// MARK: - Adjust Workout Sheet

/// "Make this shorter." "Only dumbbells." "Go easy today."
///
/// Four buttons that need no interpretation at all, and one text field that
/// does. Either way the result is the same: a **diff** — every replacement,
/// every set removed, the new estimated duration — and a button. The workout is
/// untouched until that button is pressed.
///
/// The presets come first on purpose. A model call to understand "shorter" is a
/// call spent on a question the app can already answer.
struct AdjustWorkoutSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// The exercises as they stand. Copied in; never written back from here.
    let exercises: [RoutineExercise]
    /// What the sheet's host does with an accepted adjustment. This is the only
    /// way anything changes.
    var onApply: ([RoutineExercise]) -> Void

    @State private var request: WorkoutAdjuster.Request?
    @State private var adjustment: WorkoutAdjuster.Adjustment?
    @State private var freeText = ""
    @State private var isInterpreting = false
    @State private var interpretation: String?
    @State private var failure: String?

    private var settings: CoachSettings { appState.coachSettings }
    private var service: WorkoutBuilderService { WorkoutBuilderService() }
    private var minutes: Int { WorkoutAdjuster.estimatedMinutes(exercises) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    presets
                    composer
                    if let adjustment { diff(adjustment) }
                    if let failure { warning(failure) }
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Adjust today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let adjustment, !adjustment.exercises.isEmpty {
                    applyBar(adjustment)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(exercises.count) exercises · about \(minutes) minutes")
                .font(.subheadline.weight(.semibold))
            Text("Nothing changes until you apply it.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QUICK CHANGES")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                preset("20 min shorter", .shorten(byMinutes: 20))
                preset("Lighter", .lighter)
            }
            HStack(spacing: 8) {
                preset("Dumbbells only", .equipmentOnly([.dumbbell]))
                preset("Bodyweight only", .equipmentOnly([.bodyweight]))
            }
        }
    }

    private func preset(_ title: String, _ value: WorkoutAdjuster.Request) -> some View {
        Button {
            HapticManager.selection()
            interpretation = nil
            failure = nil
            apply(value)
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(request == value ? AppTheme.trainAccent.opacity(0.18) : AppTheme.cardBg)
                .foregroundColor(request == value ? AppTheme.trainAccent : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Free text

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OR SAY WHAT YOU NEED")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("I've only got half an hour…", text: $freeText, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(12)
                    .background(AppTheme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(isInterpreting)

                Button {
                    Task { await interpret() }
                } label: {
                    if isInterpreting {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(freeText.trimmingCharacters(in: .whitespaces).isEmpty || isInterpreting)
                .accessibilityLabel("Interpret this request")
            }

            if !settings.mayUseCloud {
                Text("AI is off, so this uses the buttons above instead. You can turn it on in Settings.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let interpretation {
                Text(interpretation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Diff

    private func diff(_ adjustment: WorkoutAdjuster.Adjustment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WHAT CHANGES")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(adjustment.originalMinutes)m → \(adjustment.adjustedMinutes)m")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(
                        adjustment.adjustedMinutes < adjustment.originalMinutes
                            ? AppTheme.trainAccent
                            : .secondary
                    )
            }

            if adjustment.isEmpty {
                Text("Nothing needed changing — this already fits.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(adjustment.changes) { change in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: change))
                            .font(.caption)
                            .foregroundColor(colour(for: change))
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(change.text)
                            .font(.footnote)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if adjustment.exercises.count < WorkoutAdjuster.minimumExercises {
                warning("That leaves \(adjustment.exercises.count) exercises. Worth picking a different session today rather than applying this.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func icon(for change: WorkoutAdjuster.Change) -> String {
        switch change {
        case .removed:        return "minus.circle"
        case .replaced:       return "arrow.left.arrow.right"
        case .setsReduced:    return "minus"
        case .restShortened:  return "timer"
        case .effortReduced:  return "gauge.with.dots.needle.33percent"
        case .shortfall:      return "exclamationmark.triangle"
        }
    }

    private func colour(for change: WorkoutAdjuster.Change) -> Color {
        switch change {
        case .shortfall: return .orange
        case .removed:   return .secondary
        default:         return AppTheme.trainAccent
        }
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func applyBar(_ adjustment: WorkoutAdjuster.Adjustment) -> some View {
        Button {
            HapticManager.success()
            // Removals here are a preference, not just an edit: these are the
            // exercises someone dropped when the session had to give something
            // up, and the builder should hear about it.
            let kept = Set(adjustment.exercises.map(\.exerciseId))
            for item in exercises where !kept.contains(item.exerciseId) {
                appState.recordFeedback(.dismissed, source: .adjustment, exerciseId: item.exerciseId)
            }

            onApply(adjustment.exercises)
            dismiss()
        } label: {
            Text("Apply these changes")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.brandGradient)
                .clipShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(adjustment.isEmpty)
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: Work

    private func apply(_ value: WorkoutAdjuster.Request) {
        request = value
        adjustment = WorkoutAdjuster.adjust(
            exercises: exercises,
            library: appState.exercises,
            request: value
        )
    }

    /// Sends the sentence, gets back one of four cases, performs it here.
    ///
    /// The model never sees the workout and never describes an edit. It reads a
    /// sentence and picks a category; the adjustment itself is Swift, against
    /// the real library, shown as a diff.
    private func interpret() async {
        let text = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isInterpreting = true
        defer { isInterpreting = false }
        failure = nil

        let context = CoachContextBuilder.build(
            appState: appState,
            permissions: .init(settings),
            snapshot: appState.healthSnapshot
        )

        do {
            let suggestion = try await service.interpretAdjustment(
                request: text, context: context, settings: settings
            )
            guard let parsed = suggestion.request else {
                failure = "I couldn't turn that into a change. The buttons above will do it."
                return
            }
            interpretation = suggestion.explanation
            apply(parsed)
        } catch {
            let coachError = error as? CoachError
            failure = coachError?.errorDescription
                ?? "Couldn't work that out. The buttons above will do it."
        }
    }
}
