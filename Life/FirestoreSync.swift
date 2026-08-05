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
    /// upload/download call. `FirestoreSync.shared` is referenced early — from
    /// `AppState.init()`, to wire the completion callback — and Firestore must
    /// not be built before Firebase is configured. Configuration now happens in
    /// `FirebaseBootstrap` on first ask, so this is defence in depth rather than
    /// the only thing holding the ordering together, and it still earns its
    /// place: uploads only ever run for a signed-in user, which can't happen
    /// until Firebase is up.
    private lazy var db: Firestore = Firestore.firestore()

    /// Serial queue protecting debounce state so callers from any thread
    /// (HealthKit completions, location updates) can't race the timer.
    private let queue = DispatchQueue(label: "uk.co.prolineroofingandsolar.life.FirestoreSync")
    private var debounceWork: DispatchWorkItem?

    /// The most recent snapshot handed to `scheduleUpload`, kept so a debounced
    /// write can be forced out early and so a failed upload has something to
    /// retry with.
    private var pendingSnapshot: (snapshot: StateSnapshot, userId: String)?

    /// How many times the current upload has been retried. Reset on success and
    /// whenever a newer snapshot arrives.
    private var retryCount = 0

    /// Increments every time a snapshot is queued, so an upload that finishes
    /// after a newer one was scheduled can tell it is no longer the current
    /// write and leave the queue alone.
    private var uploadSequence = 0

    /// A transient failure — no network on the train, a server hiccup — used to
    /// leave the change sitting in memory with nothing to send it later. The
    /// next save would have carried it, but "the next save" can be days away,
    /// and in the meantime the account is missing data the device believes it
    /// has already synced.
    private static let maxRetries = 5

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
            self.pendingSnapshot = (snapshot, userId)
            // A newer snapshot supersedes whatever was being retried, and gets
            // its own full budget of attempts.
            self.retryCount = 0
            self.uploadSequence += 1
            let sequence = self.uploadSequence
            let work = DispatchWorkItem { [weak self] in
                self?.upload(snapshot, userId: userId, sequence: sequence)
            }
            self.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    /// Send any queued upload immediately instead of waiting out the debounce.
    ///
    /// Called when the app leaves the foreground: the two-second debounce is
    /// there to coalesce typing, and the user swiping the app away shouldn't
    /// take the last two seconds of their work with it.
    func flushPending() {
        queue.async { [weak self] in
            guard let self, let pending = self.pendingSnapshot else { return }
            self.debounceWork?.cancel()
            self.debounceWork = nil
            self.upload(pending.snapshot, userId: pending.userId, sequence: self.uploadSequence)
        }
    }

    /// Cancel any queued upload. Call on sign-out so a debounced write from
    /// the previous session can't fire after the user has switched accounts
    /// (or signed out entirely) and leak data into the wrong document.
    func cancelPending() {
        queue.async { [weak self] in
            self?.debounceWork?.cancel()
            self?.debounceWork = nil
            self?.pendingSnapshot = nil
            self?.retryCount = 0
        }
    }

    // MARK: - Download

    /// A downloaded snapshot paired with the wall-clock time the uploading
    /// device wrote it, so the caller can decide whether it's actually newer
    /// than what's on disk locally before overwriting anything.
    struct DownloadedSnapshot {
        let snapshot: StateSnapshot
        let updatedAt: Date
    }

    func download(userId: String) async throws -> DownloadedSnapshot? {
        let ref = db.collection("users").document(userId)
            .collection("state").document("snapshot")

        // `.server` bypasses the local cache on first sign-in so a stale cache
        // can't trick us into thinking the cloud is empty and uploading local
        // data over real cloud data.
        let doc = try await ref.getDocument(source: .server)

        guard doc.exists,
              let json = doc.data()?["json"] as? String,
              let data = json.data(using: .utf8) else { return nil }

        let snapshot = try Self.decoder.decode(StateSnapshot.self, from: data)
        // `clientUpdatedAt` is written by the device that uploaded; fall back
        // to distantPast (never wins a "who's newer" comparison) if missing.
        let updatedAt = (doc.data()?["clientUpdatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        return DownloadedSnapshot(snapshot: snapshot, updatedAt: updatedAt)
    }

    // MARK: - Private

    private func upload(_ snapshot: StateSnapshot, userId: String, sequence: Int) {
        let report: (Result<Date, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.onUploadCompletion?(result)
            }
        }

        /// Failures that retrying can't fix. Clearing the pending snapshot
        /// stops every later flush re-attempting the same doomed write.
        let reportPermanent: (Error) -> Void = { [weak self] error in
            self?.queue.async {
                guard self?.uploadSequence == sequence else { return }
                self?.pendingSnapshot = nil
                self?.retryCount = 0
            }
            report(.failure(error))
        }

        guard let data = try? Self.encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            reportPermanent(SyncError.encodeFailed)
            return
        }

        // Firestore caps a single document at 1 MiB. Bail before the network
        // call with a clear error so the UI can prompt the user instead of
        // failing silently on the server side.
        if data.count > 900_000 {
            reportPermanent(SyncError.payloadTooLarge(bytes: data.count))
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
            .setData(payload, merge: true) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.scheduleRetry(
                        after: error, snapshot: snapshot, userId: userId,
                        sequence: sequence, report: report
                    )
                } else {
                    self.queue.async {
                        // Only clear the queue if nothing newer was scheduled
                        // while this write was in flight — otherwise the newer
                        // snapshot would lose its ability to be flushed early.
                        guard self.uploadSequence == sequence else { return }
                        self.pendingSnapshot = nil
                        self.retryCount = 0
                    }
                    report(.success(Date()))
                }
            }
    }

    /// Retries a failed upload with exponential backoff, giving up — and
    /// reporting — once the budget is spent.
    ///
    /// Only the reporting is deferred, not the data: `pendingSnapshot` still
    /// holds the change, so the next ordinary save picks it up regardless. The
    /// retry is what closes the gap when there is no next save for a while.
    private func scheduleRetry(
        after error: Error,
        snapshot: StateSnapshot,
        userId: String,
        sequence: Int,
        report: @escaping (Result<Date, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            // A newer snapshot arrived while this one was in flight; it will be
            // uploaded on its own schedule and supersedes this attempt.
            guard self.uploadSequence == sequence,
                  self.pendingSnapshot?.userId == userId else { return }

            guard self.retryCount < Self.maxRetries else {
                report(.failure(error))
                return
            }

            self.retryCount += 1
            // 2s, 4s, 8s, 16s, 32s.
            let delay = pow(2.0, Double(self.retryCount))
            let work = DispatchWorkItem { [weak self] in
                self?.upload(snapshot, userId: userId, sequence: sequence)
            }
            self.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
}
