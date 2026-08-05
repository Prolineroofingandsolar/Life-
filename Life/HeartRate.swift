import SwiftUI

// MARK: - Samples

/// Which device measured a reading.
///
/// Kept on every sample rather than decided globally, because the two sources
/// genuinely measure at different times: the band records all day, while
/// heart-rate-capable AirPods only record during a workout. Merging them into
/// an untagged curve would make it impossible to tell which is which.
enum HeartRateSource: String, Codable, CaseIterable, Identifiable {
    case fitbit
    case appleHealth

    var id: String { rawValue }

    /// The provider, so the name shown beside a reading comes from the same
    /// mapping every other screen uses rather than being spelled out again
    /// here — which is how "Fitbit", "Google Health" and "Google Fit" ended up
    /// meaning the same thing in three different places.
    var provider: HealthProvider {
        switch self {
        case .fitbit:      return .fitbit
        case .appleHealth: return .appleHealth
        }
    }

    var label: String { provider.displayName }
}

/// One timestamped heart-rate reading.
struct HeartRateSample: Identifiable, Equatable {
    var time: Date
    var bpm: Double
    var source: HeartRateSource

    var id: String { "\(source.rawValue)-\(time.timeIntervalSince1970)" }
}

// MARK: - Zones

/// The four zones the API reports, spelled exactly as its enum does.
enum HeartRateZone: String, Codable, CaseIterable, Identifiable {
    case light = "LIGHT"
    case moderate = "MODERATE"
    case vigorous = "VIGOROUS"
    case peak = "PEAK"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light:    return "Light"
        case .moderate: return "Moderate"
        case .vigorous: return "Vigorous"
        case .peak:     return "Peak"
        }
    }

    var colour: Color {
        switch self {
        case .light:    return .blue
        case .moderate: return .green
        case .vigorous: return .orange
        case .peak:     return .red
        }
    }
}

// MARK: - Workouts

/// One exercise session, with whatever heart-rate summary the source attached.
///
/// `averageBpm` and `maximumBpm` are optional because the API's
/// `metricsSummary` doesn't reliably carry them — when they're absent the view
/// derives them from the sample curve clipped to this interval rather than
/// showing nothing.
struct ExerciseSession: Identifiable, Equatable {
    var id: String
    var start: Date
    var end: Date
    var name: String
    var activeMinutes: Int?
    var averageBpm: Double?
    var maximumBpm: Double?
    var kcal: Double?

    var minutes: Int {
        activeMinutes ?? Int((end.timeIntervalSince(start) / 60).rounded())
    }
}

// MARK: - Store

/// Heart-rate samples for one day, held **in memory only**.
///
/// Deliberately not part of `StateSnapshot`. That's a single Firestore document
/// with a 1 MB ceiling, and a day of readings is up to 1,440 points — it would
/// blow the budget inside a week. Only the cheap daily aggregates
/// (`HealthDay.hrMin` / `hrMax` / `hrAverage` and the zone minutes) are stored,
/// and losing the raw curve on relaunch costs nothing because it's re-fetched
/// in a second.
@MainActor
@Observable
final class HeartRateStore {

    static let shared = HeartRateStore()

    /// A reading older than this is reported as its age rather than as a live
    /// number, whichever source it came from. Two minutes is generous for a
    /// wrist tracker and about right for AirPods mid-workout.
    static let liveWindow: TimeInterval = 120

    /// How often the screen re-asks while it's in front of you.
    ///
    /// This does **not** make readings arrive sooner. The Fitbit decides that
    /// when it syncs over Bluetooth — typically every fifteen minutes, or when
    /// you open the Fitbit app. Polling only means a reading that has already
    /// landed appears without a manual pull.
    static let pollInterval: TimeInterval = 60

    /// Longest we'll back off to after the API pushes back. Retrying a rate
    /// limit at the same cadence just extends it.
    static let maximumBackoff: TimeInterval = 15 * 60

    private(set) var samples: [HeartRateSample] = []
    private(set) var sessions: [ExerciseSession] = []
    /// The day currently loaded, so a stale curve isn't shown past midnight.
    private(set) var dayKey: String = ""
    private(set) var isLoading = false
    /// Set when a fetch failed. Shown to the user rather than leaving the card
    /// silently empty, which reads as "no heart rate" instead of "couldn't ask".
    private(set) var message: String?

    private var pollTask: Task<Void, Never>?
    private var healthKit: HealthKitManager?
    private weak var appState: AppState?
    private var backoff: TimeInterval = 0

    private init() {}

    // MARK: Derived

    /// The newest reading from any source.
    var latest: HeartRateSample? {
        samples.max { $0.time < $1.time }
    }

    var latestAge: TimeInterval? {
        latest.map { Date().timeIntervalSince($0.time) }
    }

    /// True only when the newest reading is genuinely recent. A number from
    /// twenty minutes ago is not a current heart rate and isn't presented as
    /// one.
    var isLive: Bool {
        guard let age = latestAge else { return false }
        return age >= 0 && age <= Self.liveWindow
    }

    /// "just now" / "12 min ago" / "2 hr ago".
    var latestAgeDescription: String? {
        guard let age = latestAge else { return nil }
        if age < 90 { return "just now" }
        let minutes = Int((age / 60).rounded())
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours) hr ago" : "over a day ago"
    }

    /// Sources that actually contributed to the loaded day, for the chart's
    /// legend and for saying where the current number came from.
    var presentSources: [HeartRateSource] {
        HeartRateSource.allCases.filter { source in
            samples.contains { $0.source == source }
        }
    }

    /// Aggregates for the loaded day.
    ///
    /// Computed from one source at a time. Fitbit wins when it's present
    /// because it's the only one recording continuously — averaging it together
    /// with a burst of workout readings from AirPods would drag the daily mean
    /// upward for no good reason.
    var dailyAggregates: (min: Double, max: Double, average: Double)? {
        let source = presentSources.first ?? .fitbit
        let values = samples.filter { $0.source == source }.map(\.bpm)
        guard let low = values.min(), let high = values.max(), !values.isEmpty else { return nil }
        return (low, high, values.reduce(0, +) / Double(values.count))
    }

    /// Samples for one source, oldest first — what a chart series is drawn from.
    func series(for source: HeartRateSource) -> [HeartRateSample] {
        samples.filter { $0.source == source }.sorted { $0.time < $1.time }
    }

    /// Average and peak inside a session's interval, for a workout whose own
    /// summary carried no heart-rate figures.
    func heartRate(during session: ExerciseSession) -> (average: Double, maximum: Double)? {
        let inside = samples
            .filter { $0.time >= session.start && $0.time <= session.end }
            .map(\.bpm)
        guard let peak = inside.max(), !inside.isEmpty else { return nil }
        return (inside.reduce(0, +) / Double(inside.count), peak)
    }

    // MARK: Loading

    /// Loads both sources for a day and replaces what's held.
    ///
    /// Neither source is allowed to fail the other: AirPods readings should
    /// still appear when the Fitbit call 403s, and vice versa.
    func refresh(day: Date = Date(), healthKit: HealthKitManager? = nil, appState: AppState? = nil) async {
        if let healthKit { self.healthKit = healthKit }
        if let appState { self.appState = appState }
        let key = day.dayKey
        // A fetch already in flight for the same day is enough; a second one
        // would only race it to assign the same answer.
        guard !isLoading || key != dayKey else { return }

        isLoading = true
        defer { isLoading = false }

        var collected: [HeartRateSample] = []
        var problems: [String] = []

        if GoogleHealthService.shared.isConnected {
            do {
                collected += try await GoogleHealthService.shared.heartRateSamples(on: day)
            } catch {
                problems.append((error as? GoogleHealthError)?.errorDescription ?? error.localizedDescription)
            }
        }

        if let healthKit = self.healthKit {
            for point in await healthKit.fetchHeartRateSamples(on: day) {
                collected.append(HeartRateSample(time: point.date, bpm: point.value, source: .appleHealth))
            }
        }

        if key != dayKey {
            sessions = []
            dayKey = key
        }
        samples = collected.sorted { $0.time < $1.time }
        message = problems.first

        // Sessions are cheap and only change when a workout ends, so they ride
        // along with the sample fetch rather than getting their own timer.
        if GoogleHealthService.shared.isConnected {
            sessions = (try? await GoogleHealthService.shared.exerciseSessions(on: day)) ?? sessions
        }

        backoff = problems.isEmpty ? 0 : min(Self.maximumBackoff, max(Self.pollInterval, backoff * 2))

        if let aggregates = dailyAggregates {
            self.appState?.recordHeartRateAggregates(
                dayKey: key, min: aggregates.min, max: aggregates.max, average: aggregates.average
            )
        }
    }

    /// Records a sample delivered live by HealthKit, in between polls.
    func record(liveSamples points: [(date: Date, value: Double)]) {
        guard !points.isEmpty else { return }
        let known = Set(samples.filter { $0.source == .appleHealth }.map(\.time))
        let fresh = points
            .filter { !known.contains($0.date) && $0.date.dayKey == dayKey }
            .map { HeartRateSample(time: $0.date, bpm: $0.value, source: .appleHealth) }
        guard !fresh.isEmpty else { return }
        samples = (samples + fresh).sorted { $0.time < $1.time }
    }

    // MARK: Polling

    /// Starts refreshing while a screen is on show. Always pair with `stop()`
    /// in `onDisappear` — this must never run in the background.
    func start(healthKit: HealthKitManager, appState: AppState) {
        self.healthKit = healthKit
        self.appState = appState
        healthKit.startHeartRateUpdates { [weak self] points in
            Task { @MainActor in self?.record(liveSamples: points) }
        }

        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let wait = max(Self.pollInterval, self.backoff)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        healthKit?.stopHeartRateUpdates()
    }
}
