import FirebaseFirestore
import Foundation

// MARK: - Firestore Sync
//
// Persists the entire StateSnapshot as a JSON string under:
//   /users/{uid}/state/snapshot  →  {
//     "json": "...",                  // encoded StateSnapshot
//     "updatedAt": <serverTimestamp>, // authoritative server time
//     "clientUpdatedAt": <Timestamp>, // for client-side merge heuristics
//     "schemaVersion": Int            // payload schema; bump on breaking change
//   }
//
// The JSON-blob approach trades server-side queries / partial updates for
// dead-simple type fidelity (Codable round-trips exactly). Moving to typed
// per-domain documents is a future migration when multi-device merging
// becomes a hard requirement.

/// Errors surfaced to the UI through `onUploadCompletion`.
enum SyncError: LocalizedError {
    case encodeFailed
    case payloadTooLarge(bytes: Int)
    case timeout

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Couldn't encode local data for sync."
        case .payloadTooLarge(let bytes):
            return "Your data is too large to sync (\(bytes / 1024) KB of 1024 KB). Consider deleting old workouts or progress photos."
        case .timeout:
            return "Sync timed out. Check your network connection."
        }
    }
}

final class FirestoreSync {
    static let shared = FirestoreSync()

    // Bump when the on-disk shape of StateSnapshot changes in a breaking way.
    static let schemaVersion: Int = 1

    /// Lazy so the Firestore singleton isn't touched until the first actual
    /// upload/download call. This matters because `FirestoreSync.shared` may
    /// be referenced (e.g. from `AppState.init()` to wire the completion
    /// callback) *before* `FirebaseApp.configure()` runs in `LifeApp.init()`.
    /// `@State` default expressions initialise before the App's init body.
    private lazy var db: Firestore = Firestore.firestore()

    /// Serial queue protecting debounce state so callers from any thread
    /// (HealthKit completions, location updates) can't race the timer.
    private let queue = DispatchQueue(label: "uk.co.prolineroofingandsolar.life.FirestoreSync")
    private var debounceWork: DispatchWorkItem?

    /// Reused so JSONEncoder/Decoder setup is consistent and not re-built on
    /// every call (hot path during typing into a text field).
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Called on the main queue after every upload attempt (success or
    /// failure). AppState wires this into its `syncState` so the UI can show
    /// a banner instead of silently dropping data.
    var onUploadCompletion: ((Result<Date, Error>) -> Void)?

    private init() {}

    // MARK: - Upload (debounced 2s)

    func scheduleUpload(_ snapshot: StateSnapshot, userId: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.upload(snapshot, userId: userId)
            }
            self.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    /// Cancel any queued upload. Call on sign-out so a debounced write from
    /// the previous session can't fire after the user has switched accounts
    /// (or signed out entirely) and leak data into the wrong document.
    func cancelPending() {
        queue.async { [weak self] in
            self?.debounceWork?.cancel()
            self?.debounceWork = nil
        }
    }

    // MARK: - Download

    func download(userId: String) async throws -> StateSnapshot? {
        let ref = db.collection("users").document(userId)
            .collection("state").document("snapshot")

        // `.server` bypasses the local cache on first sign-in so a stale cache
        // can't trick us into thinking the cloud is empty and uploading local
        // data over real cloud data.
        let doc = try await ref.getDocument(source: .server)

        guard doc.exists,
              let json = doc.data()?["json"] as? String,
              let data = json.data(using: .utf8) else { return nil }

        return try Self.decoder.decode(StateSnapshot.self, from: data)
    }

    // MARK: - Private

    private func upload(_ snapshot: StateSnapshot, userId: String) {
        let report: (Result<Date, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.onUploadCompletion?(result)
            }
        }

        guard let data = try? Self.encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            report(.failure(SyncError.encodeFailed))
            return
        }

        // Firestore caps a single document at 1 MiB. Bail before the network
        // call with a clear error so the UI can prompt the user instead of
        // failing silently on the server side.
        if data.count > 900_000 {
            report(.failure(SyncError.payloadTooLarge(bytes: data.count)))
            return
        }

        let payload: [String: Any] = [
            "json": json,
            "updatedAt": FieldValue.serverTimestamp(),
            "clientUpdatedAt": Timestamp(date: Date()),
            "schemaVersion": Self.schemaVersion
        ]

        // `merge: true` protects fields written by a future schema version
        // (or a sibling document type) from being silently wiped by an
        // older client.
        db.collection("users").document(userId)
            .collection("state").document("snapshot")
            .setData(payload, merge: true) { error in
                if let error {
                    report(.failure(error))
                } else {
                    report(.success(Date()))
                }
            }
    }
}
