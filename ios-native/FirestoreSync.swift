import FirebaseFirestore
import Foundation

// MARK: - Firestore Sync
// Persists the entire StateSnapshot as a JSON string under:
//   /users/{uid}/state/snapshot  →  { "json": "...", "updatedAt": Timestamp }
// Using a single JSON blob avoids Firestore type-mapping issues with nested
// arrays and optional fields.

final class FirestoreSync {
    static let shared = FirestoreSync()
    private let db = Firestore.firestore()
    private var debounceWork: DispatchWorkItem?

    // MARK: Upload (debounced 2s so rapid mutations don't spam Firestore)

    func scheduleUpload(_ snapshot: StateSnapshot, userId: String) {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.upload(snapshot, userId: userId)
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    // MARK: Download

    func download(userId: String) async throws -> StateSnapshot? {
        let ref = db.collection("users").document(userId)
            .collection("state").document("snapshot")
        let doc = try await ref.getDocument()
        guard doc.exists,
              let json = doc.data()?["json"] as? String,
              let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StateSnapshot.self, from: data)
    }

    // MARK: Private

    private func upload(_ snapshot: StateSnapshot, userId: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        db.collection("users").document(userId)
            .collection("state").document("snapshot")
            .setData(["json": json, "updatedAt": FieldValue.serverTimestamp()]) { _ in }
    }
}
