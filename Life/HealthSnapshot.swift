import Foundation
import CryptoKit

// MARK: - Health Snapshot

/// The one description of "how are things right now" that every screen reads.
///
/// Before this existed each consumer worked the answer out for itself. Today
/// asked `AppState` for last night's sleep, the Health tab asked
/// `HealthInsights` for a trend, the coach asked both and then applied its own
/// rules about what counted as present. They agreed most of the time, and when
/// they didn't the user was shown two contradictory statements about the same
/// morning with no way to tell which was lying:
///
/// - Today: "10h 17m slept". Ask Coach: "471 minutes".
/// - Today: no recovery data. Health: "HRV 79 ms, resting HR 59 bpm".
/// - Today: no steps. Ask Coach: steps and active minutes, both populated.
/// - A measurement plainly on screen, and a coach saying "no recovery data".
///
/// None of those were arithmetic errors. Each was a different consumer applying
/// a different rule for whether a figure existed, over a different day
/// boundary. One snapshot, built once and read everywhere, is the only fix that
/// doesn't leave the next consumer free to invent a fourth rule.
///
/// It carries no raw samples and no identity — see `CoachContext` for the
/// privacy boundary. What it adds over the stored models is *state*: not just
/// the number, but whether the number can be relied on, when it was measured,
/// and which device produced it.

/// How much a reading can be relied on.
///
/// Distinct from `MetricState`: state says what kind of thing the app holds,
/// confidence says how firmly it holds it. A fully present reading from a night
/// the band half-recorded is `.ready` and `.low` at the same time.
enum DataConfidence: String, Codable, Equatable, Sendable, CaseIterable {
    case low, medium, high
}

/// What the app actually has for one metric.
///
/// The five cases are the distinctions the brief asks to be kept apart, and
/// they exist because collapsing any two of them produces a specific wrong
/// sentence:
///
/// - `.missing` collapsed into `.insufficientHistory` → "not enough history"
///   for a tracker that was never connected.
/// - `.insufficientHistory` collapsed into `.missing` → "no recovery data"
///   printed underneath a visible HRV reading. This was the reported bug.
/// - `.stale` collapsed into `.ready` → Tuesday's figure presented as today's.
/// - `.partial` collapsed into `.ready` → firm advice from a night with three
///   hours of lost contact.
enum MetricState: String, Codable, Equatable, Sendable, CaseIterable {
    /// Nothing has ever been recorded, or nothing within the window that could
    /// possibly be relevant. There is no value to show.
    case missing

    /// A value exists, but it is older than this metric's freshness window.
    /// Worth showing — with its date — and never worth presenting as current.
    case stale

    /// A current value exists, but there aren't enough past readings to say
    /// whether it is high, low or normal *for this person*.
    ///
    /// "Not enough history to assess recovery", never "no recovery data": the
    /// measurement is right there, and denying it makes the app look broken to
    /// someone reading it off the Health tab at the same moment.
    case insufficientHistory

    /// A value exists but is incomplete — a part-recorded night, or a day still
    /// accumulating. Usable, as long as it is labelled.
    case partial

    /// A current value, with enough behind it to interpret.
    case ready

    /// Whether there is a number to put on screen at all.
    var hasValue: Bool { self != .missing }

    /// Whether the value may be stated as the current position without a
    /// qualifier attached.
    var isCurrent: Bool { self == .ready || self == .partial }
}

/// One figure, with everything needed to say it honestly.
struct HealthMetric<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {

    /// Nil whenever `state == .missing`, and only then. A present value with a
    /// `.missing` state would be a contradiction the consumers can't resolve.
    var value: Value?
    var state: MetricState
    var confidence: DataConfidence

    /// The local day this reading describes — not when it was fetched.
    var dayKey: String?
    /// The instant the reading refers to, where one is known.
    var measuredAt: Date?
    /// The device that produced it, in the app's own vocabulary.
    var source: String?

    /// How many past readings exist, and how many are needed before this metric
    /// can be compared against a baseline. Carried so a consumer can say "3 of
    /// 10 nights" rather than an unexplained refusal.
    var sampleCount: Int = 0
    var requiredSamples: Int = 0

    static var missing: Self {
        .init(value: nil, state: .missing, confidence: .low)
    }

    init(
        value: Value?,
        state: MetricState,
        confidence: DataConfidence,
        dayKey: String? = nil,
        measuredAt: Date? = nil,
        source: String? = nil,
        sampleCount: Int = 0,
        requiredSamples: Int = 0
    ) {
        // A value can never travel with `.missing`, in either direction. This
        // is the invariant every consumer relies on to decide whether to draw a
        // number, and enforcing it here means none of them has to check both.
        self.value = state == .missing ? nil : value
        self.state = value == nil ? .missing : state
        self.confidence = confidence
        self.dayKey = dayKey
        self.measuredAt = measuredAt
        self.source = source
        self.sampleCount = sampleCount
        self.requiredSamples = requiredSamples
    }
}

/// Which way a reading sits against the person's own recent norm.
enum BaselineDirection: String, Codable, Equatable, Sendable {
    case below, normal, above
}

/// A reading interpreted against a baseline — the thing readiness rests on.
struct BaselineComparison: Codable, Equatable, Sendable {
    var direction: BaselineDirection
    /// Percentage away from the person's own recent mean.
    var deltaPercent: Double
    /// False when the gap is inside ordinary day-to-day variation, so a 1%
    /// wobble is never reported as a change.
    var isMeaningful: Bool
}

// MARK: - The snapshot

struct HealthSnapshot: Codable, Equatable, Sendable {

    /// The local day this snapshot describes. Every consumer uses this key
    /// rather than recomputing one, which is what makes them agree about the
    /// day boundary even when one of them is rendered either side of midnight.
    var dayKey: String
    /// When the snapshot was assembled.
    var generatedAt: Date
    /// The zone the day boundary was drawn in, so a snapshot restored from
    /// cache in a different zone can be recognised as belonging to another day.
    var timeZoneIdentifier: String

    // MARK: Provenance

    /// The device the figures came from — "Fitbit", "Apple Health".
    var source: String?
    /// When health data last successfully arrived.
    var lastSyncedAt: Date?
    /// Metrics the last sync couldn't fetch, so a gap can be explained rather
    /// than presented as a zero.
    var syncFailures: [String] = []
    /// True when no tracker is connected at all — a different problem from a
    /// connected tracker that hasn't synced, and a different fix.
    var hasConnectedSource: Bool = false

    // MARK: Figures

    /// Last night's total sleep, in minutes. Minutes rather than a formatted
    /// string so every consumer formats it the same way through
    /// `HealthInsights.formatDuration` — the "471 minutes" in the coach's mouth
    /// came from a consumer that had the raw number and no shared formatter.
    var sleepMinutes: HealthMetric<Int> = .missing
    var sleepScore: HealthMetric<Int> = .missing
    var sleepEfficiencyPercent: HealthMetric<Int> = .missing
    var sleepVsBaselineMinutes: HealthMetric<Int> = .missing

    var hrvMs: HealthMetric<Double> = .missing
    var restingHeartRate: HealthMetric<Double> = .missing
    var readiness: HealthMetric<Int> = .missing

    var steps: HealthMetric<Int> = .missing
    var activeMinutes: HealthMetric<Int> = .missing

    /// How HRV and resting heart rate sit against their own baselines. Nil
    /// whenever the corresponding metric isn't `.ready` — a comparison needs
    /// both a reading and a baseline, and the state already says which is
    /// absent.
    var hrvBaseline: BaselineComparison?
    var restingHeartRateBaseline: BaselineComparison?

    // MARK: Derived comparisons

    /// Small, already-derived deltas, so the coach can answer "which figure
    /// changed most since yesterday?" without being sent raw history.
    var sleepChangeSinceYesterdayMinutes: Int?
    var stepsChangeSinceYesterday: Int?
    var restingHeartRateChangeSinceYesterday: Double?

    // MARK: Freshness

    /// How long after a sync the figures stop being described as current.
    ///
    /// Six hours: long enough that an overnight sync still counts at breakfast,
    /// short enough that yesterday evening's numbers are never presented as
    /// this morning's.
    static let syncFreshnessWindow: TimeInterval = 6 * 60 * 60

    /// Readings needed before a metric can be read against its own baseline.
    /// Matches `HealthInsights.minimumSamples`, named here so the snapshot can
    /// state the requirement rather than just enforce it.
    static let baselineSampleRequirement = HealthInsights.minimumSamples

    /// Whether health data has arrived recently enough to be called current.
    var isFresh: Bool {
        guard let lastSyncedAt else { return false }
        return generatedAt.timeIntervalSince(lastSyncedAt) < Self.syncFreshnessWindow
    }

    /// Whether anything at all was measured. Drives "tracker not connected"
    /// against "tracker connected, nothing through yet", which read the same on
    /// screen and need opposite advice.
    var hasAnyMeasurement: Bool {
        [sleepMinutes.state, hrvMs.state, restingHeartRate.state,
         steps.state, activeMinutes.state].contains { $0.hasValue }
    }

    // MARK: Phrasing

    /// What to say about recovery, in one sentence, given what's actually held.
    ///
    /// Centralised because this is the sentence that was wrong. Every consumer
    /// that phrased it for itself eventually produced "No recovery data" over a
    /// visible HRV reading, because "can I compute a trend?" and "do I have a
    /// measurement?" are different questions and only one of them was asked.
    var recoveryStatement: String {
        let hasMeasurement = hrvMs.state.hasValue || restingHeartRate.state.hasValue

        if !hasMeasurement {
            return hasConnectedSource
                ? "No recovery data yet — nothing recorded for HRV or resting heart rate."
                : "No recovery data — no tracker is connected."
        }

        if readiness.state == .ready || readiness.state == .partial {
            return "Recovery assessed from HRV and resting heart rate."
        }

        if hrvMs.state == .stale && restingHeartRate.state == .stale {
            return "Recovery figures are from \(staleDescription(hrvMs)) — not today's."
        }

        // The measurement is present and current; what's missing is the past to
        // read it against.
        let samples = max(hrvMs.sampleCount, restingHeartRate.sampleCount)
        let required = max(hrvMs.requiredSamples, restingHeartRate.requiredSamples)
        if required > 0 {
            return "Not enough history to assess recovery — \(samples) of \(required) nights recorded."
        }
        return "Not enough history to assess recovery."
    }

    private func staleDescription<V: Codable & Equatable & Sendable>(_ metric: HealthMetric<V>) -> String {
        metric.dayKey ?? "an earlier day"
    }

    /// A one-line freshness statement for the greeting row.
    var freshnessStatement: String {
        guard hasConnectedSource else { return "No tracker connected" }
        guard let lastSyncedAt else { return "Waiting for first sync" }

        let name = source ?? "Tracker"
        let elapsed = generatedAt.timeIntervalSince(lastSyncedAt)
        if elapsed < 5 * 60 { return "\(name) · just now" }
        if elapsed < Self.syncFreshnessWindow {
            return "\(name) · updated \(lastSyncedAt.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInToday(lastSyncedAt) {
            return "\(name) · last updated \(lastSyncedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "\(name) · last updated \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    // MARK: Identity

    /// A hash of everything that could change advice built on this snapshot.
    ///
    /// **Every timestamp is stripped first**, and that is the point rather than
    /// an optimisation. A sync stamps `lastSyncedAt` whether or not it brought
    /// anything back, so a hash that included it would change on each poll, miss
    /// the cache, and buy an identical answer again — a two-minute foreground
    /// poll turns into a paid model call every two minutes, all day. Timestamps
    /// alone must never invalidate anything; they are shown to the user and
    /// stored beside the cached output, not keyed on.
    ///
    /// The *states* are in, deliberately. A reading going stale, or a baseline
    /// finally becoming computable, changes the advice as surely as the number
    /// moving, and both slip past a key built from values alone.
    var materialHash: String { StableHash.of(withoutTimestamps) }

    /// The overnight figures only: sleep and recovery.
    ///
    /// What a morning briefing is *about*. Steps and active minutes climb all
    /// day and should not make a briefing look outdated — but last night's
    /// sleep arriving late, or a recovery reading landing after the briefing
    /// was written, means the briefing is now describing a night it never saw.
    /// That is the case worth catching, and only that one.
    /// Built by appending to a declared array rather than as one literal.
    ///
    /// A ten-element literal mixing `map(String.init)`, `String(format:)` and
    /// `??` gives the type-checker ten independent overload sets to resolve
    /// simultaneously, and it gives up: "unable to type-check this expression in
    /// reasonable time". Each `append` below is its own statement with a known
    /// element type, so there is nothing left to infer.
    var overnightHash: String {
        let stable = withoutTimestamps
        var parts: [String] = []

        parts.append(Self.describe(stable.sleepMinutes))
        parts.append(Self.describe(stable.sleepScore))
        parts.append(Self.describe(stable.hrvMs))
        parts.append(Self.describe(stable.restingHeartRate))
        parts.append(Self.describe(stable.readiness))

        return StableHash.of(parts)
    }

    /// One metric as "value|state", to one decimal place.
    ///
    /// The state is part of the string on purpose: a reading going stale or a
    /// baseline becoming computable changes what a briefing should say even
    /// when the number itself has not moved.
    private static func describe(_ metric: HealthMetric<Int>) -> String {
        let value = metric.value.map { String($0) } ?? "-"
        return value + "|" + metric.state.rawValue
    }

    private static func describe(_ metric: HealthMetric<Double>) -> String {
        let value: String
        if let number = metric.value {
            value = String(format: "%.1f", number)
        } else {
            value = "-"
        }
        return value + "|" + metric.state.rawValue
    }

    /// A copy with every clock reading flattened, so two snapshots of the same
    /// situation taken a minute apart hash identically.
    private var withoutTimestamps: HealthSnapshot {
        let epoch = Date(timeIntervalSince1970: 0)
        var stable = self
        stable.generatedAt = epoch
        stable.lastSyncedAt = nil
        stable.sleepMinutes.measuredAt = nil
        stable.sleepScore.measuredAt = nil
        stable.sleepEfficiencyPercent.measuredAt = nil
        stable.sleepVsBaselineMinutes.measuredAt = nil
        stable.hrvMs.measuredAt = nil
        stable.restingHeartRate.measuredAt = nil
        stable.readiness.measuredAt = nil
        stable.steps.measuredAt = nil
        stable.activeMinutes.measuredAt = nil
        return stable
    }
}

// MARK: - Stable hashing

/// A hash that is the same for the same data across launches.
///
/// `Hashable` is explicitly not this: Swift seeds string hashing per process,
/// so a `hashValue` written to `UserDefaults` never matches on the next launch
/// and every cache read after a restart would be a miss.
///
/// Sorted keys matter as much as the digest. `JSONEncoder` makes no promise
/// about key order, and an unsorted encoding produces a different hash for
/// identical data — a cache that silently never hits, which looks like a
/// working cache right up until the bill arrives.
enum StableHash {
    static func of<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return "unencodable" }
        return sha256(data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
