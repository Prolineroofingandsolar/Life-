import Foundation
import SwiftUI
import CoreLocation
import UIKit

// MARK: - Persistence Keys

private enum PersistenceKey {
    static let appState = "life_app_state_v2"
    static let lastModified = "life_app_state_last_modified_v1"
    /// True once the user has changed anything on this device. See
    /// `AppState.hasLocalUserData`.
    static let hasUserData = "life_app_state_has_user_data_v1"
}

// MARK: - Planned Session

// `Equatable` and `Sendable` are additive: every stored property already
// conforms, nothing about decoding or syncing changes, and `AutomationOutcome`
// needs both to carry one.
struct PlannedSession: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var date: Date
    var routineId: String?
    var routineName: String
    var notes: String = ""
    var completed: Bool = false

    /// Whether this entry is a deliberately planned rest day.
    ///
    /// **Inferred rather than stored, and knowingly so.** The data model has no
    /// rest-day concept: a plan is a routine on a date, and there is no flag for
    /// "today is meant to be easy". Adding one would mean migrating every
    /// persisted plan and every synced snapshot, which is a large change to make
    /// for a label.
    ///
    /// So this reads a plan with no routine attached and a name that says rest.
    /// It is narrow on purpose — a plan pointing at a real routine is never a
    /// rest day however it is named — and it only ever changes wording, never
    /// behaviour. Today used to show "Rest" whenever no workout had been
    /// *completed*, which said the same thing about a planned rest day and a
    /// Tuesday with a hard session still ahead of it. This distinguishes the
    /// two without a migration; a stored flag would do it properly.
    var isRestDay: Bool {
        guard routineId == nil else { return false }
        let name = routineName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return name == "rest" || name == "rest day" || name == "recovery"
    }
}

// MARK: - Progress Photo (stored separately, not in cloud snapshot)

struct ProgressPhoto: Identifiable, Codable {
    var id: String = UUID().uuidString
    var date: Date
    var label: String
    var imageData: Data
}

// MARK: - Sync State

enum SyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case failed(String)
}

// MARK: - Serializable State Snapshot

struct StateSnapshot: Codable {
    var tasks: [AppTask] = []
    var taskLists: [TaskList] = []
    var bills: [Bill] = []
    var incomes: [Income] = []
    var oneOffExpenses: [OneOffExpense] = []
    var moneySettings: MoneySettings = MoneySettings()
    var habits: [Habit] = []
    var exercises: [Exercise] = []
    var routines: [Routine] = []
    var sessions: [WorkoutSession] = []
    var weightEntries: [WeightEntry] = []
    var bodyCompEntries: [BodyCompEntry] = []
    var bodyMeasurements: [BodyMeasurement] = []
    var achievements: [Achievement] = []
    var programs: [WorkoutProgram] = []
    var careDays: [String: CareDay] = [:]
    var careSettings: CareSettings = CareSettings()
    var workoutSettings: WorkoutSettings = WorkoutSettings()
    var userName: String = ""
    var visitedLocations: [VisitedLocation] = []
    var plannedSessions: [PlannedSession] = []
    var supplements: [Supplement] = []
    // Optional on purpose. Swift's synthesized `Codable` calls `decode` (not
    // `decodeIfPresent`) for non-optional properties, so a *missing* key throws
    // rather than falling back to the default value — and `load()` treats a
    // decode failure as "first launch" and seeds defaults. A non-optional field
    // added here would therefore wipe every save written before this version.
    // Optionals get `decodeIfPresent`, so old snapshots decode as nil and
    // `apply(snapshot:)` substitutes the default.
    var healthDays: [String: HealthDay]? = nil
    var healthSettings: HealthSettings? = nil
    var sleepNights: [String: SleepNight]? = nil
    /// Manually entered Google Health scores paired with our estimates.
    var sleepComparisons: [String: SleepScoreComparison]? = nil
    var coachSettings: CoachSettings? = nil
    /// What the app has learned about this person — see `TrainingMemory`.
    /// Optional for the same reason as everything above it.
    var coachFeedback: [CoachFeedbackEntry]? = nil

    init() {}

    /// Decode every persisted collection leniently. Default property values are
    /// not used by Swift's synthesised decoder when a key is absent, so adding a
    /// non-optional field used to make an older save look corrupt and trigger a
    /// first-launch reset.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([AppTask].self, forKey: .tasks) ?? []
        taskLists = try c.decodeIfPresent([TaskList].self, forKey: .taskLists) ?? []
        bills = try c.decodeIfPresent([Bill].self, forKey: .bills) ?? []
        incomes = try c.decodeIfPresent([Income].self, forKey: .incomes) ?? []
        oneOffExpenses = try c.decodeIfPresent([OneOffExpense].self, forKey: .oneOffExpenses) ?? []
        moneySettings = try c.decodeIfPresent(MoneySettings.self, forKey: .moneySettings) ?? MoneySettings()
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        exercises = try c.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        routines = try c.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        sessions = try c.decodeIfPresent([WorkoutSession].self, forKey: .sessions) ?? []
        weightEntries = try c.decodeIfPresent([WeightEntry].self, forKey: .weightEntries) ?? []
        bodyCompEntries = try c.decodeIfPresent([BodyCompEntry].self, forKey: .bodyCompEntries) ?? []
        bodyMeasurements = try c.decodeIfPresent([BodyMeasurement].self, forKey: .bodyMeasurements) ?? []
        achievements = try c.decodeIfPresent([Achievement].self, forKey: .achievements) ?? []
        programs = try c.decodeIfPresent([WorkoutProgram].self, forKey: .programs) ?? []
        careDays = try c.decodeIfPresent([String: CareDay].self, forKey: .careDays) ?? [:]
        careSettings = try c.decodeIfPresent(CareSettings.self, forKey: .careSettings) ?? CareSettings()
        workoutSettings = try c.decodeIfPresent(WorkoutSettings.self, forKey: .workoutSettings) ?? WorkoutSettings()
        userName = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        visitedLocations = try c.decodeIfPresent([VisitedLocation].self, forKey: .visitedLocations) ?? []
        plannedSessions = try c.decodeIfPresent([PlannedSession].self, forKey: .plannedSessions) ?? []
        supplements = try c.decodeIfPresent([Supplement].self, forKey: .supplements) ?? []
        healthDays = try c.decodeIfPresent([String: HealthDay].self, forKey: .healthDays)
        healthSettings = try c.decodeIfPresent(HealthSettings.self, forKey: .healthSettings)
        sleepNights = try c.decodeIfPresent([String: SleepNight].self, forKey: .sleepNights)
        sleepComparisons = try c.decodeIfPresent([String: SleepScoreComparison].self, forKey: .sleepComparisons)
        coachSettings = try c.decodeIfPresent(CoachSettings.self, forKey: .coachSettings)
        coachFeedback = try c.decodeIfPresent([CoachFeedbackEntry].self, forKey: .coachFeedback)
    }
}

// MARK: - Snapshot Merging

extension StateSnapshot {

    /// Combines two snapshots without discarding anything from either.
    ///
    /// Sign-in used to be a straight choice: whichever side had the later
    /// timestamp replaced the other outright. That loses data in both
    /// directions. Install the app on a new phone, log one workout before
    /// signing in, and local was "newer" — so a year of history in the cloud was
    /// overwritten by that single session. Sign in first instead and anything
    /// recorded offline on the old phone was thrown away.
    ///
    /// Nothing is deleted here. Records are unioned by id; where both sides hold
    /// the same id, `preferring` decides. Day-keyed health data merges field by
    /// field, because a day can legitimately be half-recorded on each device —
    /// steps synced on the phone, sleep synced on the tablet.
    ///
    /// The cost is that a record deleted on one device comes back if the other
    /// device still has it and hasn't synced since. That is the right trade:
    /// a resurrected workout is an annoyance the user can delete again, a
    /// deleted year of history is not recoverable.
    static func merged(preferring winner: StateSnapshot, with loser: StateSnapshot) -> StateSnapshot {
        var out = winner

        out.tasks = mergeTasks(preferred: winner.tasks, other: loser.tasks)
        out.taskLists = union(winner.taskLists, loser.taskLists)
        out.bills = union(winner.bills, loser.bills)
        out.incomes = union(winner.incomes, loser.incomes)
        out.oneOffExpenses = union(winner.oneOffExpenses, loser.oneOffExpenses)
        out.habits = union(winner.habits, loser.habits)
        out.exercises = union(winner.exercises, loser.exercises)
        out.routines = union(winner.routines, loser.routines)
        out.sessions = union(winner.sessions, loser.sessions)
        out.weightEntries = union(winner.weightEntries, loser.weightEntries)
            .sorted { $0.date < $1.date }
        out.bodyCompEntries = union(winner.bodyCompEntries, loser.bodyCompEntries)
            .sorted { $0.date < $1.date }
        out.bodyMeasurements = union(winner.bodyMeasurements, loser.bodyMeasurements)
            .sorted { $0.date > $1.date }
        out.achievements = union(winner.achievements, loser.achievements)
        out.programs = union(winner.programs, loser.programs)
        out.visitedLocations = union(winner.visitedLocations, loser.visitedLocations)
        out.plannedSessions = union(winner.plannedSessions, loser.plannedSessions)
        // Unioned like everything else: feedback given on one device is still
        // true on the other, and losing it would quietly un-learn a preference.
        out.coachFeedback = union(winner.coachFeedback ?? [], loser.coachFeedback ?? [])
        out.supplements = union(winner.supplements, loser.supplements)

        out.careDays = merge(winner.careDays, loser.careDays) { win, lose in
            CareDay.merging(win, onto: lose)
        }
        out.healthDays = merge(winner.healthDays ?? [:], loser.healthDays ?? [:]) { win, lose in
            HealthDay.merging(win, onto: lose)
        }
        out.sleepNights = merge(winner.sleepNights ?? [:], loser.sleepNights ?? [:]) { win, lose in
            // A night's stage list is one indivisible reading. Interleaving two
            // versions of it would invent a hypnogram neither device recorded,
            // so the more detailed one wins whole.
            win.segments.count >= lose.segments.count ? win : lose
        }
        out.sleepComparisons = merge(winner.sleepComparisons ?? [:], loser.sleepComparisons ?? [:]) { win, _ in win }

        // Settings and the user's name are single values, not collections:
        // there is nothing to union, so the preferred side stands. `out` is a
        // copy of `winner`, so this is already the case — except where the
        // winner never set one.
        if out.userName.isEmpty { out.userName = loser.userName }

        // Consent is never un-given by a merge. If either device recorded that
        // the user agreed, that agreement stands — the alternative is a stale
        // snapshot silently revoking it and re-prompting.
        if var coach = out.coachSettings {
            coach.hasConsented = coach.hasConsented || (loser.coachSettings?.hasConsented ?? false)
            out.coachSettings = coach
        } else {
            out.coachSettings = loser.coachSettings
        }

        return out
    }

    /// Union by id, keeping the preferred side's copy of anything in both.
    private static func union<T: Identifiable>(_ preferred: [T], _ other: [T]) -> [T] {
        var seen = Set(preferred.map(\.id))
        var out = preferred
        for item in other where !seen.contains(item.id) {
            seen.insert(item.id)
            out.append(item)
        }
        return out
    }

    /// Resolves the same task per record instead of letting the age of the
    /// entire snapshot decide. A completion on one phone must beat an untouched
    /// stale copy on another; a later explicit reopening must still be allowed.
    private static func mergeTasks(preferred: [AppTask], other: [AppTask]) -> [AppTask] {
        var byId = Dictionary(uniqueKeysWithValues: preferred.map { ($0.id, $0) })
        var order = preferred.map(\.id)

        for candidate in other {
            guard let existing = byId[candidate.id] else {
                byId[candidate.id] = candidate
                order.append(candidate.id)
                continue
            }

            switch (existing.modifiedAt, candidate.modifiedAt) {
            case let (left?, right?) where right > left:
                byId[candidate.id] = candidate
            case (nil, .some):
                byId[candidate.id] = candidate
            case (nil, nil) where candidate.done && !existing.done:
                // Compatibility for completions made before `modifiedAt`
                // existed: completed wins over an otherwise indistinguishable
                // unfinished copy.
                byId[candidate.id] = candidate
            default:
                break
            }
        }
        return order.compactMap { byId[$0] }
    }

    /// Union of two day-keyed maps, combining the entries present in both.
    private static func merge<Value>(
        _ preferred: [String: Value],
        _ other: [String: Value],
        combine: (Value, Value) -> Value
    ) -> [String: Value] {
        preferred.merging(other) { win, lose in combine(win, lose) }
    }
}

// MARK: - AppState

@Observable
final class AppState {

    /// The app's one instance.
    ///
    /// Background work needs to reach the same state the UI is showing, and it
    /// needs to reach it from `LifeApp.init()` — before any scene exists, since
    /// `BGTaskScheduler.register` must happen before launch finishes. A
    /// `@State` property can't be read that early. Tests still construct their
    /// own instances; nothing here is enforced as a singleton beyond the app
    /// agreeing to use this one.
    static let shared = AppState()

    // MARK: Stored Properties

    var latestPR: (exerciseName: String, value: String)? = nil
    var showWorkoutSheet: Bool = false
    var tasks: [AppTask] = []
    var taskLists: [TaskList] = []
    var bills: [Bill] = []
    var incomes: [Income] = []
    var oneOffExpenses: [OneOffExpense] = []
    var moneySettings: MoneySettings = MoneySettings()
    var habits: [Habit] = []
    var exercises: [Exercise] = []
    var routines: [Routine] = []
    var sessions: [WorkoutSession] = []
    var weightEntries: [WeightEntry] = []
    var bodyCompEntries: [BodyCompEntry] = []
    var bodyMeasurements: [BodyMeasurement] = []
    var achievements: [Achievement] = []
    var programs: [WorkoutProgram] = []
    var careDays: [String: CareDay] = [:]
    var careSettings: CareSettings = CareSettings()
    var workoutSettings: WorkoutSettings = WorkoutSettings()
    var userName: String = ""
    var supplements: [Supplement] = []
    var cloudUserId: String? = nil
    var syncState: SyncState = .idle
    var visitedLocations: [VisitedLocation] = []
    var plannedSessions: [PlannedSession] = []
    var progressPhotos: [ProgressPhoto] = []
    var healthDays: [String: HealthDay] = [:]
    var healthSettings: HealthSettings = HealthSettings()
    var sleepNights: [String: SleepNight] = [:]
    var sleepComparisons: [String: SleepScoreComparison] = [:]
    var coachSettings: CoachSettings = CoachSettings()

    /// Every proposal accepted, edited or dismissed.
    ///
    /// The app's only memory of its own suggestions. `TrainingMemory` turns this
    /// into score adjustments, so declining the same exercise three times
    /// actually stops it being offered — which is the difference between an app
    /// that reacts and one that learns.
    var coachFeedback: [CoachFeedbackEntry] = []

    // MARK: Computed Properties

    var todayKey: String { Date().dayKey }

    var today: CareDay {
        get { careDays[todayKey] ?? CareDay(dayKey: todayKey) }
    }

    /// True while a health sync is in flight.
    ///
    /// Observable so the Today screen can say "Updating health data…" rather
    /// than showing a generic spinner that is indistinguishable from "Asking
    /// Gemini…". They take different lengths of time, fail for different
    /// reasons, and one of them costs money.
    var isSyncingHealth: Bool = false

    // MARK: Canonical health snapshot

    /// The one health/coaching snapshot every screen reads.
    ///
    /// Memoised behind a cheap token rather than rebuilt per access. SwiftUI
    /// evaluates `body` freely, and building this walks the whole health
    /// history — doing that on every render would make scrolling Today
    /// re-derive a year of data several times a frame.
    ///
    /// The cache is `@ObservationIgnored` on purpose: writing to it from inside
    /// a getter that observation is already tracking would register a mutation
    /// during a read and loop.
    @ObservationIgnored private var cachedSnapshot: (token: String, value: HealthSnapshot)?

    /// What has to change before the snapshot is worth rebuilding.
    ///
    /// Counts and timestamps, not contents. It has to be cheap enough to
    /// evaluate on every render, and it only decides *when* to rebuild — the
    /// snapshot's own `materialHash` decides whether anything meaningful
    /// actually moved.
    @MainActor
    var healthSnapshotToken: String {
        let key = todayKey
        let sync = healthSettings.lastSyncedAt?.timeIntervalSince1970 ?? 0
        let steps = careDays[key]?.steps ?? 0
        return "\(key)|\(healthDays.count)|\(careDays.count)|\(steps)|\(sync)|\(healthSettings.stepSource.rawValue)"
    }

    /// The canonical snapshot. Today, Health, the briefings, the
    /// recommendation card and Ask Coach all read this and nothing else, which
    /// is what stops them contradicting each other.
    @MainActor
    var healthSnapshot: HealthSnapshot {
        let token = healthSnapshotToken
        if let cachedSnapshot, cachedSnapshot.token == token { return cachedSnapshot.value }
        let built = HealthSnapshotBuilder.build(appState: self)
        cachedSnapshot = (token, built)
        return built
    }

    /// Drops the memoised snapshot so the next read rebuilds it.
    ///
    /// Called after a health sync completes. The token above covers the ordinary
    /// cases, but a sync that rewrites an existing day's values changes neither
    /// a count nor today's step total, and a snapshot that silently kept the
    /// pre-sync figures is precisely the stale-data bug this work is about.
    @MainActor
    func invalidateHealthSnapshot() {
        cachedSnapshot = nil
    }

    /// Health days oldest-first, for charting.
    var healthHistory: [HealthDay] {
        healthDays.values.sorted { $0.dayKey < $1.dayKey }
    }

    /// Last night's sleep — today's record if it has one, otherwise the most
    /// recent night on file. Sleep is filed under the morning you woke, so
    /// today's entry is the night just gone.
    var lastNightSleep: HealthDay? {
        if let todayRecord = healthDays[todayKey], todayRecord.sleepMin != nil { return todayRecord }
        return healthHistory.last { $0.sleepMin != nil }
    }

    /// Activity per day, oldest first.
    ///
    /// Steps live on `CareDay` (they drive Today's Move ring) while everything
    /// else lives on `HealthDay`, so this stitches the two together. Days
    /// present in either map are included; a day with only steps is still a day
    /// worth charting.
    var activityHistory: [ActivityDay] {
        var byDay: [String: ActivityDay] = [:]

        for (key, care) in careDays where care.steps > 0 {
            byDay[key] = ActivityDay(dayKey: key, steps: care.steps)
        }
        for (key, health) in healthDays {
            var day = byDay[key] ?? ActivityDay(dayKey: key)
            day.activeEnergyKcal = health.activeEnergyKcal
            day.exerciseMinutes = health.exerciseMinutes
            day.distanceKm = health.distanceKm
            day.flights = health.flights
            byDay[key] = day
        }

        return byDay.values.sorted { $0.dayKey < $1.dayKey }
    }

    /// Mean of the last `days` readings for a metric, excluding today so a
    /// reading can be compared against its own recent baseline. Nil until there
    /// are at least `minimumSamples` readings — a baseline from two nights is
    /// noise, not a baseline.
    func healthBaseline(
        _ metric: (HealthDay) -> Double?,
        days: Int = 7,
        minimumSamples: Int = 3
    ) -> Double? {
        let values = healthHistory
            .filter { $0.dayKey != todayKey }
            .suffix(days)
            .compactMap(metric)
        guard values.count >= minimumSamples else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var activeSession: WorkoutSession? {
        sessions.first { $0.finishedAt == nil }
    }

    // MARK: Init

    init() {
        load()
        // Surface sync errors and success timestamps from FirestoreSync into
        // our observable syncState so the UI can show a banner instead of
        // failures being swallowed silently.
        FirestoreSync.shared.onUploadCompletion = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let date):
                self.syncState = .synced(date)
            case .failure(let error):
                self.syncState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Persistence

    /// When this device's local data last changed. Compared against a cloud
    /// snapshot's `clientUpdatedAt` on sign-in so a stale/empty second device
    /// can't clobber newer local data — see `loadFromCloud`.
    private var localLastModified: Date {
        get { UserDefaults.standard.object(forKey: PersistenceKey.lastModified) as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: PersistenceKey.lastModified) }
    }

    /// Whether anything on this device has been created or changed by the
    /// person using it, as opposed to written by `seedDefaults`.
    ///
    /// This is the difference between a device with data and a device that has
    /// merely been launched. A fresh install writes example tasks, bills and
    /// habits and stamps `localLastModified` with the current time — which made
    /// every new install look, at sign-in, like the device holding the newest
    /// data. It then uploaded its three sample tasks over a real account.
    /// That is the bug behind "my history disappeared when I reinstalled".
    private var hasLocalUserData: Bool {
        get { UserDefaults.standard.bool(forKey: PersistenceKey.hasUserData) }
        set { UserDefaults.standard.set(newValue, forKey: PersistenceKey.hasUserData) }
    }

    /// Set while `seedDefaults` runs so its own save isn't mistaken for the
    /// user doing something.
    private var isSeeding = false

    /// The account a `loadFromCloud` is currently running for, so the same one
    /// can't be started twice concurrently.
    private var cloudLoadInProgress: String?

    /// True between asking Firestore for the account snapshot and applying the
    /// answer, during which no upload may leave this device.
    ///
    /// This window is the whole reason a reinstall lost its workout history.
    /// `loadFromCloud` enables sync by setting `cloudUserId` *before* awaiting
    /// the download, so for the few hundred milliseconds that request is in
    /// flight the app is a device that (a) holds nothing but freshly seeded
    /// example data and (b) is allowed to upload. Anything calling `save()` in
    /// that window — a step sync, a habit reminder refresh, one tap — queued an
    /// upload of the seed state. The download then arrived and was applied
    /// locally, but the queued upload fired two seconds later and wrote the
    /// empty snapshot over the account. Local looked fine until the next
    /// install; the account had already lost every session.
    private var isLoadingFromCloud = false

    private var pendingSaveWork: DispatchWorkItem?

    /// Debounced save — coalesces rapid text-field changes (title, notes) into a single disk write.
    func saveDebounced(delay: Double = 0.4) {
        pendingSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Persists to disk, refreshes the widgets, and queues a cloud upload.
    ///
    /// `markingUserData` records whether what's being saved is something the
    /// person did. It decides, at the next sign-in, whether this device is
    /// allowed to overwrite the account — so a sync that merely wrote today's
    /// step count must not claim it. See `hasLocalUserData`.
    func save(markingUserData: Bool = true) {
        pendingSaveWork?.cancel()
        pendingSaveWork = nil
        let snapshot = makeSnapshot()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: PersistenceKey.appState)
        }
        localLastModified = Date()
        if !isSeeding && markingUserData { hasLocalUserData = true }
        WidgetSync.sync(tasks: tasks, taskLists: taskLists)
        WidgetSync.syncHabits(habits: habits, todayKey: todayKey, streakFor: streakFor)
        syncHabitReminderSummaries()
        // Held while a download is in flight. Uploading here would race the
        // snapshot being fetched, and this device is losing that race with
        // whatever it happens to hold — which on a reinstall is nothing.
        if let uid = cloudUserId, !isLoadingFromCloud {
            syncState = .syncing
            FirestoreSync.shared.scheduleUpload(snapshot, userId: uid)
        }
    }

    /// Writes any queued change straight away rather than waiting out the
    /// debounce windows.
    ///
    /// A save is debounced by 0.4s locally and the upload by a further 2s, so
    /// up to 2.4 seconds of work existed only in memory at any moment. Anything
    /// that ends the app's turn on screen — backgrounding it, swiping it away —
    /// discarded that window. Called from the scene-phase change so the last
    /// thing you did is on disk and on its way to the server before the app
    /// stops running.
    func flushPendingWrites() {
        save()
        FirestoreSync.shared.flushPending()
    }

    func taskList(for task: AppTask) -> TaskList? {
        taskLists.first { $0.id == task.listId }
    }

    func makeSnapshot() -> StateSnapshot {
        var snapshot = StateSnapshot()
        snapshot.tasks = tasks
        snapshot.taskLists = taskLists
        snapshot.bills = bills
        snapshot.incomes = incomes
        snapshot.oneOffExpenses = oneOffExpenses
        snapshot.moneySettings = moneySettings
        snapshot.habits = habits
        snapshot.exercises = exercises
        snapshot.routines = routines
        snapshot.sessions = sessions
        snapshot.weightEntries = weightEntries
        snapshot.bodyCompEntries = bodyCompEntries
        snapshot.bodyMeasurements = bodyMeasurements
        snapshot.achievements = achievements
        snapshot.programs = programs
        snapshot.careDays = careDays
        snapshot.careSettings = careSettings
        snapshot.workoutSettings = workoutSettings
        snapshot.userName = userName
        snapshot.visitedLocations = visitedLocations
        snapshot.plannedSessions = plannedSessions
        snapshot.supplements = supplements
        snapshot.healthDays = healthDays
        snapshot.healthSettings = healthSettings
        snapshot.sleepNights = sleepNights
        snapshot.sleepComparisons = sleepComparisons
        snapshot.coachSettings = coachSettings
        snapshot.coachFeedback = coachFeedback
        return snapshot
    }

    func apply(snapshot: StateSnapshot) {
        // Older versions stored relative labels such as `.tomorrow`. Freeze
        // them to a real date on first load so they cannot roll forward forever.
        tasks = snapshot.tasks.map { task in
            guard task.dueDateOverride == nil, let preset = task.dueDate else { return task }
            var migrated = task
            migrated.dueDateOverride = preset.fixedDate()
            migrated.dueDate = nil
            return migrated
        }
        taskLists = snapshot.taskLists.isEmpty ? Self.defaultTaskLists : snapshot.taskLists
        bills = snapshot.bills
        incomes = snapshot.incomes
        oneOffExpenses = snapshot.oneOffExpenses
        moneySettings = snapshot.moneySettings
        habits = Self.deduplicatedHabits(snapshot.habits)
        supplements = snapshot.supplements
        exercises = WorkoutSeed.mergeExercises(into: snapshot.exercises)
        routines = snapshot.routines.isEmpty ? WorkoutSeed.routines : snapshot.routines
        sessions = snapshot.sessions
        weightEntries = snapshot.weightEntries
        bodyCompEntries = snapshot.bodyCompEntries
        bodyMeasurements = snapshot.bodyMeasurements
        achievements = snapshot.achievements
        programs = snapshot.programs
        careDays = snapshot.careDays
        careSettings = snapshot.careSettings
        workoutSettings = snapshot.workoutSettings
        userName = snapshot.userName
        visitedLocations = snapshot.visitedLocations
        plannedSessions = snapshot.plannedSessions
        healthDays = snapshot.healthDays ?? [:]
        healthSettings = snapshot.healthSettings ?? HealthSettings()
        sleepNights = snapshot.sleepNights ?? [:]
        sleepComparisons = snapshot.sleepComparisons ?? [:]
        coachSettings = snapshot.coachSettings ?? CoachSettings()
        coachFeedback = snapshot.coachFeedback ?? []
    }

    /// Collapses exact duplicate habit definitions created by older seed/merge
    /// behaviour. Logs are combined by day without adding counts together, so
    /// removing duplicates cannot manufacture extra progress.
    private static func deduplicatedHabits(_ habits: [Habit]) -> [Habit] {
        var result: [Habit] = []
        var indexBySignature: [String: Int] = [:]

        for habit in habits {
            let signature = [
                habit.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                habit.kind.rawValue,
                habit.cadence.rawValue,
                habit.targetType.rawValue,
                String(habit.targetCount),
                habit.targetUnit.lowercased()
            ].joined(separator: "|")

            guard let existingIndex = indexBySignature[signature] else {
                indexBySignature[signature] = result.count
                result.append(habit)
                continue
            }

            var existing = result[existingIndex]
            for incoming in habit.logs {
                if let logIndex = existing.logs.firstIndex(where: { $0.dayKey == incoming.dayKey }) {
                    existing.logs[logIndex].count = max(existing.logs[logIndex].count, incoming.count)
                    existing.logs[logIndex].slipped = existing.logs[logIndex].slipped || incoming.slipped
                    if existing.logs[logIndex].note.isEmpty {
                        existing.logs[logIndex].note = incoming.note
                    }
                } else {
                    existing.logs.append(incoming)
                }
            }
            existing.createdAt = min(existing.createdAt, habit.createdAt)
            result[existingIndex] = existing
        }
        return result
    }

    // MARK: Cloud Sync

    /// Brings this device and the account into agreement, keeping everything
    /// either of them holds.
    ///
    /// Three cases, and only one of them used to be handled correctly.
    ///
    /// *Nothing in the cloud yet* — first sign-in on this account. Local data
    /// goes up as-is.
    ///
    /// *Cloud has data, this device has none of its own* — a reinstall, a new
    /// phone, or an app update that cleared local storage. The cloud snapshot is
    /// taken whole. Critically, "none of its own" means the user hasn't changed
    /// anything: the example tasks and bills a fresh install writes don't count,
    /// and used to be enough to make this device win and wipe the account.
    ///
    /// *Both have data* — they're merged rather than one chosen. Neither side
    /// loses records, and the newer of the two decides any record they both
    /// hold. See `StateSnapshot.merged(preferring:with:)`.
    func loadFromCloud(userId: String) async {
        // Two things call this — the auth-state change and the launch-time
        // check that covers an already-restored session — and on a cold start
        // with a signed-in user they can both fire. Merging twice would give
        // the same answer, but it would also download twice and race on
        // `localLastModified`, so the second caller waits for nothing instead.
        guard cloudLoadInProgress != userId else { return }
        cloudLoadInProgress = userId
        defer { cloudLoadInProgress = nil }

        cloudUserId = userId
        await MainActor.run {
            isLoadingFromCloud = true
            syncState = .syncing
        }
        do {
            let downloaded = try await FirestoreSync.shared.download(userId: userId)

            await MainActor.run {
                isLoadingFromCloud = false

                guard let downloaded else {
                    // Nothing stored for this account yet — seed it from here.
                    FirestoreSync.shared.scheduleUpload(makeSnapshot(), userId: userId)
                    syncState = .synced(Date())
                    return
                }

                let local = makeSnapshot()

                if !hasLocalUserData {
                    // This device has nothing worth keeping. Take the account's
                    // data whole rather than merging example data into it.
                    //
                    // Anything queued before now was built from the seed state,
                    // so it is dropped rather than allowed to fire after the
                    // real data lands. Belt and braces alongside the upload
                    // suppression above: a save that slipped through on another
                    // thread still cannot reach the account.
                    FirestoreSync.shared.cancelPending()
                    apply(snapshot: downloaded.snapshot)
                    localLastModified = downloaded.updatedAt
                    hasLocalUserData = true
                    syncState = .synced(Date())
                    // Persist the downloaded state to disk immediately so a
                    // crash before the next change doesn't lose it — but don't
                    // schedule an upload of what we just downloaded.
                    persistLocally()
                    return
                }

                let localIsNewer = localLastModified > downloaded.updatedAt
                let merged = localIsNewer
                    ? StateSnapshot.merged(preferring: local, with: downloaded.snapshot)
                    : StateSnapshot.merged(preferring: downloaded.snapshot, with: local)

                apply(snapshot: merged)
                localLastModified = Date()
                syncState = .syncing
                // The merged result is new to both sides, so it has to go up
                // even when the cloud copy was the newer of the two.
                FirestoreSync.shared.scheduleUpload(merged, userId: userId)
                persistLocally()
            }
        } catch {
            // Network unavailable — carry on with local data, but surface the
            // failure so the UI can show a "Sync failed" banner with retry.
            await MainActor.run {
                isLoadingFromCloud = false
                // A device that has never been used and could not read the
                // account must not upload. We don't know what is up there, and
                // what is down here is three example tasks. Sync stays off for
                // this launch; the next one tries the download again.
                if !hasLocalUserData { cloudUserId = nil }
                syncState = .failed(error.localizedDescription)
            }
        }

        if cloudUserId == userId {
            FirestoreSync.shared.startListening(userId: userId) { [weak self] downloaded in
                self?.applyRemoteUpdate(downloaded)
            }
        }
    }

    /// Applies a server-confirmed update without echoing it straight back to
    /// Firestore. Record-level merge rules preserve newer local edits while a
    /// completion made on another device becomes visible immediately.
    private func applyRemoteUpdate(_ downloaded: FirestoreSync.DownloadedSnapshot) {
        guard cloudUserId != nil, !isLoadingFromCloud else { return }
        let merged = StateSnapshot.merged(
            preferring: downloaded.snapshot,
            with: makeSnapshot()
        )
        apply(snapshot: merged)
        localLastModified = max(localLastModified, downloaded.updatedAt)
        syncState = .synced(Date())
        persistLocally()
    }

    /// Writes the current state to disk without touching the cloud or the
    /// modification stamp. Used after applying a downloaded snapshot, where
    /// `save()` would schedule a pointless upload of what just arrived.
    private func persistLocally() {
        if let data = try? JSONEncoder().encode(makeSnapshot()) {
            UserDefaults.standard.set(data, forKey: PersistenceKey.appState)
        }
        WidgetSync.sync(tasks: tasks, taskLists: taskLists)
        WidgetSync.syncHabits(habits: habits, todayKey: todayKey, streakFor: streakFor)
    }

    func disableCloudSync() {
        // Cancel any queued upload so a debounced write from the previous
        // session can't fire after sign-out and leak data into the cloud.
        FirestoreSync.shared.cancelPending()
        FirestoreSync.shared.stopListening()
        cloudUserId = nil
        syncState = .idle
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: PersistenceKey.appState),
           let snapshot = try? JSONDecoder().decode(StateSnapshot.self, from: data) {
            apply(snapshot: snapshot)
            if taskLists.isEmpty { taskLists = Self.defaultTaskLists }
            // Devices that were already running before `hasUserData` existed
            // have no value stored for it, which reads as false — and false
            // means "safe to replace with the cloud copy". A device with a save
            // file has been used, so it is credited with its data on first
            // launch after upgrading.
            if UserDefaults.standard.object(forKey: PersistenceKey.hasUserData) == nil {
                hasLocalUserData = true
            }
        } else {
            // First launch — seed default data
            exercises = WorkoutSeed.exercises
            routines = WorkoutSeed.routines
            seedDefaults()
        }
        loadPhotos()
        resetCoachForUITestsIfNeeded()
        // Defer notification scheduling off the synchronous launch path.
        let habitsSnapshot = habits
        DispatchQueue.main.async { [weak self] in
            HabitReminderManager.shared.syncReminders(for: habitsSnapshot)
            self?.syncHabitReminderSummaries()
        }
    }

    /// Puts the coach back to its shipped defaults when launched by a UI test.
    ///
    /// Without this a test inherits whatever the simulator was left in — a
    /// dismissed suggestion, consent already given — and fails for a reason
    /// that has nothing to do with the change being tested. Guarded by a launch
    /// argument the app is never started with in normal use.
    private func resetCoachForUITestsIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-CoachUITest") else { return }
        coachSettings = CoachSettings()
        coachFeedback = []
        CoachCache.resetForTesting()
    }

    /// Schedules (or cancels) the daily morning-summary and evening-nudge
    /// habit notifications based on CareSettings and today's completion
    /// state. Uses the same "is this habit done today" rule as the widget
    /// (WidgetSync.syncHabits) so the notification and widget agree.
    private func syncHabitReminderSummaries() {
        let unfinishedToday = habits.filter { habit in
            guard !habit.isArchived else { return false }
            let todayLog = habit.logs.first { $0.dayKey == todayKey }
            let count = todayLog?.count ?? 0
            let slipped = todayLog?.slipped == true
            let isCompleted = habit.kind == .break ? !slipped : (!slipped && count >= habit.targetCount)
            return !isCompleted
        }

        if careSettings.morningSummaryEnabled {
            HabitReminderManager.shared.scheduleMorningSummary(activeCount: unfinishedToday.count)
        } else {
            HabitReminderManager.shared.cancelMorningSummary()
        }

        if careSettings.eveningNudgeEnabled {
            HabitReminderManager.shared.scheduleEveningNudge(unfinishedNames: unfinishedToday.map(\.name))
        } else {
            HabitReminderManager.shared.cancelEveningNudge()
        }
    }

    static let defaultTaskLists: [TaskList] = [
        TaskList(id: "work",     name: "Work",     emoji: "💼", colorHex: "#5E9BF0", isSystem: true),
        TaskList(id: "gym",      name: "Gym",      emoji: "🏋️", colorHex: "#2FD4C0", isSystem: true),
        TaskList(id: "personal", name: "Personal", emoji: "🌱", colorHex: "#FF9F0A", isSystem: true),
    ]

    private func seedDefaults() {
        // Everything written here is an example, not the user's data. The flag
        // keeps `save()` from marking this device as holding real content,
        // which is what decides whether it may overwrite an account at sign-in.
        isSeeding = true
        defer { isSeeding = false }

        taskLists = Self.defaultTaskLists
        tasks = [
            AppTask(title: "Reply to client email", listId: "work", dueDate: .today),
            AppTask(title: "Push session — legs", listId: "gym", dueDate: .today),
            AppTask(title: "Refill water bottle", listId: "personal", dueDate: .today),
        ]
        bills = [
            Bill(name: "Rent", amount: 1200, dayOfMonth: 1),
            Bill(name: "Electricity", amount: 85, dayOfMonth: 15),
            Bill(name: "Internet", amount: 45, dayOfMonth: 20),
            Bill(name: "Phone", amount: 35, dayOfMonth: 28),
        ]
        habits = [
            Habit(name: "Drink 8 glasses of water", emoji: "💧", kind: .build, cadence: .daily, targetCount: 8),
            Habit(name: "Read for 20 minutes", emoji: "📚", kind: .build, cadence: .daily, targetCount: 1),
            Habit(name: "No social media after 9pm", emoji: "📵", kind: .break, cadence: .daily, targetCount: 1),
            Habit(name: "Exercise 4x per week", emoji: "🏃", kind: .build, cadence: .weekly, targetCount: 4),
        ]
        save()
    }

    // MARK: - Task Mutations

    func addTask(title: String, listId: String = "personal", dueDate: DueDate, priority: TaskPriority = .none, notes: String = "", dueDateOverride: Date? = nil) {
        var task = AppTask(title: title, listId: listId, dueDate: nil)
        task.priority = priority
        task.notes = notes
        task.dueDateOverride = Calendar.current.startOfDay(for: dueDateOverride ?? dueDate.fixedDate())
        task.modifiedAt = Date()
        tasks.append(task)
        save()
    }

    /// Stores an absolute day. Presets are resolved immediately and never move
    /// when the app crosses midnight.
    func scheduleTask(id: String, on date: Date?) {
        updateTask(
            id: id,
            dueDate: .some(nil),
            dueDateOverride: .some(date.map { Calendar.current.startOfDay(for: $0) })
        )
    }

    func toggleTask(id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let wasRecurring = tasks[idx].isRecurring
        let recurrenceType = tasks[idx].recurrenceType
        tasks[idx].done.toggle()
        tasks[idx].completedAt = tasks[idx].done ? Date() : nil
        tasks[idx].modifiedAt = Date()
        if tasks[idx].done { NotificationsManager.shared.cancelTaskReminder(taskId: id) }

        // Advance recurring task to next period when checked off
        if tasks[idx].done, wasRecurring, let rt = recurrenceType {
            let base = tasks[idx].dueDateOverride ?? tasks[idx].dueDate?.date ?? Date()
            let cal = Calendar.current
            let nextDate: Date?
            switch rt {
            case .daily:    nextDate = cal.date(byAdding: .day, value: 1, to: base)
            case .weekly:   nextDate = cal.date(byAdding: .weekOfYear, value: 1, to: base)
            case .biweekly: nextDate = cal.date(byAdding: .weekOfYear, value: 2, to: base)
            case .monthly:  nextDate = cal.date(byAdding: .month, value: 1, to: base)
            case .yearly:   nextDate = cal.date(byAdding: .year, value: 1, to: base)
            }
            if let next = nextDate {
                tasks[idx].done = false
                tasks[idx].completedAt = nil
                tasks[idx].dueDateOverride = cal.startOfDay(for: next)
                tasks[idx].dueDate = nil

                // Carry the reminder forward to the next occurrence so
                // recurring tasks don't silently lose their notifications.
                if let oldReminder = tasks[idx].reminderDate {
                    let delta = next.timeIntervalSince(base)
                    let newReminder = oldReminder.addingTimeInterval(delta)
                    tasks[idx].reminderDate = newReminder
                    NotificationsManager.shared.scheduleTaskReminder(
                        taskId: tasks[idx].id,
                        title: tasks[idx].title,
                        at: newReminder
                    )
                }
            }
        }
        save()
    }

    func deleteTask(id: String) {
        NotificationsManager.shared.cancelTaskReminder(taskId: id)
        tasks.removeAll { $0.id == id }
        save()
    }

    func updateTask(id: String, title: String? = nil, dueDate: DueDate?? = nil, priority: TaskPriority? = nil, notes: String? = nil, listId: String? = nil, dueDateOverride: Date?? = nil, reminderDate: Date?? = nil, scheduledTime: Date?? = nil, estimatedMinutes: Int?? = nil, isRecurring: Bool? = nil, recurrenceType: RecurrenceType?? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        // Track whether this update is text-only (title/notes) to debounce disk writes.
        let isTextOnly = title != nil || notes != nil
        var otherFieldsChanged = false
        if let title = title { tasks[idx].title = title }
        if let dueDate = dueDate { tasks[idx].dueDate = dueDate; otherFieldsChanged = true }
        if let priority = priority { tasks[idx].priority = priority; otherFieldsChanged = true }
        if let notes = notes { tasks[idx].notes = notes }
        if let listId = listId { tasks[idx].listId = listId; otherFieldsChanged = true }
        if let override = dueDateOverride { tasks[idx].dueDateOverride = override; otherFieldsChanged = true }
        if let rd = reminderDate {
            tasks[idx].reminderDate = rd
            otherFieldsChanged = true
            if let date = rd {
                NotificationsManager.shared.scheduleTaskReminder(taskId: id, title: tasks[idx].title, at: date)
            } else {
                NotificationsManager.shared.cancelTaskReminder(taskId: id)
            }
        }
        if let st = scheduledTime { tasks[idx].scheduledTime = st; otherFieldsChanged = true }
        if let em = estimatedMinutes { tasks[idx].estimatedMinutes = em; otherFieldsChanged = true }
        if let rec = isRecurring { tasks[idx].isRecurring = rec; otherFieldsChanged = true }
        if let rt = recurrenceType { tasks[idx].recurrenceType = rt; otherFieldsChanged = true }
        tasks[idx].modifiedAt = Date()
        if isTextOnly && !otherFieldsChanged {
            saveDebounced()
        } else {
            save()
        }
    }

    // MARK: - Subtask Mutations

    func addSubtask(taskId: String, title: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].subtasks.append(Subtask(title: title))
        tasks[idx].modifiedAt = Date()
        save()
    }

    func toggleSubtask(taskId: String, subtaskId: String) {
        guard let tIdx = tasks.firstIndex(where: { $0.id == taskId }),
              let sIdx = tasks[tIdx].subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
        tasks[tIdx].subtasks[sIdx].done.toggle()
        tasks[tIdx].modifiedAt = Date()
        save()
    }

    func deleteSubtask(taskId: String, subtaskId: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].subtasks.removeAll { $0.id == subtaskId }
        tasks[idx].modifiedAt = Date()
        save()
    }

    // MARK: - Bill Mutations

    func addBill(name: String, amount: Double, dayOfMonth: Int, notes: String = "") {
        let bill = Bill(name: name, amount: amount, dayOfMonth: dayOfMonth, notes: notes)
        bills.append(bill)
        save()
    }

    func deleteBill(id: String) {
        bills.removeAll { $0.id == id }
        save()
    }

    func updateBill(id: String, name: String? = nil, amount: Double? = nil, dayOfMonth: Int? = nil, notes: String? = nil) {
        guard let idx = bills.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { bills[idx].name = name }
        if let amount = amount { bills[idx].amount = amount }
        if let day = dayOfMonth { bills[idx].dayOfMonth = day }
        if let notes = notes { bills[idx].notes = notes }
        save()
    }

    // MARK: - Income Mutations

    func addIncome(name: String, amount: Double, dayOfMonth: Int, notes: String = "") {
        incomes.append(Income(name: name, amount: amount, dayOfMonth: dayOfMonth, notes: notes))
        save()
    }

    func deleteIncome(id: String) {
        incomes.removeAll { $0.id == id }
        save()
    }

    func updateIncome(id: String, name: String? = nil, amount: Double? = nil, dayOfMonth: Int? = nil, notes: String? = nil) {
        guard let idx = incomes.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { incomes[idx].name = name }
        if let amount = amount { incomes[idx].amount = amount }
        if let day = dayOfMonth { incomes[idx].dayOfMonth = day }
        if let notes = notes { incomes[idx].notes = notes }
        save()
    }

    // MARK: - One-Off Expense Mutations

    func addOneOffExpense(name: String, amount: Double, date: Date = Date(), notes: String = "") {
        oneOffExpenses.append(OneOffExpense(name: name, amount: amount, date: date, notes: notes))
        save()
    }

    func deleteOneOffExpense(id: String) {
        oneOffExpenses.removeAll { $0.id == id }
        save()
    }

    func updateOneOffExpense(id: String, name: String? = nil, amount: Double? = nil, date: Date? = nil, notes: String? = nil) {
        guard let idx = oneOffExpenses.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { oneOffExpenses[idx].name = name }
        if let amount = amount { oneOffExpenses[idx].amount = amount }
        if let date = date { oneOffExpenses[idx].date = date }
        if let notes = notes { oneOffExpenses[idx].notes = notes }
        save()
    }

    func setMoneySettings(_ settings: MoneySettings) {
        moneySettings = settings
        save()
    }

    // MARK: - Habit Analytics

    func streakFor(_ habit: Habit) -> Int {
        var count = 0
        let cal = Calendar.current
        let todayKey = Date().dayKey
        let todayLog = habit.logs.first(where: { $0.dayKey == todayKey })
        let todaySuccess: Bool = {
            if habit.kind == .break { return todayLog?.slipped != true }
            return todayLog != nil && (todayLog?.count ?? 0) >= habit.targetCount && todayLog?.slipped != true
        }()
        // If today isn't done yet, start from yesterday so streak persists until midnight
        var date: Date = todaySuccess ? Date() : (cal.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        // Lower bound: never walk before the habit was created. Critical for break
        // habits, where a no-log day counts as success — without this the loop
        // would walk backward forever and freeze the main thread.
        let startBound = cal.startOfDay(for: habit.createdAt)
        while date >= startBound {
            let key = date.dayKey
            let log = habit.logs.first(where: { $0.dayKey == key })
            let success: Bool
            if habit.kind == .break {
                success = log?.slipped != true
            } else {
                success = log != nil && (log?.count ?? 0) >= habit.targetCount && log?.slipped != true
            }
            if success {
                count += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
                date = prev
            } else {
                break
            }
        }
        return count
    }

    func bestStreakFor(_ habit: Habit) -> Int {
        let cal = Calendar.current

        if habit.kind == .break {
            // For break habits, find the longest run of days without a slip
            // Walk from the earliest log date to today
            guard let earliest = habit.logs.compactMap({ DayKey.date(from: $0.dayKey) }).min() else { return 0 }
            let slippedKeys = Set(habit.logs.filter { $0.slipped }.map { $0.dayKey })
            var best = 0, current = 0
            var date = earliest
            let today = cal.startOfDay(for: Date())
            while date <= today {
                if !slippedKeys.contains(date.dayKey) {
                    current += 1
                    best = max(best, current)
                } else {
                    current = 0
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
            return best
        }

        guard !habit.logs.isEmpty else { return 0 }
        let sortedDays = habit.logs
            .filter { $0.count >= habit.targetCount && !$0.slipped }
            .compactMap { DayKey.date(from: $0.dayKey) }
            .sorted()
        guard !sortedDays.isEmpty else { return 0 }
        var best = 1, current = 1
        for i in 1..<sortedDays.count {
            let diff = cal.dateComponents([.day], from: sortedDays[i-1], to: sortedDays[i]).day ?? 0
            if diff == 1 { current += 1; best = max(best, current) } else { current = 1 }
        }
        return best
    }

    func totalCompletionsFor(_ habit: Habit) -> Int {
        if habit.kind == .break {
            // Count days with a log that didn't slip (maintained days)
            return habit.logs.filter { !$0.slipped }.count
        }
        return habit.logs.filter { $0.count >= habit.targetCount && !$0.slipped }.count
    }

    func weeklyCompletionFor(_ habit: Habit) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var completed = 0
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = day.dayKey
            let log = habit.logs.first(where: { $0.dayKey == key })
            if habit.kind == .break {
                if log?.slipped != true { completed += 1 }
            } else if let log = log, log.count >= habit.targetCount, !log.slipped {
                completed += 1
            }
        }
        return Double(completed) / 7.0
    }

    // MARK: - Habit Mutations

    func addHabit(name: String, emoji: String, kind: HabitKind, cadence: HabitCadence, targetCount: Int) {
        let habit = Habit(name: name, emoji: emoji, kind: kind, cadence: cadence, targetCount: targetCount)
        habits.append(habit)
        save()
    }

    func updateHabit(id: String, name: String? = nil, emoji: String? = nil, kind: HabitKind? = nil, cadence: HabitCadence? = nil, targetCount: Int? = nil, reminderEnabled: Bool? = nil, reminderTime: Date?? = nil) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { habits[idx].name = name }
        if let emoji = emoji { habits[idx].emoji = emoji }
        if let kind = kind { habits[idx].kind = kind }
        if let cadence = cadence { habits[idx].cadence = cadence }
        if let target = targetCount { habits[idx].targetCount = target }
        if let enabled = reminderEnabled { habits[idx].reminderEnabled = enabled }
        if let time = reminderTime { habits[idx].reminderTime = time }
        HabitReminderManager.shared.syncReminders(for: [habits[idx]])
        save()
    }

    func deleteHabit(id: String) {
        HabitReminderManager.shared.cancelReminder(habitId: id)
        habits.removeAll { $0.id == id }
        save()
    }

    func toggleArchiveHabit(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[idx].isArchived.toggle()
        HabitReminderManager.shared.syncReminders(for: [habits[idx]])
        save()
    }

    func logHabit(id: String, dayKey: String? = nil, count: Int = 1) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = dayKey ?? todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count += count
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: count))
        }
        save()
    }

    func toggleHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs.remove(at: logIdx)
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1))
        }
        save()
    }

    /// Mark a habit complete for today (idempotent). Used to apply completions
    /// queued by the widget's interactive button.
    func completeHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if habits[idx].kind == .break {
            if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
                habits[idx].logs[logIdx].slipped = false
            }
            // No log for a break habit already counts as maintained.
        } else {
            let target = max(1, habits[idx].targetCount)
            if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
                habits[idx].logs[logIdx].slipped = false
                if habits[idx].logs[logIdx].count < target {
                    habits[idx].logs[logIdx].count = target
                }
            } else {
                habits[idx].logs.append(HabitLogEntry(dayKey: key, count: target))
            }
        }
        save()
    }

    /// Apply any habit completions the widget queued (its interactive button
    /// writes ids to the App Group; the app logs them next time it's active).
    func drainPendingHabitCompletions() {
        let appGroup = "group.uk.co.prolineroofingandsolar.life"
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.string(forKey: "life_pending_completions_date") == todayKey else { return }
        let pending = (defaults.array(forKey: "life_pending_completions_v1") as? [String]) ?? []
        guard !pending.isEmpty else { return }
        defaults.set([String](), forKey: "life_pending_completions_v1")
        for id in pending { completeHabitToday(id: id) }
    }

    func incHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count += 1
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1))
        }
        // If this is a water-tracking habit, also increment the hydration ring
        if habits[idx].name.lowercased().contains("water") {
            addWater()
            return // save() already called inside addWater()
        }
        save()
    }

    func undoHabitCompletion(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        habits[idx].logs.removeAll { $0.dayKey == key }
        save()
    }

    func setHabitCount(id: String, count: Int) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        let clamped = max(0, count)
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            if clamped == 0 {
                habits[idx].logs.remove(at: logIdx)
            } else {
                habits[idx].logs[logIdx].count = clamped
            }
        } else if clamped > 0 {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: clamped))
        }
        save()
    }

    func completeHabitTimer(id: String, seconds: Int) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        let minutes = max(1, seconds / 60)
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].count = minutes
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: minutes))
        }
        save()
    }

    func slipHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        if let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            habits[idx].logs[logIdx].slipped = true
        } else {
            habits[idx].logs.append(HabitLogEntry(dayKey: key, count: 1, slipped: true))
        }
        save()
    }

    func decHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        guard let logIdx = habits[idx].logs.firstIndex(where: { $0.dayKey == key }) else { return }
        if habits[idx].logs[logIdx].count > 1 {
            habits[idx].logs[logIdx].count -= 1
        } else {
            habits[idx].logs.remove(at: logIdx)
        }
        save()
        // Also undo water ring if applicable
        if habits[idx].name.lowercased().contains("water") {
            removeWater()
        }
    }

    func unslipHabitToday(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        let key = todayKey
        habits[idx].logs.removeAll { $0.dayKey == key }
        save()
    }

    // MARK: - Supplement Mutations

    func addSupplement(_ supplement: Supplement) {
        supplements.append(supplement)
        save()
    }

    func updateSupplement(_ supplement: Supplement) {
        guard let idx = supplements.firstIndex(where: { $0.id == supplement.id }) else { return }
        var updated = supplement
        updated.logs = supplements[idx].logs // preserve existing dose logs
        supplements[idx] = updated
        save()
    }

    func deleteSupplement(id: String) {
        supplements.removeAll { $0.id == id }
        save()
    }

    func logDose(supplementId: String) {
        guard let idx = supplements.firstIndex(where: { $0.id == supplementId }) else { return }
        let key = Date().dayKey
        if let logIdx = supplements[idx].logs.firstIndex(where: { $0.dayKey == key }) {
            supplements[idx].logs[logIdx].dosesTaken += 1
        } else {
            supplements[idx].logs.append(DoseLog(dayKey: key, dosesTaken: 1))
        }
        save()
    }

    func undoDose(supplementId: String) {
        guard let idx = supplements.firstIndex(where: { $0.id == supplementId }) else { return }
        let key = Date().dayKey
        guard let logIdx = supplements[idx].logs.firstIndex(where: { $0.dayKey == key }) else { return }
        if supplements[idx].logs[logIdx].dosesTaken > 1 {
            supplements[idx].logs[logIdx].dosesTaken -= 1
        } else {
            supplements[idx].logs.remove(at: logIdx)
        }
        save()
    }

    func dosesToday(for supplement: Supplement) -> Int {
        supplement.logs.first(where: { $0.dayKey == Date().dayKey })?.dosesTaken ?? 0
    }

    func isDueToday(_ supplement: Supplement) -> Bool {
        guard !supplement.isArchived else { return false }
        if supplement.scheduleDays.isEmpty { return true }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let mon1 = ((weekday + 5) % 7) + 1
        return supplement.scheduleDays.contains(mon1)
    }

    // MARK: - Routine Mutations

    func addRoutine(name: String, exercises: [RoutineExercise] = []) {
        let routine = Routine(name: name, exercises: exercises)
        routines.append(routine)
        save()
    }

    func updateRoutine(id: String, name: String? = nil, exercises: [RoutineExercise]? = nil, colorHex: String? = nil, emoji: String? = nil, photoData: Data? = nil, clearPhoto: Bool = false) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { routines[idx].name = name }
        if let exercises = exercises { routines[idx].exercises = exercises }
        if let colorHex = colorHex { routines[idx].colorHex = colorHex }
        if let emoji = emoji { routines[idx].emoji = emoji }
        if clearPhoto { routines[idx].photoData = nil }
        else if let photoData = photoData { routines[idx].photoData = photoData }
        save()
    }

    func deleteRoutine(id: String) {
        routines.removeAll { $0.id == id }
        save()
    }

    // MARK: - Workout Session Mutations

    func startSession(name: String, routineId: String? = nil) {
        // Safety: if a workout is already in progress, do nothing instead of
        // silently destroying it. Callers should inspect `activeSession` first
        // and either resume it or prompt the user to finish/discard.
        guard activeSession == nil else { return }

        var session = WorkoutSession(name: name, routineId: routineId)

        if let routineId = routineId,
           let routine = routines.first(where: { $0.id == routineId }) {
            session.exercises = routine.exercises.map { re in
                var sessionExercise = SessionExercise(exerciseId: re.exerciseId)
                let suggested = suggestedWeight(for: re.exerciseId)
                let sugReps = suggestedReps(for: re.exerciseId)
                let weight = suggested > 0 ? suggested : re.defaultWeight
                let reps = sugReps > 0 ? sugReps : re.defaultReps
                sessionExercise.targetRepMin = re.repRangeMin
                sessionExercise.targetRepMax = re.repRangeMax
                sessionExercise.sets = (0..<re.defaultSets).map { _ in
                    LoggedSet(weight: weight, reps: reps)
                }
                return sessionExercise
            }
        }

        sessions.append(session)
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.start(workoutName: session.name, startedAt: session.startedAt)
        }
        save()
    }

    func updateSet(sessionId: String, exerciseId: String, setId: String, weight: Double? = nil, reps: Int? = nil, durationSec: Int? = nil, distanceKm: Double? = nil, isWarmup: Bool? = nil, isDropSet: Bool? = nil, rpe: Int? = nil) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        if let weight = weight { sessions[sIdx].exercises[eIdx].sets[setIdx].weight = weight }
        if let reps = reps { sessions[sIdx].exercises[eIdx].sets[setIdx].reps = reps }
        if let dur = durationSec { sessions[sIdx].exercises[eIdx].sets[setIdx].durationSec = dur }
        if let dist = distanceKm { sessions[sIdx].exercises[eIdx].sets[setIdx].distanceKm = dist }
        if let warmup = isWarmup { sessions[sIdx].exercises[eIdx].sets[setIdx].isWarmup = warmup }
        if let drop = isDropSet { sessions[sIdx].exercises[eIdx].sets[setIdx].isDropSet = drop }
        if let rpe = rpe { sessions[sIdx].exercises[eIdx].sets[setIdx].rpe = rpe == 0 ? nil : rpe }
        save()
    }

    /// Changes what a set is — normal, warm-up, drop or superset — in one move.
    ///
    /// Marking a set as a superset also pairs its exercise with the next one in
    /// the session if it isn't already paired, because a superset is by
    /// definition two exercises alternated: labelling a set and leaving the
    /// exercise unpaired would be a badge that means nothing. Where there is no
    /// next exercise the set is still labelled, so the record is accurate even
    /// though the pairing has to wait for something to pair with.
    ///
    /// Clearing a superset set back to normal deliberately leaves the exercise
    /// pairing alone: other sets in the pair may still be supersets, and
    /// unpairing the exercise would silently change them too.
    func setSetKind(sessionId: String, exerciseId: String, setId: String, kind: SetKind) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == setId })
        else { return }

        sessions[sIdx].exercises[eIdx].sets[setIdx].kind = kind

        if kind == .superset, sessions[sIdx].exercises[eIdx].supersetGroupId == nil {
            let next = eIdx + 1
            if sessions[sIdx].exercises.indices.contains(next) {
                let groupId = sessions[sIdx].exercises[next].supersetGroupId ?? UUID().uuidString
                sessions[sIdx].exercises[eIdx].supersetGroupId = groupId
                sessions[sIdx].exercises[next].supersetGroupId = groupId
            }
        }

        save()
    }

    func toggleSetDone(sessionId: String, exerciseId: String, setId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        let isDone = !sessions[sIdx].exercises[eIdx].sets[setIdx].done
        sessions[sIdx].exercises[eIdx].sets[setIdx].done = isDone
        sessions[sIdx].exercises[eIdx].sets[setIdx].completedAt = isDone ? Date() : nil
        if isDone {
            let set = sessions[sIdx].exercises[eIdx].sets[setIdx]
            let exId = sessions[sIdx].exercises[eIdx].exerciseId
            let prevPR = computePRs(for: exId)
            let new1RM = set.weight * (1 + Double(set.reps) / 30.0)
            if set.weight > prevPR.bestWeight || new1RM > prevPR.best1RM {
                let name = exercises.first(where: { $0.id == exId })?.name ?? "Exercise"
                latestPR = (exerciseName: name, value: "\(set.weight.formatted1)kg × \(set.reps)")
                if !achievements.contains(where: { $0.kind == .weightPR }) || set.weight > prevPR.bestWeight {
                    let unlocked = Set(achievements.map(\.kind))
                    if !unlocked.contains(.weightPR) {
                        achievements.append(Achievement(kind: .weightPR, title: AchievementKind.weightPR.title, detail: "\(name): \(set.weight.formatted1)kg"))
                    }
                }
            }
        }
        save()
    }

    func toggleSetFailure(sessionId: String, exerciseId: String, setId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == setId }) else { return }
        sessions[sIdx].exercises[eIdx].sets[setIdx].isFailure.toggle()
        save()
    }

    func addSet(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let lastSet = sessions[sIdx].exercises[eIdx].sets.last
        // Prefer last set in current session; fall back to previous session history
        let weight: Double
        let reps: Int
        if let last = lastSet, last.weight > 0 {
            weight = last.weight
            reps = last.reps
        } else {
            weight = suggestedWeight(for: exerciseId)
            reps = suggestedReps(for: exerciseId)
        }
        sessions[sIdx].exercises[eIdx].sets.append(LoggedSet(weight: weight, reps: reps))
        save()
    }

    func removeSet(sessionId: String, exerciseId: String, setId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        sessions[sIdx].exercises[eIdx].sets.removeAll { $0.id == setId }
        save()
    }

    func addExerciseToSession(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var sessionExercise = SessionExercise(exerciseId: exerciseId)
        let w = suggestedWeight(for: exerciseId)
        let r = suggestedReps(for: exerciseId)
        sessionExercise.sets = [LoggedSet(weight: w, reps: r)]
        sessions[sIdx].exercises.append(sessionExercise)
        save()
    }

    func removeExerciseFromSession(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[sIdx].exercises.removeAll { $0.id == exerciseId }
        save()
    }

    func addDropSet(sessionId: String, exerciseId: String, afterSetId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIdx = sessions[sIdx].exercises[eIdx].sets.firstIndex(where: { $0.id == afterSetId }) else { return }
        let parent = sessions[sIdx].exercises[eIdx].sets[setIdx]
        let drop = LoggedSet(weight: max(0, parent.weight - 5), reps: parent.reps, isDropSet: true)
        sessions[sIdx].exercises[eIdx].sets.insert(drop, at: setIdx + 1)
        save()
    }

    func setSupersetGroup(sessionId: String, exerciseIds: [String], groupId: String?) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        for eIdx in sessions[sIdx].exercises.indices {
            if exerciseIds.contains(sessions[sIdx].exercises[eIdx].id) {
                sessions[sIdx].exercises[eIdx].supersetGroupId = groupId
            }
        }
        save()
    }

    func finishSession(sessionId: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].finishedAt = Date()
        // Mark any planned session for today as completed
        let todayStart = Calendar.current.startOfDay(for: Date())
        if let pIdx = plannedSessions.firstIndex(where: {
            Calendar.current.startOfDay(for: $0.date) == todayStart && !$0.completed
        }) {
            plannedSessions[pIdx].completed = true
        }
        checkAndGrantAchievements()
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.end()
        }
        save()
    }

    func updateSessionNotes(sessionId: String, notes: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].notes = notes
        save()
    }

    func deleteFinishedSession(sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        save()
    }

    func rateSession(sessionId: String, rating: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].rating = rating
        save()
    }

    func discardSession(sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
        if #available(iOS 16.2, *) {
            WorkoutLiveActivityManager.shared.end()
        }
        save()
    }

    func renameSession(sessionId: String, name: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].name = name
        save()
    }

    func reorderExercises(sessionId: String, from: IndexSet, to: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].exercises.move(fromOffsets: from, toOffset: to)
        save()
    }

    /// Adjust a (finished) workout's date and duration. Sets `finishedAt` to the
    /// chosen date and back-dates `startedAt` so the stored duration is preserved.
    func setSessionTimes(sessionId: String, date: Date, durationSeconds: Int) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[idx].finishedAt = date
        sessions[idx].startedAt = date.addingTimeInterval(-TimeInterval(max(0, durationSeconds)))
        save()
    }

    func addWarmupSets(sessionId: String, exerciseId: String) {
        guard let sIdx = sessions.firstIndex(where: { $0.id == sessionId }),
              let eIdx = sessions[sIdx].exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let workingWeight = sessions[sIdx].exercises[eIdx].sets.first(where: { !$0.isWarmup })?.weight
                            ?? suggestedWeight(for: exerciseId)
        guard workingWeight > 0 else { return }
        let warmupSpecs: [(pct: Double, reps: Int)] = [(0.4, 5), (0.6, 3), (0.8, 2)]
        let newSets = warmupSpecs.map { w -> LoggedSet in
            var s = LoggedSet()
            s.weight = (workingWeight * w.pct / 2.5).rounded() * 2.5
            s.reps = w.reps
            s.isWarmup = true
            return s
        }
        sessions[sIdx].exercises[eIdx].sets.insert(contentsOf: newSets, at: 0)
        save()
    }

    // MARK: - Body / Weight Mutations

    /// Records a weigh-in, ignoring anything that isn't a plausible weight.
    ///
    /// The UI disables Add for an invalid entry, but this is also reached by the
    /// Apple Health import, which forwards whatever HealthKit hands over. A
    /// single 0 kg sample — they exist, usually from a scale mid-calibration —
    /// used to be stored and then flattened the whole weight chart.
    @discardableResult
    func logBodyWeight(
        valueKg: Double,
        date: Date = Date(),
        source: HealthProvider = .manual
    ) -> Bool {
        guard let valid = BodyMetricLimits.validate(valueKg, in: BodyMetricLimits.weightKg) else {
            return false
        }
        var entry = WeightEntry(date: date, valueKg: valid)
        entry.source = source.storageValue
        weightEntries.append(entry)
        weightEntries.sort { $0.date < $1.date }
        save()
        return true
    }

    func deleteWeightEntry(id: String) {
        weightEntries.removeAll { $0.id == id }
        save()
    }

    /// Merges body composition readings, dropping any field that isn't a
    /// possible measurement.
    ///
    /// Validation happens here rather than only in the entry form because this
    /// is also the import path, and a rejected field has to be dropped
    /// individually — a bad BMI shouldn't cost the body-fat reading recorded
    /// alongside it.
    func mergeBodyCompEntries(_ newEntries: [BodyCompEntry]) {
        for raw in newEntries {
            var entry = raw
            // Body fat is stored 0–1, so the range is checked in percent.
            entry.bodyFatPct = raw.bodyFatPct.flatMap {
                BodyMetricLimits.validate($0 * 100, in: BodyMetricLimits.bodyFatPercent).map { $0 / 100 }
            }
            entry.leanMassKg = raw.leanMassKg.flatMap {
                BodyMetricLimits.validate($0, in: BodyMetricLimits.leanMassKg)
            }
            entry.bmi = raw.bmi.flatMap {
                BodyMetricLimits.validate($0, in: BodyMetricLimits.bmi)
            }

            // Nothing survived validation, so there's nothing to record.
            guard entry.bodyFatPct != nil || entry.leanMassKg != nil || entry.bmi != nil else { continue }

            // Match by date (same day)
            let key = entry.date.dayKey
            if let idx = bodyCompEntries.firstIndex(where: { $0.date.dayKey == key }) {
                // Merge fields
                if let bf = entry.bodyFatPct { bodyCompEntries[idx].bodyFatPct = bf }
                if let lm = entry.leanMassKg { bodyCompEntries[idx].leanMassKg = lm }
                if let bmi = entry.bmi { bodyCompEntries[idx].bmi = bmi }
            } else {
                bodyCompEntries.append(entry)
            }
        }
        bodyCompEntries.sort { $0.date < $1.date }
        save()
    }

    func deleteBodyCompEntry(id: String) {
        bodyCompEntries.removeAll { $0.id == id }
        save()
    }

    /// Sets — or with nil, clears — the goal weight.
    ///
    /// A goal of 0 is refused rather than stored. It was previously accepted and
    /// then used as the denominator of the progress figure, so the goal read as
    /// met the instant it was set.
    func setGoalWeight(kg: Double?) {
        guard let kg else {
            workoutSettings.goalWeightKg = nil
            save()
            return
        }
        guard let valid = BodyMetricLimits.validate(kg, in: BodyMetricLimits.goalWeightKg) else { return }
        workoutSettings.goalWeightKg = valid
        save()
    }

    // MARK: - Care Day Mutations

    func addWater() {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.waterGlasses += 1
        careDays[todayKey] = day
        save()
    }

    func removeWater() {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        if day.waterGlasses > 0 { day.waterGlasses -= 1 }
        careDays[todayKey] = day
        save()
    }

    func addMeal(name: String = "") {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.meals.append(name.isEmpty ? "Meal \(day.meals.count + 1)" : name)
        careDays[todayKey] = day
        save()
    }

    func markBreak() {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.lastBreakAt = Date()
        day.breaksTaken += 1
        careDays[todayKey] = day
        save()
    }

    func syncSteps(_ steps: Int) {
        var day = careDays[todayKey] ?? CareDay(dayKey: todayKey)
        day.steps = max(0, steps)
        careDays[todayKey] = day
        // Written by a tracker, not by the person. A fresh install that reads a
        // step count before sign-in finishes must not be credited with holding
        // real data — that is what lets a device overwrite an account.
        save(markingUserData: false)
    }

    /// Backfills step counts for past days without touching anything else on
    /// those records.
    func mergeSteps(_ stepsByDay: [String: Int], keepHighestToday: Bool = true) {
        guard !stepsByDay.isEmpty else { return }
        for (key, steps) in stepsByDay {
            var day = careDays[key] ?? CareDay(dayKey: key)
            // Today is still being counted, and a sync that catches the source
            // mid-import can return less than it did a minute ago — which made
            // the step count visibly go *down* during the day. Keep the higher
            // figure for today only.
            //
            // Past days stay a straight overwrite: there the source is
            // authoritative and a correction should be allowed to reduce the
            // number, which a max() would silently block forever.
            let incoming = max(0, steps)
            day.steps = key == todayKey && keepHighestToday
                ? max(day.steps, incoming)
                : incoming
            careDays[key] = day
        }
        save(markingUserData: false)
    }

    // MARK: - Health Mutations

    /// How much health history to keep. The whole `StateSnapshot` is uploaded as
    /// a single Firestore document with a 1 MB ceiling, and `healthDays` is the
    /// one collection that grows by a record every day forever — so it gets a
    /// hard cap rather than being allowed to creep up on the limit.
    private static let healthDayRetention = 400

    /// Merges a sync into stored history field by field, so a short 7-day pull
    /// never blanks values an earlier full import found. Only non-nil incoming
    /// values overwrite.
    func mergeHealthDays(_ days: [HealthDay]) {
        guard !days.isEmpty else { return }

        for incoming in days where !incoming.dayKey.isEmpty {
            let existing = healthDays[incoming.dayKey] ?? HealthDay(dayKey: incoming.dayKey)
            healthDays[incoming.dayKey] = HealthDay.merging(incoming, onto: existing)
        }

        pruneHealthDays()
        save(markingUserData: false)
    }

    /// Stores a day's heart-rate range and mean, derived from the sample curve
    /// that `HeartRateStore` holds in memory.
    ///
    /// Writes only when a figure actually moved. This is called after every
    /// poll while the Health tab is open, and saving on each tick would push a
    /// Firestore write a minute for numbers that barely change.
    func recordHeartRateAggregates(dayKey: String, min: Double, max: Double, average: Double) {
        guard !dayKey.isEmpty else { return }
        var day = healthDays[dayKey] ?? HealthDay(dayKey: dayKey)

        let rounded = (min.rounded(), max.rounded(), (average * 10).rounded() / 10)
        guard day.hrMin != rounded.0 || day.hrMax != rounded.1 || day.hrAverage != rounded.2 else {
            return
        }
        day.hrMin = rounded.0
        day.hrMax = rounded.1
        day.hrAverage = rounded.2
        healthDays[dayKey] = day
        save(markingUserData: false)
    }

    /// Hypnogram segments are roughly thirty records a night against a handful
    /// of numbers on `HealthDay`, so they get a much shorter memory. A year of
    /// them would be most of the 1 MB Firestore document on its own.
    private static let sleepNightRetention = 30

    /// Replaces stored nights outright rather than merging field by field: a
    /// night's stage list is a single indivisible reading, and a re-sync of the
    /// same night should supersede it, not interleave with it.
    func mergeSleepNights(_ nights: [SleepNight]) {
        guard !nights.isEmpty else { return }
        for night in nights where !night.dayKey.isEmpty && !night.segments.isEmpty {
            sleepNights[night.dayKey] = night
        }
        if sleepNights.count > Self.sleepNightRetention {
            let keep = Set(sleepNights.keys.sorted().suffix(Self.sleepNightRetention))
            sleepNights = sleepNights.filter { keep.contains($0.key) }
        }
        save(markingUserData: false)
    }

    // MARK: - Sleep score comparisons

    /// Saves a manually entered Google Health score for a night.
    ///
    /// Returns the reason it was refused, or nil on success. Validation lives in
    /// `SleepComparisonValidator` so the same rules apply here and at training
    /// time.
    @discardableResult
    func saveSleepComparison(googleScore: Int, for day: HealthDay) -> SleepComparisonValidator.Rejection? {
        let baselines = SleepFeatureBuilder.baselines(from: healthHistory, excluding: day.dayKey)
        let features = SleepFeatureBuilder.features(for: day, history: healthHistory, baselines: baselines)

        // Editing an existing entry is allowed; only a *new* duplicate is not.
        var existing = sleepComparisons
        existing.removeValue(forKey: day.dayKey)
        if let rejection = SleepComparisonValidator.validateEntry(
            googleScore: googleScore, features: features, existing: existing
        ) { return rejection }

        guard let result = SleepScore.calculate(features: features, baselines: baselines) else {
            return .missingStages
        }

        sleepComparisons[day.dayKey] = SleepScoreComparison(
            features: features, result: result, googleScore: googleScore
        )
        save()
        return nil
    }

    func removeSleepComparison(for dayKey: String) {
        guard sleepComparisons[dayKey] != nil else { return }
        sleepComparisons.removeValue(forKey: dayKey)
        save()
    }

    /// The calibration model fitted from currently valid comparisons.
    ///
    /// Re-validated on every fit rather than trusting what was stored: a night
    /// can be reprocessed by the source after a score was entered, and training
    /// on a stale pairing teaches the wrong correction.
    var sleepCalibrationModel: SleepScoreCalibration.Model {
        let history = healthHistory
        var featuresByDay: [String: SleepFeatures] = [:]
        for day in history where sleepComparisons[day.dayKey] != nil {
            let baselines = SleepFeatureBuilder.baselines(from: history, excluding: day.dayKey)
            featuresByDay[day.dayKey] = SleepFeatureBuilder.features(
                for: day, history: history, baselines: baselines
            )
        }
        let valid = SleepComparisonValidator.validTrainingSet(
            Array(sleepComparisons.values), featuresByDay: featuresByDay
        )
        return SleepScoreCalibration.fit(valid)
    }

    private func pruneHealthDays() {
        guard healthDays.count > Self.healthDayRetention else { return }
        let keep = Set(healthDays.keys.sorted().suffix(Self.healthDayRetention))
        healthDays = healthDays.filter { keep.contains($0.key) }
    }

    func setCoachSettings(_ transform: (inout CoachSettings) -> Void) {
        transform(&coachSettings)
        save()
    }

    /// Records what someone did with a suggestion.
    ///
    /// The only writer of `coachFeedback`, and it is called from the same taps
    /// that accept or dismiss a proposal — never inferred, never written on the
    /// app's own initiative. `TrainingMemory` reads it back as score
    /// adjustments, so this is the mechanism by which saying no three times
    /// actually means something.
    func recordFeedback(
        _ outcome: CoachFeedbackEntry.Outcome,
        source: CoachFeedbackEntry.Source,
        exerciseId: String? = nil
    ) {
        coachFeedback.append(
            CoachFeedbackEntry(source: source, outcome: outcome, exerciseId: exerciseId)
        )
        // Bounded. This is a preference signal, not an audit log, and
        // `TrainingMemory` ignores anything older than four months anyway.
        if coachFeedback.count > 500 {
            coachFeedback.removeFirst(coachFeedback.count - 500)
        }
        save()
    }

    func setHealthSettings(_ transform: (inout HealthSettings) -> Void) {
        transform(&healthSettings)
        save()
    }

    // MARK: - Settings Mutations

    func setName(_ name: String) {
        userName = name
        save()
    }

    func setCareSettings(_ settings: CareSettings) {
        careSettings = settings
        save()
    }

    func setWorkoutSettings(_ settings: WorkoutSettings) {
        workoutSettings = settings
        save()
    }

    // MARK: - Exercise Mutations

    func addCustomExercise(name: String, muscle: String, kind: ExerciseKind,
                            equipment: ExerciseEquipment = .barbell,
                            movementType: MovementType = .compound) {
        let exercise = Exercise(name: name, muscle: muscle, kind: kind, isCustom: true,
                                equipment: equipment, movementType: movementType)
        exercises.append(exercise)
        save()
    }

    // MARK: - Previous Session Helpers

    func previousSets(for exerciseId: String) -> [LoggedSet] {
        let finished = sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        for session in finished {
            if let ex = session.exercises.first(where: { $0.exerciseId == exerciseId }) {
                let done = ex.sets.filter(\.done)
                if !done.isEmpty { return done }
            }
        }
        return []
    }

    func suggestedWeight(for exerciseId: String) -> Double {
        previousSets(for: exerciseId).first?.weight ?? 0
    }

    func suggestedReps(for exerciseId: String) -> Int {
        previousSets(for: exerciseId).first?.reps ?? 0
    }

    // MARK: - Workout Analytics

    /// A session counts as a real workout only if it's finished AND has at least
    /// one completed set. Excludes empty/accidental finishes so counts aren't
    /// inflated (all-time total, this-week, streak, achievements all use this).
    var completedWorkouts: [WorkoutSession] {
        sessions.filter { $0.finishedAt != nil && $0.totalSets > 0 }
    }

    var workoutStreak: Int {
        let finished = completedWorkouts
        guard !finished.isEmpty else { return 0 }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dayKeys = Set(finished.compactMap { $0.finishedAt }.map { cal.startOfDay(for: $0) })
        // Start from today; if no workout today, start from yesterday so streak persists until midnight
        var checkDate = dayKeys.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0
        while dayKeys.contains(checkDate) {
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    func volumeThisWeekByMuscle() -> [(muscle: String, volumeKg: Double)] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let thisWeek = sessions.filter {
            guard let fin = $0.finishedAt else { return false }
            return fin >= weekStart
        }
        var map: [String: Double] = [:]
        for session in thisWeek {
            for ex in session.exercises {
                guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }) else { continue }
                let vol = ex.sets.filter(\.done).reduce(0.0) { $0 + $1.weight * Double($1.reps) }
                map[exercise.muscle, default: 0] += vol
            }
        }
        return map.map { (muscle: $0.key, volumeKg: $0.value) }
            .sorted { $0.volumeKg > $1.volumeKg }
    }

    /// Completed sets per muscle so far this (calendar) week.
    func setsThisWeekByMuscle() -> [(muscle: String, sets: Int)] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let thisWeek = sessions.filter {
            guard let fin = $0.finishedAt else { return false }
            return fin >= weekStart
        }
        var map: [String: Int] = [:]
        for session in thisWeek {
            for ex in session.exercises {
                guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }) else { continue }
                let sets = ex.sets.filter(\.done).count
                guard sets > 0 else { continue }
                map[exercise.muscle, default: 0] += sets
            }
        }
        return map.map { (muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets > $1.sets }
    }

    /// Weekly set-volume landmarks per muscle group for hypertrophy —
    /// roughly minimum-effective to near-maximum-recoverable volume, per
    /// commonly cited strength & conditioning volume landmarks (e.g.
    /// Renaissance Periodization / Schoenfeld-style guidance). "Legs" here
    /// covers both quads and hamstrings, so its range sits higher than a
    /// single-muscle target would.
    private static let weeklySetTargets: [String: (min: Int, max: Int)] = [
        "Chest":     (10, 20),
        "Back":      (10, 20),
        "Shoulders": (8, 16),
        "Biceps":    (8, 14),
        "Triceps":   (8, 14),
        "Legs":      (12, 20),
        "Glutes":    (6, 16),
        "Calves":    (8, 16),
        "Core":      (0, 15),
    ]

    func weeklySetTarget(forMuscle muscle: String) -> (min: Int, max: Int) {
        Self.weeklySetTargets[muscle] ?? (8, 16)
    }

    // MARK: - Progressive Overload

    enum OverloadSuggestion: Equatable {
        case addWeight(by: Double)
        case addReps
        case addSet
        case deload
        case maintain

        var label: String {
            switch self {
            case .addWeight(let by): return "+\(by.formatted1)kg"
            case .addReps:           return "+1 rep"
            case .addSet:            return "+1 set"
            case .deload:            return "Deload"
            case .maintain:          return "Maintain"
            }
        }
        var icon: String {
            switch self {
            case .addWeight: return "arrow.up.circle.fill"
            case .addReps:   return "plus.circle.fill"
            case .addSet:    return "square.stack.fill"
            case .deload:    return "arrow.down.circle.fill"
            case .maintain:  return "equal.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .addWeight: return AppTheme.primary
            case .addReps:   return .blue
            case .addSet:    return .orange
            case .deload:    return .red
            case .maintain:  return .secondary
            }
        }
    }

    func progressiveOverloadSuggestion(for exerciseId: String, targetRepMax: Int) -> OverloadSuggestion {
        let pastSets: [[LoggedSet]] = sessions
            .filter { $0.finishedAt != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
            .compactMap { session in
                guard let ex = session.exercises.first(where: { $0.exerciseId == exerciseId }) else { return nil }
                let working = ex.sets.filter { $0.done && $0.kind.countsAsWorkingSet }
                return working.isEmpty ? nil : working
            }

        guard let recent = pastSets.first, !recent.isEmpty else { return .addWeight(by: 2.5) }

        let avgReps = Double(recent.map(\.reps).reduce(0, +)) / Double(recent.count)
        let maxWeight = recent.map(\.weight).max() ?? 0

        if pastSets.count >= 3 {
            let weights = pastSets.prefix(3).map { $0.map(\.weight).max() ?? 0 }
            let reps    = pastSets.prefix(3).map { $0.map(\.reps).reduce(0, +) }
            if weights[0] == weights[1] && weights[1] == weights[2] &&
               reps[0] <= reps[1] && reps[1] <= reps[2] {
                return .deload
            }
        }

        if avgReps >= Double(targetRepMax) {
            return .addWeight(by: maxWeight >= 100 ? 5.0 : 2.5)
        }
        if avgReps >= Double(targetRepMax) - 1.5 {
            return .addReps
        }
        if pastSets.count >= 2 {
            let prevAvg = Double(pastSets[1].map(\.reps).reduce(0, +)) / Double(pastSets[1].count)
            if abs(avgReps - prevAvg) < 1 { return .addSet }
        }
        return .maintain
    }

    // MARK: - Muscle Recovery

    enum RecoveryStatus {
        case fresh, recovered, recovering, fatigued
        var label: String {
            switch self {
            case .fresh:      return "Fresh"
            case .recovered:  return "Ready"
            case .recovering: return "Recovering"
            case .fatigued:   return "Fatigued"
            }
        }
        var color: Color {
            switch self {
            case .fresh:      return Color(.tertiaryLabel)
            case .recovered:  return AppTheme.primary
            case .recovering: return .orange
            case .fatigued:   return .red
            }
        }
    }

    func daysSinceLastTrained(muscle: String) -> Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for session in sessions.filter({ $0.finishedAt != nil })
            .sorted(by: { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }) {
            // Starting a routine pre-populates every one of its exercises as a
            // session entry, even ones never actually performed — only count
            // it if at least one set was completed, or every muscle in that
            // routine would register as "trained today" regardless of what
            // was actually done.
            let hit = session.exercises.contains { ex in
                guard ex.sets.contains(where: \.done) else { return false }
                return exercises.first(where: { $0.id == ex.exerciseId })?.muscle == muscle
            }
            if hit, let fin = session.finishedAt {
                return cal.dateComponents([.day], from: cal.startOfDay(for: fin), to: today).day ?? 0
            }
        }
        return nil
    }

    struct MuscleTrainingInfo {
        let sessionId: String
        let daysAgo: Int
        let completedSets: Int
        /// Σ weight × reps across completed sets (Σ reps alone for bodyweight
        /// exercises, where weight is 0) — the actual load moved for this
        /// muscle in its most recent trained session.
        let volume: Double
        /// (completed sets, volume moved, exercise kind), in the order first encountered.
        /// `kind` lets UI skip showing a weight figure for bodyweight/cardio exercises.
        let exerciseBreakdown: [(name: String, sets: Int, volume: Double, kind: ExerciseKind)]
    }

    private func setVolume(_ set: LoggedSet) -> Double {
        set.weight > 0 ? set.weight * Double(set.reps) : Double(set.reps)
    }

    /// Total volume (Σ weight × reps of completed sets) moved for `muscle`
    /// in one session.
    private func sessionVolume(_ session: WorkoutSession, muscle: String) -> Double {
        session.exercises.reduce(0) { total, ex in
            guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }), exercise.muscle == muscle else { return total }
            return total + ex.sets.filter(\.done).reduce(0) { $0 + setVolume($1) }
        }
    }

    /// Like `daysSinceLastTrained`, but also reports how much was actually
    /// done (sets + volume per exercise) in that most recent session, so
    /// recovery UI can show a real metric (e.g. "2 sets of Bicep Curls · 60kg")
    /// instead of just a day count, and scale fatigue by how much was moved
    /// rather than treating one light set the same as a full session.
    func lastTrainingInfo(muscle: String) -> MuscleTrainingInfo? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for session in sessions.filter({ $0.finishedAt != nil })
            .sorted(by: { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }) {
            var totalSets = 0
            var totalVolume: Double = 0
            var setsByName: [String: Int] = [:]
            var volumeByName: [String: Double] = [:]
            var kindByName: [String: ExerciseKind] = [:]
            var order: [String] = []
            for ex in session.exercises {
                guard let exercise = exercises.first(where: { $0.id == ex.exerciseId }),
                      exercise.muscle == muscle else { continue }
                let doneSets = ex.sets.filter(\.done)
                guard !doneSets.isEmpty else { continue }
                totalSets += doneSets.count
                let vol = doneSets.reduce(0) { $0 + setVolume($1) }
                totalVolume += vol
                if setsByName[exercise.name] == nil { order.append(exercise.name) }
                setsByName[exercise.name, default: 0] += doneSets.count
                volumeByName[exercise.name, default: 0] += vol
                kindByName[exercise.name] = exercise.kind
            }
            guard totalSets > 0, let fin = session.finishedAt else { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: fin), to: today).day ?? 0
            return MuscleTrainingInfo(
                sessionId: session.id,
                daysAgo: days,
                completedSets: totalSets,
                volume: totalVolume,
                exerciseBreakdown: order.map { ($0, setsByName[$0] ?? 0, volumeByName[$0] ?? 0, kindByName[$0] ?? .weight) }
            )
        }
        return nil
    }

    /// Highest single-session volume ever recorded for `muscle`, used to
    /// express a session's intensity as "how much of your best effort was
    /// this" rather than an arbitrary absolute threshold. Excludes
    /// `excludingSessionId` (the session currently being evaluated) so it's a
    /// genuine comparison against prior history rather than including itself.
    func personalBestVolume(muscle: String, excludingSessionId: String? = nil) -> Double {
        sessions
            .filter { $0.finishedAt != nil && $0.id != excludingSessionId }
            .map { sessionVolume($0, muscle: muscle) }
            .max() ?? 0
    }

    /// Typical full-recovery time (days) per muscle group. Smaller/isolation
    /// muscles (biceps, triceps, calves, core) bounce back faster than large
    /// compound groups (back, legs) that take more systemic recovery,
    /// per common strength & conditioning / DOMS recovery guidance. Any
    /// muscle not listed falls back to a 2-day default.
    private static let muscleRecoveryDays: [String: Double] = [
        "Biceps":    1.5,
        "Triceps":   1.5,
        "Calves":    1.5,
        "Core":      1.5,
        "Shoulders": 2.0,
        "Chest":     2.5,
        "Glutes":    2.5,
        "Back":      3.0,
        "Legs":      3.0,
    ]

    func recoveryDays(forMuscle muscle: String) -> Double {
        Self.muscleRecoveryDays[muscle] ?? 2.0
    }

    func recoveryStatus(muscle: String) -> RecoveryStatus {
        guard let days = daysSinceLastTrained(muscle: muscle) else { return .fresh }
        if days == 0 { return .fatigued }
        return Double(days) < recoveryDays(forMuscle: muscle) ? .recovering : .recovered
    }

    // MARK: - Weekly Sessions Calendar

    func sessionsThisWeek() -> [Date: [WorkoutSession]] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
        var map: [Date: [WorkoutSession]] = [:]
        for session in sessions where session.finishedAt != nil {
            guard let fin = session.finishedAt, fin >= weekStart, fin < weekEnd else { continue }
            let day = cal.startOfDay(for: fin)
            map[day, default: []].append(session)
        }
        return map
    }

    // MARK: - XP / Level

    var xpPoints: Int {
        return completedWorkouts.count * 100 + workoutStreak * 10 + achievements.count * 50
    }
    var xpLevel: Int  { xpPoints / 500 + 1 }
    var xpProgress: Double { Double(xpPoints % 500) / 500.0 }

    // MARK: - Progress Screen Helpers

    struct DatedValue: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    struct MuscleCount: Identifiable {
        let id = UUID()
        let muscle: String
        let count: Int
    }

    private var weekStartDate: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    }

    private var finishedSessionsSorted: [WorkoutSession] {
        completedWorkouts
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
    }

    var workoutsThisWeekCount: Int {
        let start = weekStartDate
        return completedWorkouts.filter { ($0.finishedAt ?? .distantPast) >= start }.count
    }

    var trainingSecondsThisWeek: Int {
        let start = weekStartDate
        return sessions
            .filter { ($0.finishedAt ?? .distantPast) >= start }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    var volumeThisWeekKg: Double {
        let start = weekStartDate
        return sessions
            .filter { ($0.finishedAt ?? .distantPast) >= start }
            .reduce(0.0) { $0 + $1.totalVolumeKg }
    }

    func recentFinishedSessions(limit: Int = 5) -> [WorkoutSession] {
        Array(finishedSessionsSorted.prefix(limit))
    }

    /// Muscle → number of sets logged this week, sorted by volume.
    func muscleCountsThisWeek() -> [MuscleCount] {
        let start = weekStartDate
        var counts: [String: Int] = [:]
        for session in sessions where (session.finishedAt ?? .distantPast) >= start {
            for ex in session.exercises {
                guard let muscle = exercises.first(where: { $0.id == ex.exerciseId })?.muscle else { continue }
                counts[muscle, default: 0] += ex.sets.filter(\.done).count
            }
        }
        return counts.map { MuscleCount(muscle: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Exercises performed most often across all finished sessions.
    func topExercises(limit: Int = 6) -> [Exercise] {
        var counts: [String: Int] = [:]
        for session in sessions where session.finishedAt != nil {
            for ex in session.exercises { counts[ex.exerciseId, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }
            .compactMap { pair in exercises.first { $0.id == pair.key } }
            .prefix(limit)
            .map { $0 }
    }

    /// Estimated 1RM per session over time for an exercise (oldest first).
    func oneRMHistory(for exerciseId: String) -> [DatedValue] {
        var points: [DatedValue] = []
        for session in finishedSessionsSorted.reversed() {
            guard let fin = session.finishedAt else { continue }
            var best1RM = 0.0
            for ex in session.exercises where ex.exerciseId == exerciseId {
                for set in ex.sets where set.done && set.kind.countsAsWorkingSet {
                    best1RM = max(best1RM, set.weight * (1 + Double(set.reps) / 30.0))
                }
            }
            if best1RM > 0 { points.append(DatedValue(date: fin, value: best1RM)) }
        }
        return points
    }

    /// Improvement in all-time best 1RM contributed by the most recent session.
    func prDelta(for exerciseId: String) -> Double {
        let history = oneRMHistory(for: exerciseId)
        guard history.count >= 2 else { return 0 }
        let allTime = history.map(\.value).max() ?? 0
        let priorBest = history.dropLast().map(\.value).max() ?? 0
        return max(0, allTime - priorBest)
    }

    // Body helpers
    var latestWeightKg: Double? { weightEntries.sorted { $0.date > $1.date }.first?.valueKg }

    var weightChangeKg: Double? {
        let sorted = weightEntries.sorted { $0.date > $1.date }
        guard sorted.count >= 2 else { return nil }
        return sorted[0].valueKg - sorted[1].valueKg
    }

    var latestBodyFatPct: Double? {
        bodyCompEntries.sorted { $0.date > $1.date }.first { $0.bodyFatPct != nil }?.bodyFatPct
    }

    var latestLeanMassKg: Double? {
        bodyCompEntries.sorted { $0.date > $1.date }.first { $0.leanMassKg != nil }?.leanMassKg
    }

    func weightTrend(days: Int) -> [DatedValue] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return weightEntries
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .map { DatedValue(date: $0.date, value: $0.valueKg) }
    }

    // MARK: - Body Measurements

    /// Records a set of circumferences, dropping any that aren't positive and
    /// plausible. A measurement of 0 or -30 cm is a typo, not a reading.
    func addBodyMeasurement(_ measurement: BodyMeasurement) {
        func valid(_ value: Double?) -> Double? {
            value.flatMap { BodyMetricLimits.validate($0, in: BodyMetricLimits.measurementCm) }
        }

        var m = measurement
        m.chestCm = valid(measurement.chestCm)
        m.waistCm = valid(measurement.waistCm)
        m.hipsCm = valid(measurement.hipsCm)
        m.leftArmCm = valid(measurement.leftArmCm)
        m.rightArmCm = valid(measurement.rightArmCm)
        m.leftThighCm = valid(measurement.leftThighCm)
        m.rightThighCm = valid(measurement.rightThighCm)
        m.neckCm = valid(measurement.neckCm)
        m.shouldersCm = valid(measurement.shouldersCm)

        let values = [m.chestCm, m.waistCm, m.hipsCm, m.leftArmCm, m.rightArmCm,
                      m.leftThighCm, m.rightThighCm, m.neckCm, m.shouldersCm]
        guard values.contains(where: { $0 != nil }) else { return }

        bodyMeasurements.append(m)
        bodyMeasurements.sort { $0.date > $1.date }
        save()
    }

    func deleteBodyMeasurement(id: String) {
        bodyMeasurements.removeAll { $0.id == id }
        save()
    }

    // MARK: - Achievements

    func checkAndGrantAchievements() {
        let finishedSessions = completedWorkouts
        let totalSets = finishedSessions.reduce(0) { $0 + $1.totalSets }
        let unlocked = Set(achievements.map(\.kind))

        func grant(_ kind: AchievementKind, detail: String = "") {
            guard !unlocked.contains(kind) else { return }
            achievements.append(Achievement(kind: kind, title: kind.title, detail: detail))
        }

        if !finishedSessions.isEmpty { grant(.firstWorkout) }
        if workoutStreak >= 7 { grant(.streak7) }
        if workoutStreak >= 30 { grant(.streak30) }
        if totalSets >= 100 { grant(.totalSets100) }
        if totalSets >= 1000 { grant(.totalSets1000) }
        if finishedSessions.count >= 10 { grant(.totalSessions10) }
        if finishedSessions.count >= 50 { grant(.totalSessions50) }
        if finishedSessions.count >= 100 { grant(.totalSessions100) }

        // 4-week consistency: worked out in at least 3 of the past 4 calendar weeks
        let cal = Calendar.current
        let now = Date()
        let weeksWithWorkout = (0..<4).filter { weekOffset in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: now),
                  let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else { return false }
            return finishedSessions.contains { s in
                guard let fin = s.finishedAt else { return false }
                return fin >= weekStart && fin < weekEnd
            }
        }.count
        if weeksWithWorkout >= 3 { grant(.consistency4Weeks) }

        // Volume PR: check if most recent session has a higher total volume than any previous session
        if let latest = finishedSessions.max(by: { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }) {
            let previousMax = finishedSessions
                .filter { $0.id != latest.id }
                .map(\.totalVolumeKg)
                .max() ?? 0
            if latest.totalVolumeKg > previousMax && latest.totalVolumeKg > 0 {
                grant(.volumePR, detail: "\(Int(latest.totalVolumeKg))kg total volume")
            }
        }
    }

    // MARK: - PR Computation

    struct PRResult {
        var bestWeight: Double
        var bestReps: Int
        var best1RM: Double
    }

    func computePRs(for exerciseId: String) -> PRResult {
        var bestWeight: Double = 0
        var bestReps: Int = 0
        var best1RM: Double = 0

        for session in sessions where session.finishedAt != nil {
            for exercise in session.exercises where exercise.exerciseId == exerciseId {
                for set in exercise.sets where set.done && set.kind.countsAsWorkingSet {
                    if set.weight > bestWeight {
                        bestWeight = set.weight
                        bestReps = set.reps
                    }
                    // Epley formula: 1RM = weight * (1 + reps/30)
                    let estimated1RM = set.weight * (1 + Double(set.reps) / 30.0)
                    if estimated1RM > best1RM {
                        best1RM = estimated1RM
                    }
                }
            }
        }
        return PRResult(bestWeight: bestWeight, bestReps: bestReps, best1RM: best1RM)
    }

    // MARK: - Workout Programs

    func addProgram(name: String, days: [ProgramDay] = []) {
        let prog = WorkoutProgram(name: name, days: days)
        programs.append(prog)
        save()
    }

    func updateProgram(id: String, name: String, days: [ProgramDay]) {
        guard let idx = programs.firstIndex(where: { $0.id == id }) else { return }
        programs[idx].name = name
        programs[idx].days = days
        save()
    }

    func deleteProgram(id: String) {
        programs.removeAll { $0.id == id }
        save()
    }

    func setActiveProgram(id: String?) {
        for idx in programs.indices {
            programs[idx].isActive = programs[idx].id == id
        }
        save()
    }

    var activeProgram: WorkoutProgram? {
        programs.first { $0.isActive }
    }

    func todaysSuggestedRoutine() -> Routine? {
        guard let prog = activeProgram else { return nil }
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday: 1=Sunday, convert to 1=Monday
        let mondayBased = weekday == 1 ? 7 : weekday - 1
        guard let day = prog.days.first(where: { $0.weekday == mondayBased }),
              let routineId = day.routineId else { return nil }
        return routines.first { $0.id == routineId }
    }

    // MARK: - Weekly Workout Counts (P3.3)

    private static let weekLabelFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    func weeklyWorkoutCounts(weeks: Int) -> [(weekLabel: String, count: Int)] {
        let cal = Calendar.current
        let now = Date()
        let fmt = Self.weekLabelFmt
        return (0..<weeks).reversed().map { offset in
            let weekAgo = cal.date(byAdding: .weekOfYear, value: -offset, to: now) ?? now
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekAgo)) ?? weekAgo
            let weekEnd   = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            let count = completedWorkouts.filter {
                guard let fin = $0.finishedAt else { return false }
                return fin >= weekStart && fin < weekEnd
            }.count
            return (weekLabel: fmt.string(from: weekStart), count: count)
        }
    }

    // MARK: - Planned Sessions

    func planSession(date: Date, routineId: String?, name: String) {
        let plan = PlannedSession(
            date: Calendar.current.startOfDay(for: date),
            routineId: routineId,
            routineName: name
        )
        plannedSessions.append(plan)
        save()
    }

    /// Applies an accepted progression to every routine holding this exercise.
    ///
    /// Updates the *stored prescription*, not the finished workout. A completed
    /// session is a record of what happened and editing it retrospectively would
    /// make the history a fiction — the progression changes what you are asked
    /// to do next time, which is a different thing.
    ///
    /// Only ever called from `ProgressionReviewSheet`, from a tap.
    func applyProgression(exerciseId: String, weight: Double, reps: Int) {
        var changed = false

        for routineIndex in routines.indices {
            for exerciseIndex in routines[routineIndex].exercises.indices
            where routines[routineIndex].exercises[exerciseIndex].exerciseId == exerciseId {
                routines[routineIndex].exercises[exerciseIndex].defaultWeight = weight
                routines[routineIndex].exercises[exerciseIndex].defaultReps = reps
                changed = true
            }
        }

        // One save for the lot, and none at all when the exercise isn't in any
        // routine — accepting a suggestion for a one-off exercise shouldn't
        // write a snapshot for nothing.
        if changed { save() }
    }

    /// Writes a generated programme in one pass.
    ///
    /// A plan is N routines, one programme and up to M dated sessions. Building
    /// it out of `addRoutine`, `addProgram` and `planSession` would call `save()`
    /// fifteen times and, if anything interrupted it halfway, leave orphan
    /// routines with no programme pointing at them — visible in the routine list,
    /// belonging to nothing, and impossible for the user to explain.
    ///
    /// Everything is appended together and saved once, so a generated plan is
    /// either entirely present or entirely absent.
    ///
    /// Only ever called from `WorkoutBuilderActions.commit`, which is only ever
    /// reached from an explicit tap.
    func applyGeneratedPlan(
        routines newRoutines: [Routine],
        program: WorkoutProgram?,
        plannedSessions newSessions: [PlannedSession],
        makeActive: Bool
    ) {
        routines.append(contentsOf: newRoutines)

        if let program {
            programs.append(program)
            if makeActive {
                for index in programs.indices {
                    programs[index].isActive = programs[index].id == program.id
                }
            }
        }

        plannedSessions.append(contentsOf: newSessions)
        save()
    }

    func deletePlannedSession(id: String) {
        plannedSessions.removeAll { $0.id == id }
        save()
    }

    // MARK: - Progress Photos (stored separately, not cloud-synced)
    //
    // Storage layout:
    //   - Image bytes: one JPEG per photo under Documents/progress_photos/<id>.jpg
    //   - Metadata only (id, date, label) in UserDefaults under photosKeyV2
    //
    // Rationale: UserDefaults isn't designed for large blobs. With raw camera
    // photos (~5–10 MB each), the previous design re-encoded and re-wrote the
    // entire array on every add/delete and risked silent truncation. Each
    // image is also compressed to ~500 KB at insert time.

    private let photosKey = "life_progress_photos_v1"     // legacy (full bytes)
    private let photosKeyV2 = "life_progress_photos_v2"   // metadata only

    private struct ProgressPhotoMetadata: Codable {
        var id: String
        var date: Date
        var label: String
    }

    private static let photoDirectory: URL = {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("progress_photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func photoURL(for id: String) -> URL {
        Self.photoDirectory.appendingPathComponent("\(id).jpg")
    }

    /// Down-scale the image and re-encode as JPEG so we don't store
    /// multi-megabyte camera originals on disk.
    private static func compressedJPEG(from data: Data, maxDimension: CGFloat = 2000, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1.0
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: quality)
    }

    func addProgressPhoto(imageData: Data, label: String) {
        let compressed = Self.compressedJPEG(from: imageData) ?? imageData
        let photo = ProgressPhoto(date: Date(), label: label, imageData: compressed)
        progressPhotos.append(photo)
        try? compressed.write(to: photoURL(for: photo.id), options: .atomic)
        saveMetadata()
    }

    func deleteProgressPhoto(id: String) {
        progressPhotos.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: photoURL(for: id))
        saveMetadata()
    }

    private func saveMetadata() {
        let metadata = progressPhotos.map {
            ProgressPhotoMetadata(id: $0.id, date: $0.date, label: $0.label)
        }
        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: photosKeyV2)
        }
    }

    func loadPhotos() {
        // Prefer the v2 metadata-only format.
        if let data = UserDefaults.standard.data(forKey: photosKeyV2),
           let metadata = try? JSONDecoder().decode([ProgressPhotoMetadata].self, from: data) {
            progressPhotos = metadata.compactMap { meta in
                guard let bytes = try? Data(contentsOf: photoURL(for: meta.id)) else { return nil }
                return ProgressPhoto(id: meta.id, date: meta.date, label: meta.label, imageData: bytes)
            }
            return
        }
        // Legacy migration: pull from v1 (full bytes in UserDefaults) and rewrite to disk.
        if let data = UserDefaults.standard.data(forKey: photosKey),
           let legacy = try? JSONDecoder().decode([ProgressPhoto].self, from: data) {
            progressPhotos = legacy
            for photo in legacy {
                try? photo.imageData.write(to: photoURL(for: photo.id), options: .atomic)
            }
            saveMetadata()
            UserDefaults.standard.removeObject(forKey: photosKey)
        }
    }

    // Backwards-compat shim; old call sites called savePhotos() directly.
    private func savePhotos() { saveMetadata() }

    // MARK: - Reset

    func resetAllData() {
        // Disable cloud sync first so the subsequent save() doesn't push the
        // empty/seed state to Firestore and wipe data on other devices.
        // User can sign in again afterwards to re-sync the reset state.
        disableCloudSync()
        tasks = []
        bills = []
        incomes = []
        oneOffExpenses = []
        moneySettings = MoneySettings()
        habits = []
        exercises = WorkoutSeed.exercises
        routines = WorkoutSeed.routines
        sessions = []
        weightEntries = []
        bodyCompEntries = []
        bodyMeasurements = []
        achievements = []
        programs = []
        careDays = [:]
        careSettings = CareSettings()
        workoutSettings = WorkoutSettings()
        userName = ""
        visitedLocations = []
        plannedSessions = []
        progressPhotos = []
        healthDays = [:]
        healthSettings = HealthSettings()
        sleepNights = [:]
        sleepComparisons = [:]
        savePhotos()
        seedDefaults()
    }

    // MARK: - Travel

    func recordVisit(lat: Double, lon: Double) {
        let newLoc = CLLocation(latitude: lat, longitude: lon)
        let tooClose = visitedLocations.contains { existing in
            let existingLoc = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
            return existingLoc.distance(from: newLoc) < 500
        }
        guard !tooClose else { return }
        visitedLocations.append(VisitedLocation(latitude: lat, longitude: lon))
        save()
    }

    // MARK: - Export

    var exportData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(makeSnapshot())
    }

    func importData(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(StateSnapshot.self, from: data)
        apply(snapshot: snapshot)
        save()
    }
}
