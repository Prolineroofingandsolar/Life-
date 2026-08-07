import SwiftUI

// MARK: - Workout Preview Sheet

/// Where a generated workout is reviewed, edited and confirmed.
///
/// Nothing this sheet displays has been saved. The draft lives in memory until
/// the confirm button is pressed, and that button is the only path from model
/// output to the user's data — see `WorkoutBuilderActions`.
///
/// Three things it insists on:
///
/// - **Every resolution note is shown.** "You have no calf exercises, so that
///   part was left out" is what stops someone wondering why they asked for
///   calves and got none. Swallowing those would make the resolver look
///   arbitrary.
/// - **Substituted equipment is badged, never hidden.** Someone who asked for
///   dumbbells asked for a reason.
/// - **The duration is the app's figure**, computed from the prescription, not
///   a number the model supplied and nobody can check.
struct WorkoutPreviewSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// What the sheet is for. A session and a programme share every stage
    /// except the shape of the result, so they share the sheet.
    enum Kind: String, CaseIterable, Identifiable {
        case workout, plan
        var id: String { rawValue }
        var label: String { self == .workout ? "Single session" : "Weekly programme" }
    }

    /// Prefilled when opened from a coach proposal, empty from Train.
    var initialBrief: WorkoutBrief = WorkoutBrief()
    var initialKind: Kind = .workout

    @State private var brief = WorkoutBrief()
    @State private var kind: Kind = .workout
    @State private var stage: Stage = .brief
    @State private var makeActive = false
    @State private var scheduleSessions = true
    @State private var confirmation: String?

    // The conversation.
    @State private var turns: [Turn] = []
    @State private var stepIndex = 0
    @State private var selectedChips: Set<String> = []
    @State private var draft = ""
    /// Built once when the sheet opens, not per render — it walks every
    /// finished session, and the conversation asks for it on each keystroke.
    @State private var digest = TrainingHistoryDigest.Digest.empty

    /// One line of the transcript.
    struct Turn: Identifiable, Equatable {
        enum Speaker { case coach, you }
        let id = UUID()
        var speaker: Speaker
        var text: String
        /// Smaller type under the question, when it needs a word of
        /// explanation to be answerable.
        var hint: String?
    }

    private var settings: CoachSettings { appState.coachSettings }
    private var service: WorkoutBuilderService { WorkoutBuilderService() }

    enum Stage: Equatable {
        case brief
        case building
        case workout(WorkoutResolver.ResolvedWorkout, CoachProvenance)
        case plan(WorkoutResolver.ResolvedPlan, CoachProvenance)
        /// Carries whether trying again could plausibly help — a spend ceiling
        /// fails identically on the second go.
        case failed(message: String, retryable: Bool)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .brief:                       conversation
                case .building:                    buildingState
                case .workout(let w, let p):       workoutPreview(w, provenance: p)
                case .plan(let plan, let p):       planPreview(plan, provenance: p)
                case .failed(let message, let r):  failureState(message: message, retryable: r)
                }
            }
            .background(AppTheme.pageBg)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            kind = initialKind
        }
    }

    private var navigationTitle: String {
        switch stage {
        case .brief, .building, .failed: return kind == .workout ? "Build a workout" : "Build a programme"
        case .workout:                   return "Your workout"
        case .plan:                      return "Your programme"
        }
    }

    // MARK: Brief — a conversation

    /// One question at a time, answered by tapping or typing.
    ///
    /// The app asks and Gemini builds. A model free to steer its own interview
    /// will sometimes finish without having asked what equipment you have —
    /// which is the one field `WorkoutResolver` cannot work without, and the
    /// difference between a programme you can do and a barbell plan for someone
    /// with a pair of dumbbells. A fixed script guarantees those arrive, and
    /// costs one model call at the end rather than one per turn.
    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(turns) { turn in
                            ChatBubble(turn: turn)
                                .id(turn.id)
                        }

                        if let step = currentStep {
                            answerControls(for: step)
                                .id("controls")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: turns.count) { _, _ in
                    withAnimation { proxy.scrollTo("controls", anchor: .bottom) }
                }
            }

            Divider()
            composer
        }
        .onAppear { startConversationIfNeeded() }
    }

    /// The questions worth asking, for this person.
    ///
    /// The history question is dropped when there is no usable history — asking
    /// someone on their first week whether to build around their training is a
    /// question with one true answer, and asking it anyway makes the app look
    /// like it isn't paying attention.
    private var script: [BuilderConversation.Kind] {
        let full = BuilderConversation.script(for: kind == .workout ? .workout : .plan)
        guard !digest.isUsable else { return full }
        return full.filter { $0 != .history }
    }

    private var currentStep: BuilderConversation.Step? {
        guard stepIndex < script.count else { return nil }
        return BuilderConversation.step(script[stepIndex], for: kind == .workout ? .workout : .plan)
    }

    @ViewBuilder
    private func answerControls(for step: BuilderConversation.Step) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !step.chips.isEmpty {
                ChipCloud(
                    chips: step.chips,
                    selected: selectedChips,
                    allowsMultiple: step.allowsMultipleChips
                ) { value in
                    HapticManager.selection()
                    if step.allowsMultipleChips {
                        if selectedChips.contains(value) {
                            selectedChips.remove(value)
                        } else {
                            selectedChips.insert(value)
                        }
                    } else {
                        selectedChips = [value]
                        advance()
                    }
                }
            }

            HStack(spacing: 14) {
                if step.allowsMultipleChips || step.chips.isEmpty {
                    Button(selectedChips.isEmpty && draft.isEmpty ? "Skip" : "Next") { advance() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.primary)
                } else if step.isSkippable {
                    Button("Skip") { advance() }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Available from the second question on. Someone who knows what
                // they want should not have to sit through the rest of the
                // interview to get it.
                if stepIndex > 0 {
                    Button("Just build it") { Task { await build() } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.primary)
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(composerPrompt, text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("Your answer")
                .disabled(currentStep?.allowsFreeText == false)

            Button {
                advance()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        draft.isEmpty || currentStep == nil
                            ? AnyShapeStyle(Color.secondary.opacity(0.4))
                            : AnyShapeStyle(AppTheme.brandGradient)
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.isEmpty || currentStep == nil)
            .accessibilityLabel("Send answer")
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private var composerPrompt: String {
        settings.mayUseCloud ? "Type an answer…" : "Type an answer — AI is off, so I'll use a template"
    }

    // MARK: Conversation flow

    private func startConversationIfNeeded() {
        guard turns.isEmpty else { return }
        digest = TrainingHistoryDigest.build(appState: appState)
        brief = initialBrief
        stepIndex = 0
        selectedChips = []

        turns = [
            Turn(speaker: .coach, text: kind == .workout
                 ? "Let's put today's session together. A few quick questions."
                 : "Let's build you a programme. A few quick questions.")
        ]

        // Opened from a coach proposal, the brief already carries what was asked
        // for. Shown back rather than silently applied: the questions are still
        // asked, so anyone who meant something else can say so before a session
        // is built on a paraphrase.
        let carried = brief.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !carried.isEmpty {
            turns.append(Turn(speaker: .coach, text: "You asked for: \(carried)"))
        }

        if let step = currentStep { ask(step) }
    }

    private func ask(_ step: BuilderConversation.Step) {
        turns.append(Turn(speaker: .coach, text: step.question, hint: step.hint))
    }

    /// Records the answer, says it back, and moves on.
    private func advance() {
        guard let step = currentStep else { return }

        let chips = Array(selectedChips)
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        // Echoed in the user's own words where they typed, and in the chip's
        // label where they tapped — so the transcript reads as what happened.
        let spoken = !text.isEmpty
            ? text
            : chips.compactMap { value in step.chips.first { $0.value == value }?.label }
                .sorted().joined(separator: ", ")

        if !spoken.isEmpty {
            turns.append(Turn(speaker: .you, text: spoken))
        } else if step.isSkippable {
            turns.append(Turn(speaker: .you, text: "Skip"))
        }

        BuilderConversation.apply(answer: text, chips: chips, for: step.kind, to: &brief)

        // Said back in the app's own words. This is how someone catches "45"
        // being read as 45 weeks before a programme is built on it.
        if !spoken.isEmpty, let ack = BuilderConversation.acknowledgement(for: step.kind, brief: brief) {
            turns.append(Turn(speaker: .coach, text: ack))
        }

        draft = ""
        selectedChips = []
        stepIndex += 1

        if let next = currentStep {
            ask(next)
        } else {
            Task { await build() }
        }
    }

    // MARK: Guardrails

    /// Programme-quality warnings, shown before the save button and never after.
    ///
    /// Calculated, not generated — `VolumeGuardrails` compares the proposed week
    /// against the user's own recent weeks. They do not block the save: these
    /// are observations about a programme, not medical limits, and the app has
    /// no standing to refuse someone their own training plan.
    @ViewBuilder
    private func guardrailsBlock(for plan: WorkoutResolver.ResolvedPlan) -> some View {
        let warnings = guardrailWarnings(for: plan)
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("WORTH KNOWING")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(warnings) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: warning.isSevere ? "exclamationmark.triangle" : "info.circle")
                            .font(.caption)
                            .foregroundColor(warning.isSevere ? .orange : .secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                        Text(warning.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    private func guardrailWarnings(for plan: WorkoutResolver.ResolvedPlan) -> [VolumeGuardrails.Warning] {
        let sessionsByKey = Dictionary(
            plan.sessions.map { ($0.key, $0.workout.items.map(\.prescription)) },
            uniquingKeysWith: { first, _ in first }
        )
        let weekly = Array(sessionsByKey.values)

        var byWeekday: [Int: [RoutineExercise]] = [:]
        for (weekday, key) in plan.schedule {
            byWeekday[weekday] = sessionsByKey[key] ?? []
        }

        let recent = VolumeGuardrails.recentWeeklySets(appState: appState)
        var targets: [String: ClosedRange<Int>] = [:]
        for status in MuscleRecoveryEngine.statuses(appState: appState) {
            guard let muscle = status.blueprintMuscle else { continue }
            targets[muscle.rawValue] = status.weeklyTarget
        }

        return VolumeGuardrails.check(
            proposedSets: VolumeGuardrails.weeklySets(in: weekly, library: appState.exercises),
            recentWeeklySets: recent.sets,
            weeksOfHistory: recent.weeks,
            targets: targets,
            focus: brief.focusMuscles,
            adjacentMuscles: VolumeGuardrails.adjacentHardMuscles(
                byWeekday: byWeekday,
                library: appState.exercises
            )
        )
    }

    // MARK: Building

    private var buildingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(settings.mayUseCloud ? "Asking Gemini…" : "Putting it together…")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("This takes a few seconds.")
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Failure

    private func failureState(message: String, retryable: Bool) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if retryable {
                Button("Try again") { Task { await build() } }
                    .buttonStyle(.borderedProminent)
            }
            Button("Change what I asked for") { stage = .brief }
                .font(.subheadline)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Workout preview

    private func workoutPreview(
        _ workout: WorkoutResolver.ResolvedWorkout,
        provenance: CoachProvenance
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryHeader(
                        title: workout.name,
                        subtitle: workout.focus,
                        detail: "\(workout.items.count) exercises · about \(workout.estimatedMinutes) min"
                    )

                    if workout.estimatedMinutes > brief.availableMinutes + 10 {
                        DataCaveatRow(
                            text: "This is about \(workout.estimatedMinutes) minutes, longer than the \(brief.availableMinutes) you asked for. Remove an exercise to bring it down."
                        )
                        .padding(.horizontal, 16)
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(workout.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 16) }
                            PreviewExerciseRow(item: item)
                        }
                    }
                    .background(AppTheme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    .padding(.horizontal, 16)

                    notesBlock(workout.notes)
                    CoachProvenanceLabel(provenance: provenance)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }

            confirmBar(
                title: "Save routine",
                enabled: WorkoutBuilderActions.isCommittable(workout, appState: appState),
                disabledReason: workout.isViable
                    ? nil
                    : "There aren't enough exercises in your library for this."
            ) {
                confirmation = WorkoutBuilderActions.commit(workout, appState: appState)
                finish()
            }
        }
    }

    // MARK: Plan preview

    private func planPreview(
        _ plan: WorkoutResolver.ResolvedPlan,
        provenance: CoachProvenance
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryHeader(
                        title: plan.name,
                        subtitle: plan.progression ?? "",
                        detail: "\(plan.schedule.count) days a week · \(plan.weeks) weeks"
                    )

                    WeekStrip(schedule: plan.schedule, sessions: plan.sessions)
                        .padding(.horizontal, 16)

                    ForEach(plan.sessions) { session in
                        DisclosureGroup {
                            VStack(spacing: 0) {
                                ForEach(Array(session.workout.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().padding(.leading, 16) }
                                    PreviewExerciseRow(item: item)
                                }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.workout.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(session.workout.items.count) exercises · about \(session.workout.estimatedMinutes) min")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(AppTheme.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    notesBlock(plan.notes)

                    guardrailsBlock(for: plan)

                    VStack(spacing: 0) {
                        Toggle("Make this my active programme", isOn: $makeActive)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        Divider().padding(.leading, 16)
                        Toggle(isOn: $scheduleSessions) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add to my calendar")
                                // Stated before the tap. "Adds 12 planned
                                // sessions" is the sort of thing people want to
                                // know in advance rather than discover.
                                Text("Adds \(min(plan.sessionCount, WorkoutBuilderActions.maximumPlannedSessions)) planned sessions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(AppTheme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                    .padding(.horizontal, 16)

                    if appState.activeProgram != nil && makeActive {
                        DataCaveatRow(
                            text: "“\(appState.activeProgram?.name ?? "")” will stop being your active programme. It isn't deleted."
                        )
                        .padding(.horizontal, 16)
                    }

                    CoachProvenanceLabel(provenance: provenance)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }

            confirmBar(
                title: "Create programme",
                enabled: WorkoutBuilderActions.isCommittable(plan, appState: appState),
                disabledReason: plan.isViable
                    ? nil
                    : "Some sessions don't have enough exercises in your library."
            ) {
                confirmation = WorkoutBuilderActions.commit(
                    plan,
                    appState: appState,
                    options: .init(makeActive: makeActive, scheduleSessions: scheduleSessions)
                )
                finish()
            }
        }
    }

    // MARK: Shared chrome

    private func summaryHeader(title: String, subtitle: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(detail)
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    /// Every note, never a summary of them.
    @ViewBuilder
    private func notesBlock(_ notes: [WorkoutResolver.ResolutionNote]) -> some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Worth knowing")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(notes) { note in
                    DataCaveatRow(text: note.description)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    /// One button, and when it's disabled it says why.
    private func confirmBar(
        title: String,
        enabled: Bool,
        disabledReason: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            if let disabledReason, !enabled {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                HapticManager.success()
                action()
            } label: {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(enabled ? AnyShapeStyle(AppTheme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.35)))
                    .clipShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!enabled)
            .accessibilityHint("Nothing is saved until you press this")
        }
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: Actions

    private func finish() {
        if confirmation != nil { HapticManager.success() }
        dismiss()
    }

    private func build() async {
        stage = .building

        // Attached at the last moment rather than during the interview, so the
        // answer to "start fresh" is honoured by simply never populating it.
        brief.historyText = brief.useHistory ? TrainingHistoryDigest.promptText(digest) : nil

        let context = CoachContextBuilder.build(
            appState: appState,
            permissions: .init(settings),
            snapshot: appState.healthSnapshot
        )
        let inputs = builderInputs()

        // Default the activation toggle from context rather than assuming.
        // Replacing an active programme is a decision; having none is not.
        makeActive = appState.activeProgram == nil

        do {
            switch kind {
            case .workout:
                let draft = try await service.buildWorkout(
                    brief: brief, context: context, settings: settings
                )
                stage = .workout(
                    WorkoutResolver.resolve(draft.blueprint, inputs: inputs),
                    draft.provenance
                )
            case .plan:
                let draft = try await service.buildPlan(
                    brief: brief, context: context, settings: settings
                )
                stage = .plan(
                    WorkoutResolver.resolve(draft.blueprint, inputs: inputs),
                    draft.provenance
                )
            }
        } catch {
            let coachError = error as? CoachError
            // The local template is the fallback, and it is labelled as one.
            // Showing an error where a usable programme could be is a worse
            // outcome than a plainer programme honestly described.
            if let local = LocalProgrammeTemplates.blueprint(for: brief, kind: kind) {
                let provenance = CoachProvenance(
                    origin: settings.mayUseCloud ? .offlineFallback : .onDevice,
                    generatedAt: Date(),
                    failureNote: settings.mayUseCloud ? coachError?.errorDescription : nil,
                    isRetryable: CoachService.isRetryable(coachError)
                )
                switch local {
                case .workout(let blueprint):
                    stage = .workout(WorkoutResolver.resolve(blueprint, inputs: inputs), provenance)
                case .plan(let blueprint):
                    stage = .plan(WorkoutResolver.resolve(blueprint, inputs: inputs), provenance)
                }
            } else {
                stage = .failed(
                    message: coachError?.errorDescription ?? "Couldn't build that just now.",
                    retryable: CoachService.isRetryable(coachError)
                )
            }
        }
    }

    private func builderInputs() -> WorkoutResolver.Inputs {
        WorkoutResolver.Inputs(
            library: appState.exercises,
            history: lastWorkingWeights(),
            favouriteIds: Set(appState.exercises.filter(\.isFavorite).map(\.id)),
            idsInExistingRoutines: Set(appState.routines.flatMap { $0.exercises.map(\.exerciseId) }),
            excludedMuscles: brief.avoidMuscles,
            availableEquipment: brief.availableEquipment
        )
    }

    /// The heaviest completed working set per exercise, from finished sessions.
    ///
    /// The one number the app can supply and the model cannot. Warm-ups are
    /// excluded — a 20 kg warm-up is not a starting weight.
    private func lastWorkingWeights() -> [String: Double] {
        var out: [String: Double] = [:]
        for session in appState.completedWorkouts.sorted(by: {
            ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast)
        }) {
            for exercise in session.exercises {
                let working = exercise.sets.filter { $0.done && !$0.isWarmup }.map(\.weight)
                guard let heaviest = working.max(), heaviest > 0 else { continue }
                out[exercise.exerciseId] = heaviest
            }
        }
        return out
    }
}

// MARK: - Rows

private struct PreviewExerciseRow: View {
    let item: WorkoutResolver.ResolvedItem

    private var prescriptionText: String {
        let p = item.prescription
        let reps = p.repRangeMin == p.repRangeMax
            ? "\(p.repRangeMin)"
            : "\(p.repRangeMin)–\(p.repRangeMax)"
        var text = "\(p.defaultSets) × \(reps)"
        if p.restSeconds > 0 { text += " · \(p.restSeconds)s rest" }
        if let rir = item.rir { text += " · \(rir) RIR" }
        return text
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.exercise.name)
                        .font(.subheadline.weight(.medium))
                    if item.substitutedEquipment {
                        // Never hidden. They asked for that equipment for a
                        // reason, and a silent swap is the sort of thing that
                        // makes the whole feature feel untrustworthy.
                        Text("closest match")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
                Text(prescriptionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if item.prescription.defaultWeight > 0 {
                    Text("Starting at \(item.prescription.defaultWeight.weightDisplay) kg, from your history")
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            Spacer(minLength: 0)
            Text(item.slotMuscle.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(item.exercise.name), \(prescriptionText)"
                + (item.substitutedEquipment ? ", closest match to what you asked for" : "")
        )
    }
}

/// The week at a glance, Monday first.
private struct WeekStrip: View {
    let schedule: [Int: String]
    let sessions: [WorkoutResolver.ResolvedPlanSession]

    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let key = schedule[weekday]
                VStack(spacing: 5) {
                    Text(labels[weekday - 1])
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(key == nil ? Color(.tertiarySystemFill) : AppTheme.primary.opacity(0.85))
                        .frame(height: 34)
                        .overlay {
                            if key != nil {
                                Image(systemName: "dumbbell.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    key == nil
                        ? "\(WorkoutBrief.weekdayName(weekday)), rest"
                        : "\(WorkoutBrief.weekdayName(weekday)), \(sessions.first { $0.key == key }?.workout.name ?? "training")"
                )
            }
        }
    }
}

/// One line of the transcript.
private struct ChatBubble: View {
    let turn: WorkoutPreviewSheet.Turn

    private var isYou: Bool { turn.speaker == .you }

    var body: some View {
        HStack {
            if isYou { Spacer(minLength: 40) }

            VStack(alignment: isYou ? .trailing : .leading, spacing: 3) {
                Text(turn.text)
                    .font(.subheadline)
                    .foregroundColor(isYou ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(isYou ? .trailing : .leading)

                if let hint = turn.hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundColor(isYou ? .white.opacity(0.85) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                if isYou { AppTheme.brandGradient } else { AppTheme.cardBg }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !isYou { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            (isYou ? "You said: " : "Coach: ") + turn.text + (turn.hint.map { ". \($0)" } ?? "")
        )
    }
}

/// The answer chips under a question.
private struct ChipCloud: View {
    let chips: [BuilderConversation.Chip]
    let selected: Set<String>
    let allowsMultiple: Bool
    let onTap: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(chips) { chip in
                let isOn = selected.contains(chip.value)
                Button { onTap(chip.value) } label: {
                    Text(chip.label)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(isOn ? .white : AppTheme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isOn ? AnyShapeStyle(AppTheme.primary) : AnyShapeStyle(AppTheme.primary.opacity(0.12)))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(chip.label)
                .accessibilityAddTraits(
                    allowsMultiple && isOn ? [.isButton, .isSelected] : [.isButton]
                )
            }
        }
    }
}
