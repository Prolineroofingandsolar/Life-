import SwiftUI
import AVFoundation
import FirebaseAuth
import UIKit

// MARK: - Machine Scanner

/// Photograph a machine, get an exercise.
///
/// **This is the only place in the app where an image leaves the device, and
/// the only place where model output can become a permanent record.** Both are
/// deliberate, both are narrow, and both are gated:
///
/// - The photo is captured, sent, and discarded. It is never written to disk,
///   never attached to a Firestore document, never logged.
/// - A match against the existing library is offered as a match. A *miss*
///   produces a prefilled draft the user edits and confirms — it never writes an
///   `Exercise` on its own.
///
/// That second rule is what separates this from `ImportRoutineSheet`, which
/// appends a custom exercise mid-parse with no confirmation. Here the tap is the
/// writer, as everywhere else. And the workout *generator* still cannot create
/// exercises at all; only this flow can, and only from a photograph the user
/// chose to take.

/// What the model is allowed to say about a machine.
///
/// Closed enums, the same vocabulary as `WorkoutBlueprint`. A name is the one
/// free-text field, and it is only ever used to *populate a form the user
/// reviews* — never to resolve against the library by string.
struct MachineIdentification: Codable, Equatable, Sendable {
    var name: String
    var muscle: BlueprintMuscle
    var equipment: ExerciseEquipment
    var movementType: MovementType
    /// The model's own confidence. Shown to the user rather than used as a
    /// threshold — "I think this is a lat pulldown" is a useful sentence, and
    /// silently discarding a low-confidence answer would just look broken.
    var confidence: Int

    enum CodingKeys: String, CodingKey {
        case name, muscle, equipment, movementType, confidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)

        let rawMuscle = try c.decode(String.self, forKey: .muscle)
        guard let muscle = BlueprintMuscle(rawValue: rawMuscle) else {
            throw BlueprintError.unsupportedValue(field: "muscle", value: rawMuscle)
        }
        self.muscle = muscle

        let rawEquipment = try c.decode(String.self, forKey: .equipment)
        guard let equipment = ExerciseEquipment(rawValue: rawEquipment) else {
            throw BlueprintError.unsupportedValue(field: "equipment", value: rawEquipment)
        }
        self.equipment = equipment

        let rawMovement = try c.decodeIfPresent(String.self, forKey: .movementType) ?? "compound"
        guard let movement = MovementType(rawValue: rawMovement) else {
            throw BlueprintError.unsupportedValue(field: "movementType", value: rawMovement)
        }
        self.movementType = movement

        confidence = try c.decodeIfPresent(Int.self, forKey: .confidence) ?? 50
    }

    init(
        name: String,
        muscle: BlueprintMuscle,
        equipment: ExerciseEquipment,
        movementType: MovementType = .compound,
        confidence: Int = 50
    ) {
        self.name = name
        self.muscle = muscle
        self.equipment = equipment
        self.movementType = movementType
        self.confidence = confidence
    }
}

// MARK: - Matching

/// Turns an identification into either a library exercise or a draft.
///
/// Pure and `nonisolated`, so the matching rules are testable without a camera.
enum MachineMatcher {

    enum Outcome: Equatable {
        /// Found something already in the library.
        case matched(Exercise)
        /// Nothing close enough. The draft is a *suggestion for a form*, not a
        /// record — nothing is created until the user confirms it.
        case draft(MachineIdentification)
    }

    /// Matches on name first, then on muscle *and* equipment together.
    ///
    /// Muscle alone is far too loose — every chest machine would match the bench
    /// press. Requiring equipment as well means a "chest, machine" answer finds
    /// the chest press and not the barbell bench, which is the distinction the
    /// scan exists to make.
    static func match(_ identification: MachineIdentification, library: [Exercise]) -> Outcome {
        let target = normalised(identification.name)

        if let exact = library.first(where: { normalised($0.name) == target }) {
            return .matched(exact)
        }

        // A containment match, but only in the direction that is safe: a library
        // name contained in the scanned name ("Lat Pulldown" inside "Cable Lat
        // Pulldown Machine"). The reverse would let "Row" match "Barbell Row",
        // "Cable Row" and "Seated Row" indiscriminately.
        let contained = library.filter { candidate in
            let name = normalised(candidate.name)
            return name.count >= 6 && target.contains(name)
        }
        if let best = contained.max(by: { normalised($0.name).count < normalised($1.name).count }) {
            return .matched(best)
        }

        let byShape = library.filter { candidate in
            candidate.muscle.caseInsensitiveCompare(identification.muscle.rawValue) == .orderedSame
                && candidate.equipment == identification.equipment
        }
        if byShape.count == 1, let only = byShape.first {
            // Exactly one candidate is a match. More than one is a guess, and a
            // guess here adds the wrong exercise to a workout.
            return .matched(only)
        }

        return .draft(identification)
    }

    /// Lowercased, punctuation stripped, whitespace collapsed.
    static func normalised(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The draft as an `Exercise`, ready for the user to edit.
    ///
    /// `isCustom` is always true, so an exercise that arrived by camera is
    /// permanently distinguishable from a seeded one.
    static func draftExercise(from identification: MachineIdentification) -> Exercise {
        var exercise = Exercise(
            name: identification.name.trimmingCharacters(in: .whitespacesAndNewlines),
            muscle: identification.muscle.rawValue,
            kind: identification.equipment == .bodyweight ? .bodyweight : .weight
        )
        exercise.isCustom = true
        exercise.equipment = identification.equipment
        exercise.movementType = identification.movementType
        exercise.difficulty = 2
        return exercise
    }
}

// MARK: - Service

/// Sends one photograph and gets one identification back.
@MainActor
final class MachineScanService {

    private let transport: CoachTransport
    private let usage: CoachUsage
    private let idTokenProvider: () async throws -> String?

    init(
        transport: CoachTransport = HTTPCoachTransport(),
        usage: CoachUsage? = nil,
        idTokenProvider: (() async throws -> String?)? = nil
    ) {
        self.transport = transport
        self.usage = usage ?? .shared
        self.idTokenProvider = idTokenProvider ?? {
            guard AuthManager.isFirebaseReady, let user = Auth.auth().currentUser else { return nil }
            return try await user.getIDToken()
        }
    }

    /// The largest image sent.
    ///
    /// A machine's name plate and general shape survive 1024px comfortably, and
    /// a full-resolution photograph is several megabytes of someone's gym on the
    /// wire for no additional accuracy.
    static let maximumDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.6

    func identify(
        image: UIImage,
        settings: CoachSettings
    ) async throws -> MachineIdentification {
        guard settings.enabled, settings.mayUseCloud else { throw CoachError.disabled }
        guard settings.allowMachineScanning else { throw CoachError.disabled }
        guard usage.canAffordCall() else {
            throw CoachError.limitReached("This month's AI limit has been reached.")
        }
        guard let idToken = try await idTokenProvider() else { throw CoachError.notSignedIn }

        guard let data = Self.encoded(image) else {
            throw CoachError.invalidResponse("couldn't read that photo")
        }

        // No context is sent with this one. The model needs to see a machine,
        // not the person's sleep — and a scan is the one call that has no reason
        // to carry health data at all.
        let body: [String: Any] = [
            "mode": "identifyExercise",
            "image": data.base64EncodedString(),
            "imageMimeType": "image/jpeg",
        ]

        let result = try await transport.send(body, idToken: idToken)

        if let usageInfo = result["usage"] as? [String: Any] {
            usage.record(
                promptTokens: coachUsageInteger(usageInfo["promptTokens"]),
                outputTokens: coachUsageInteger(usageInfo["outputTokens"]),
                cost: usageInfo["cost"] as? Double ?? 0
            )
        }

        if let ok = result["ok"] as? Bool, ok == false {
            throw CoachError.invalidResponse(result["reason"] as? String ?? "couldn't identify that")
        }

        guard let value = result["value"],
              let json = try? JSONSerialization.data(withJSONObject: value) else {
            throw CoachError.invalidResponse("no answer")
        }

        do {
            return try JSONDecoder().decode(MachineIdentification.self, from: json)
        } catch let error as BlueprintError {
            switch error {
            case .unsupportedValue(let field, let value):
                throw CoachError.invalidResponse("\(field) \"\(value)\" isn't one the app knows")
            }
        }
    }

    /// Downscaled and compressed before it leaves.
    static func encoded(_ image: UIImage) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maximumDimension / longest)
        let target = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: jpegQuality)
    }
}

// MARK: - Camera

/// A plain camera sheet.
///
/// `UIImagePickerController` rather than a custom `AVCaptureSession`: this needs
/// one still photograph, and the system camera already handles focus, exposure,
/// permission prompts and the retake flow that a hand-rolled preview would have
/// to reimplement badly.
struct MachineCameraPicker: UIViewControllerRepresentable {

    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    /// False in the simulator and on a device with no camera, so the caller can
    /// offer the photo library instead of presenting a black screen.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.isAvailable ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
