import SwiftUI

// MARK: - Machine Scan Sheet

/// Photograph a machine; get an exercise you can use.
///
/// The consent gate comes first, and it is its own decision. Someone who agreed
/// that Life may send their sleep score to a coach has not thereby agreed that
/// it may send photographs of where they are — those are different kinds of
/// data and this asks separately.
struct MachineScanSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Where a confirmed exercise goes. Nil means "just add it to my library".
    var onIdentified: ((Exercise) -> Void)?

    @State private var stage: Stage = .intro
    @State private var draftName = ""
    @State private var draftMuscle: BlueprintMuscle = .chest
    @State private var draftEquipment: ExerciseEquipment = .machine
    @State private var showConsent = false

    private var settings: CoachSettings { appState.coachSettings }
    private var service: MachineScanService { MachineScanService() }

    enum Stage: Equatable {
        /// Explains what happens before the camera opens.
        case intro
        case capturing
        case identifying
        case matched(Exercise, Int)
        case drafting(MachineIdentification)
        case failed(message: String, retryable: Bool)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .intro:                      intro
                case .capturing:                  camera
                case .identifying:                identifying
                case .matched(let e, let c):      matched(e, confidence: c)
                case .drafting(let id):           drafting(id)
                case .failed(let m, let r):       failure(message: m, retryable: r)
                }
            }
            .background(AppTheme.pageBg)
            .navigationTitle("Scan a machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if stage != .capturing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showConsent) {
                CoachConsentView()
            }
        }
    }

    // MARK: Intro and consent

    /// Says what will happen before it happens.
    ///
    /// Not a formality. This is the only feature in the app that sends an image
    /// anywhere, and someone should be able to decline it without declining
    /// coaching altogether.
    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.trainAccent)
                    Text("Point your camera at a machine and Life will work out what it's for.")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    point("photo", "The photo is sent to Gemini once, to recognise the equipment.")
                    point("trash", "It isn't saved to your device, your account, or any log.")
                    point("checkmark.shield", "If it matches something in your library, you'll get that. If it doesn't, you'll get a form to check before anything is added.")
                }

                if !settings.mayUseCloud {
                    // Was a dead end: it named Settings and offered no way to
                    // get there, so the only route out of this screen was to
                    // close it, find the right settings section and come back.
                    // The consent screen is the same one Settings presents.
                    VStack(alignment: .leading, spacing: 12) {
                        warning("Recognising a machine needs AI coaching, which is switched off.")
                        Button {
                            showConsent = true
                        } label: {
                            Text("Turn on AI coaching")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.brandGradient)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                } else if !settings.allowMachineScanning {
                    Button {
                        appState.setCoachSettings { $0.allowMachineScanning = true }
                        stage = .capturing
                    } label: {
                        Text("Allow photos and continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.brandGradient)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                } else {
                    Button {
                        stage = .capturing
                    } label: {
                        Text("Take a photo")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppTheme.brandGradient)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                }

                if settings.allowMachineScanning {
                    Button("Stop allowing photos") {
                        appState.setCoachSettings { $0.allowMachineScanning = false }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.trainAccent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Camera

    private var camera: some View {
        MachineCameraPicker(
            onCapture: { image in Task { await identify(image) } },
            onCancel: { stage = .intro }
        )
        .ignoresSafeArea()
    }

    private var identifying: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Working out what that is…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Matched

    private func matched(_ exercise: Exercise, confidence: Int) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    resultHeader(
                        title: exercise.name,
                        subtitle: "\(exercise.muscle) · \(exercise.equipment.label)",
                        note: "Already in your library."
                    )
                    confidenceRow(confidence)
                }
                .padding(20)
            }

            confirmBar(title: onIdentified == nil ? "Done" : "Add to workout") {
                onIdentified?(exercise)
                dismiss()
            }
        }
    }

    // MARK: Drafting

    /// A form, prefilled — not a record.
    ///
    /// This is the only place model output can become a permanent row in the
    /// exercise library, and it does so through a field the user can edit and a
    /// button they have to press. `ImportRoutineSheet` appends mid-parse with no
    /// confirmation; this deliberately doesn't.
    private func drafting(_ identification: MachineIdentification) -> some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draftName)
                    Picker("Muscle", selection: $draftMuscle) {
                        ForEach(BlueprintMuscle.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Picker("Equipment", selection: $draftEquipment) {
                        ForEach(ExerciseEquipment.allCases) {
                            Text($0.label).tag($0)
                        }
                    }
                } header: {
                    Text("Nothing like this in your library")
                } footer: {
                    Text("Check these before adding. It'll be saved as one of your own exercises, and you can edit or delete it later.")
                }

                Section {
                    confidenceRow(identification.confidence)
                        .listRowBackground(Color.clear)
                }
            }

            confirmBar(
                title: "Add to my exercises",
                enabled: !draftName.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                var exercise = MachineMatcher.draftExercise(from: identification)
                exercise.name = draftName.trimmingCharacters(in: .whitespaces)
                exercise.muscle = draftMuscle.rawValue
                exercise.equipment = draftEquipment
                appState.addCustomExercise(
                    name: exercise.name,
                    muscle: exercise.muscle,
                    kind: exercise.kind,
                    equipment: exercise.equipment,
                    movementType: exercise.movementType
                )
                // The id the store generated, not the draft's — the draft was
                // only ever a suggestion for this form.
                if let saved = appState.exercises.last { onIdentified?(saved) }
                dismiss()
            }
        }
    }

    // MARK: Failure

    private func failure(message: String, retryable: Bool) -> some View {
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
                Button("Try another photo") { stage = .capturing }
                    .buttonStyle(.borderedProminent)
            }
            Button("Add it by hand instead") {
                stage = .drafting(
                    MachineIdentification(name: "", muscle: .chest, equipment: .machine, confidence: 0)
                )
                draftName = ""
                draftMuscle = .chest
                draftEquipment = .machine
            }
            .font(.subheadline)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Shared

    private func resultHeader(title: String, subtitle: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(note)
                .font(.caption)
                .foregroundColor(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Shown rather than used as a threshold.
    ///
    /// Silently discarding a low-confidence answer would look like the scan
    /// failed. "I think this is a lat pulldown, but I'm not sure" is a more
    /// useful thing to put in front of someone who is standing next to it and
    /// can check.
    private func confidenceRow(_ confidence: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: confidence >= 70 ? "checkmark.circle" : "questionmark.circle")
                .font(.caption)
                .accessibilityHidden(true)
            Text(confidence >= 70 ? "Confident about this" : "Not certain — worth checking")
                .font(.caption)
        }
        .foregroundColor(confidence >= 70 ? .secondary : .orange)
        .accessibilityElement(children: .combine)
    }

    private func confirmBar(
        title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
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
        .padding(16)
        .background(.regularMaterial)
    }

    // MARK: Actions

    private func identify(_ image: UIImage) async {
        stage = .identifying
        do {
            let identification = try await service.identify(image: image, settings: settings)
            switch MachineMatcher.match(identification, library: appState.exercises) {
            case .matched(let exercise):
                stage = .matched(exercise, identification.confidence)
            case .draft(let draft):
                draftName = draft.name
                draftMuscle = draft.muscle
                draftEquipment = draft.equipment
                stage = .drafting(draft)
            }
        } catch {
            let coachError = error as? CoachError
            stage = .failed(
                message: coachError?.errorDescription ?? "Couldn't identify that.",
                retryable: CoachService.isRetryable(coachError)
            )
        }
    }
}
