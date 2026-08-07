import SwiftUI

// MARK: - Reschedule Sheet

/// Tuesday's session didn't happen. Here are the days that could take it.
///
/// The options are generated deterministically by `RescheduleEngine` — free
/// days only, with a warning where a move would put the same muscles on
/// back-to-back days. Nothing moves until one is tapped, and "leave it" is
/// offered with the same weight as the moves, because carrying on is often the
/// right answer and an app that only offers rearrangements is nagging.
struct RescheduleSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let missed: PlannedSession

    @State private var confirmation: String?

    private var options: [RescheduleEngine.Option] {
        RescheduleEngine.options(
            for: missed,
            context: RescheduleEngine.Context(
                planned: appState.plannedSessions,
                musclesByRoutine: musclesByRoutine
            )
        )
    }

    /// Which blueprint muscles each routine trains, for the consecutive-day
    /// guardrail. Built here because the engine is pure and holds no store.
    private var musclesByRoutine: [String: Set<BlueprintMuscle>] {
        var out: [String: Set<BlueprintMuscle>] = [:]
        for routine in appState.routines {
            var muscles = Set<BlueprintMuscle>()
            for item in routine.exercises {
                guard let exercise = appState.exercises.first(where: { $0.id == item.exerciseId }),
                      let muscle = BlueprintMuscle(appMuscle: exercise.muscle) else { continue }
                muscles.insert(muscle)
            }
            out[routine.id] = muscles
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let confirmation {
                        Text(confirmation)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(options) { option in
                            optionRow(option)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Missed session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(missed.routineName)
                .font(.title3.weight(.bold))
            Text("Planned for \(missed.date.formatted(date: .abbreviated, time: .omitted)) and not done.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            if RescheduleEngine.isStale(missed) {
                Text("That was over a week ago — moving it now adds a session to this week rather than saving last week's.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func optionRow(_ option: RescheduleEngine.Option) -> some View {
        switch option {
        case .moveTo(let date, let note, let warning):
            row(
                icon: "calendar",
                title: "Move to \(note)",
                subtitle: warning ?? date.formatted(date: .abbreviated, time: .omitted),
                isWarning: warning != nil
            ) {
                move(to: date)
            }

        case .skip:
            row(
                icon: "xmark.circle",
                title: "Skip it",
                subtitle: "Take the week as it went and carry on.",
                isWarning: false
            ) {
                skip()
            }

        case .keep:
            row(
                icon: "checkmark.circle",
                title: "Leave everything as it is",
                subtitle: "The plan is fine. The week wasn't.",
                isWarning: false
            ) {
                dismiss()
            }
        }
    }

    private func row(
        icon: String,
        title: String,
        subtitle: String,
        isWarning: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isWarning ? .orange : AppTheme.trainAccent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isWarning ? .orange : .secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// The only two writes in this file, both behind a tap.
    private func move(to date: Date) {
        guard let index = appState.plannedSessions.firstIndex(where: { $0.id == missed.id }) else {
            dismiss()
            return
        }
        appState.plannedSessions[index].date = date
        appState.save()
        HapticManager.success()
        confirmation = "Moved to \(date.formatted(date: .abbreviated, time: .omitted))."
    }

    private func skip() {
        appState.plannedSessions.removeAll { $0.id == missed.id }
        appState.save()
        HapticManager.impact(.light)
        confirmation = "Skipped. Nothing else moved."
    }
}
