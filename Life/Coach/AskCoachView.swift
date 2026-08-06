import SwiftUI

// MARK: - Ask Coach

/// A short conversation with the coach about your own data.
///
/// Notably *not* backed by the local rules. Everywhere else in this feature a
/// failure falls back to something deterministic, because a card that has to
/// show one suggestion is better off showing a plain one than an error. A
/// question is different: the rules can recommend an action but they cannot
/// answer "why was my sleep worse this week", and inventing an answer would be
/// far worse than admitting the coach couldn't reach anything.
struct AskCoachView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var turns: [Turn] = []
    @State private var state: AskState = .idle
    @State private var showConsent = false
    /// Set by a `buildWorkout` proposal. Non-nil presents the builder; the
    /// builder itself writes nothing until its own confirm button is pressed.
    @State private var builderBrief: WorkoutBrief?
    @FocusState private var inputFocused: Bool

    private var service: CoachService { CoachService() }
    private var settings: CoachSettings { appState.coachSettings }

    /// The same snapshot Today and the briefing are reading.
    ///
    /// This is the fix for "Today shows 10h 17m, Ask Coach is told 471
    /// minutes". Both figures were right; they were built by two different
    /// pieces of code from two different reads of the store, and only one of
    /// them formatted the result.
    private var snapshot: HealthSnapshot { appState.healthSnapshot }

    private var context: CoachContext {
        CoachContextBuilder.build(
            appState: appState,
            permissions: .init(settings),
            snapshot: snapshot
        )
    }

    struct Turn: Identifiable, Equatable {
        enum Speaker { case you, coach }
        let id = UUID()
        var speaker: Speaker
        var text: String
        /// Changes the coach offered to make. Buttons, not instructions —
        /// nothing here happens until it is tapped.
        var proposals: [CoachProposal] = []
        /// What tapping one did, once it has been tapped. Keyed by proposal id
        /// so an applied offer becomes a confirmation in place rather than
        /// vanishing, which would leave no record that anything happened.
        var applied: [String: String] = [:]
    }

    /// Deliberately not called `State`. A nested type of that name shadows
    /// SwiftUI's `@State` property wrapper inside this view, so every
    /// `@State var` in the file stops compiling with a message that points at
    /// the wrapper rather than at the enum that broke it.
    enum AskState: Equatable {
        case idle
        case thinking
        /// Carries what to say and whether trying again is worth it — an
        /// offline failure deserves a Retry, a spend ceiling does not.
        case failed(message: String, retryable: Bool)
    }

    /// Starting points, so an empty box isn't the first thing you meet — and
    /// only ones the data on hand can actually answer.
    ///
    /// The previous set promised more than the context held. "How did I sleep
    /// this week?" was offered to someone whose payload contains exactly one
    /// night and no weekly comparison, so the honest answer was always "I can't
    /// tell you that" — from a button the app itself had put there. "Why is my
    /// recovery low?" presupposed the answer, and fired happily on a day when
    /// recovery was fine or not yet measurable.
    ///
    /// Each prompt below is gated on the field that would have to be present for
    /// it to be answerable, so a suggestion appearing is itself a promise the
    /// app can keep.
    private var prompts: [String] {
        var out = ["What is the best use of my next 30 minutes?"]

        out.append("Is today's data complete enough to guide training?")

        if snapshot.sleepScore.state.hasValue {
            out.append("Explain my sleep score in plain English.")
        }
        if snapshot.sleepChangeSinceYesterdayMinutes != nil
            || snapshot.stepsChangeSinceYesterday != nil
            || snapshot.restingHeartRateChangeSinceYesterday != nil {
            out.append("Which figure changed most since yesterday?")
        }

        out.append("What information is missing from today's advice?")
        return out
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                Divider()
                composer
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Ask Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            turns.removeAll()
                            state = .idle
                        } label: {
                            Label("Clear conversation", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Conversation options")
                }
            }
            .sheet(isPresented: $showConsent) {
                CoachConsentView()
            }
            .sheet(item: $builderBrief) { brief in
                WorkoutPreviewSheet(initialBrief: brief, initialKind: .workout)
            }
        }
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    disclaimer

                    if turns.isEmpty {
                        suggestions
                    }

                    ForEach(turns) { turn in
                        VStack(alignment: .leading, spacing: 8) {
                            TurnBubble(turn: turn)
                            if !turn.proposals.isEmpty {
                                proposalList(for: turn)
                            }
                        }
                        .id(turn.id)
                    }

                    if state == .thinking {
                        thinkingRow
                    }

                    if case .failed(let message, let retryable) = state {
                        failureRow(message: message, retryable: retryable)
                    }
                }
                .padding(16)
            }
            .onChange(of: turns.count) { _, _ in
                if let last = turns.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("General wellbeing guidance from your own data — not medical advice. The coach can't diagnose anything.")
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.tertiarySystemFill).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            ForEach(prompts, id: \.self) { prompt in
                Button {
                    draft = prompt
                    send()
                } label: {
                    HStack {
                        Text(prompt)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Asks this question")
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Thinking…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thinking")
    }

    @ViewBuilder
    private func failureRow(message: String, retryable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if retryable {
                    Button("Try again") { retry() }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(AppTheme.primary)
                }
                if !settings.mayUseCloud {
                    Button("Turn on AI coaching") { showConsent = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(AppTheme.primary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask about your data…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("Your question")

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? AnyShapeStyle(AppTheme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send question")
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state != .thinking
    }

    // MARK: Actions

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        draft = ""
        inputFocused = false
        turns.append(Turn(speaker: .you, text: question))
        ask(question)
    }

    private func retry() {
        guard let last = turns.last(where: { $0.speaker == .you }) else { return }
        ask(last.text)
    }

    private func ask(_ question: String) {
        state = .thinking
        Task {
            do {
                let answer = try await service.ask(question, context: context, settings: settings)
                turns.append(
                    Turn(
                        speaker: .coach,
                        text: answer.text,
                        // Filtered before anything is drawn. A proposal naming
                        // a task that doesn't exist is dropped rather than
                        // shown and then failed on tap.
                        proposals: CoachActions.usable(answer.proposals, appState: appState)
                    )
                )
                state = .idle
            } catch {
                let coachError = error as? CoachError
                state = .failed(
                    message: coachError?.errorDescription ?? "Couldn't reach the coach.",
                    // Retrying a spend ceiling or a switched-off feature just
                    // fails again in the same way; only a transport problem is
                    // worth a second go.
                    retryable: CoachService.isRetryable(coachError)
                )
            }
        }
    }

    // MARK: Proposals

    /// The changes on offer, as buttons.
    ///
    /// Each one performs exactly what its label says and nothing else, and
    /// turns into a plain confirmation once used — so the conversation keeps a
    /// record of what was done rather than a button that looks pressable and
    /// isn't.
    @ViewBuilder
    private func proposalList(for turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(turn.proposals) { proposal in
                if let outcome = turn.applied[proposal.id] {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .accessibilityHidden(true)
                        Text(outcome)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityElement(children: .combine)
                } else {
                    Button {
                        apply(proposal, in: turn)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: proposal.kind))
                                .font(.caption.weight(.semibold))
                                .accessibilityHidden(true)
                            Text(proposal.label)
                                .font(.footnote.weight(.semibold))
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(AppTheme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.primary.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Makes this change. Nothing is changed until you tap.")
                }
            }
        }
        .padding(.trailing, 40)
    }

    private func icon(for kind: CoachProposalKind) -> String {
        switch kind {
        case .addTask:      return "plus.circle"
        case .completeTask: return "checkmark.circle"
        case .addHabitLog:  return "flame"
        case .logWater:     return "drop"
        case .planWorkout:  return "dumbbell"
        case .buildWorkout: return "sparkles"
        }
    }

    private func apply(_ proposal: CoachProposal, in turn: Turn) {
        guard let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
        switch CoachActions.perform(proposal, appState: appState) {
        case .changed(let outcome):
            turns[index].applied[proposal.id] = outcome
            HapticManager.success()

        case .opensBuilder(let brief):
            // No confirmation line, because nothing has been confirmed. The
            // button stays live so it can be tapped again if the sheet is
            // dismissed, which is the honest reading of "nothing happened".
            builderBrief = brief

        case .unavailable:
            // Valid when the answer arrived, gone by the time it was tapped —
            // completed on another device, most likely. Say so where the button
            // was rather than failing silently.
            turns[index].applied[proposal.id] = "That's no longer available."
        }
    }
}

// MARK: - Bubble

private struct TurnBubble: View {
    let turn: AskCoachView.Turn

    private var isYou: Bool { turn.speaker == .you }

    var body: some View {
        HStack {
            if isYou { Spacer(minLength: 40) }
            Text(turn.text)
                .font(.subheadline)
                .foregroundColor(isYou ? .white : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    if isYou {
                        AppTheme.brandGradient
                    } else {
                        AppTheme.cardBg
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !isYou { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isYou ? "You said: \(turn.text)" : "Coach said: \(turn.text)")
    }
}
