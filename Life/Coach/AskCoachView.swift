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
    @State private var state: State = .idle
    @State private var showConsent = false
    @FocusState private var inputFocused: Bool

    private var service: CoachService { CoachService() }
    private var settings: CoachSettings { appState.coachSettings }

    private var context: CoachContext {
        CoachContextBuilder.build(appState: appState, permissions: .init(settings))
    }

    struct Turn: Identifiable, Equatable {
        enum Speaker { case you, coach }
        let id = UUID()
        var speaker: Speaker
        var text: String
    }

    enum State: Equatable {
        case idle
        case thinking
        /// Carries what to say and whether trying again is worth it — an
        /// offline failure deserves a Retry, a spend ceiling does not.
        case failed(message: String, retryable: Bool)
    }

    /// Starting points, so an empty box isn't the first thing you meet.
    private let prompts = [
        "How did I sleep this week?",
        "Should I train today?",
        "What should I focus on?",
        "Why is my recovery low?"
    ]

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
                        TurnBubble(turn: turn).id(turn.id)
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
                turns.append(Turn(speaker: .coach, text: answer))
                state = .idle
            } catch {
                let coachError = error as? CoachError
                state = .failed(
                    message: coachError?.errorDescription ?? "Couldn't reach the coach.",
                    // Retrying a spend ceiling or a switched-off feature just
                    // fails again in the same way; only a transport problem is
                    // worth a second go.
                    retryable: isRetryable(coachError)
                )
            }
        }
    }

    private func isRetryable(_ error: CoachError?) -> Bool {
        switch error {
        case .transport, .invalidResponse, .none: return true
        case .disabled, .notConfigured, .notSignedIn, .limitReached: return false
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
