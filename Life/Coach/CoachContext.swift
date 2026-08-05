import Foundation
import CryptoKit

// MARK: - Coach Context

/// Everything the coach is told, and nothing else.
///
/// This is the privacy boundary. What is in this struct leaves the device; what
/// isn't, doesn't. So it holds derived figures only — no name, no email, no raw
/// HealthKit samples, no provider tokens, no location, no notes, no journal
/// text. Adding a field here is a decision to send that data to a third party,
/// which is why each one is spelled out rather than the whole `AppState` being
/// serialised and trimmed later.
///
/// Every figure carries its own confidence and, where it matters, its source.
/// The model is explicitly told what is shaky so it can hedge instead of
/// inventing certainty — the alternative is a coach that speaks just as firmly
/// about a night the tracker half-recorded as one it recorded fully.
struct CoachContext: Codable, Equatable, Sendable {

    var generatedAt: Date
    var timeOfDay: TimeOfDay
    var goals: [Goal]
    var sleep: Sleep?
    var recovery: Recovery?
    var activity: Activity?
    var training: Training?
    var tasks: Tasks?
    var habits: Habits?
    /// Anything the app knows is missing, partial or suspect. Never empty
    /// because a gap was silently filled — a gap is stated.
    var dataWarnings: [String]
    /// Categories the user has asked not to be nudged about.
    ///
    /// Carried with the data rather than kept as a client-side filter, because
    /// the model needs to know in order to pick a *different* good suggestion
    /// rather than have its best one thrown away. The filter still exists —
    /// see `CoachRecommendation.validate` — but as a backstop, not the
    /// mechanism.
    var mutedCategories: [String] = []

    enum TimeOfDay: String, Codable, Sendable {
        case morning, afternoon, evening

        /// Derived from the hour rather than asked for, so a briefing generated
        /// by a background refresh is labelled by when it actually ran.
        static func from(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
            switch calendar.component(.hour, from: date) {
            case ..<12:  return .morning
            case 12..<17: return .afternoon
            default:      return .evening
            }
        }
    }

    /// How much a figure can be relied on.
    ///
    /// `low` is not a reason to hide a number — it's a reason to say so. A
    /// partially recorded night still tells you something; pretending it didn't
    /// happen tells you less.
    enum Confidence: String, Codable, Sendable {
        case low, medium, high
    }

    /// Whether a figure is a complete record or a snapshot of something still
    /// in progress.
    enum DataQuality: String, Codable, Sendable {
        /// A finished day, from the trusted source, with nothing missing.
        case verified
        /// Still accumulating — today's steps before the day is over.
        case partial
        /// Present but questionable: an implausible jump, or a value from a
        /// source that isn't the chosen one.
        case suspect
        /// Nothing recorded. Distinct from zero, always.
        case missing
    }

    // MARK: Sections

    /// A target the user has actually set.
    ///
    /// Life has no goals feature — no named, tracked objective with a
    /// deadline. What it has is five independent numeric targets, so these are
    /// synthesised from those rather than invented. If a real goals model is
    /// added later this becomes a direct mapping instead.
    struct Goal: Codable, Equatable, Sendable {
        var id: String
        var category: String
        var summary: String
    }

    struct Sleep: Codable, Equatable, Sendable {
        var score: Int?
        var durationMinutes: Int?
        /// Minutes above or below the user's own recent average. Nil when there
        /// isn't enough history to have an average worth comparing to.
        var vsBaselineMinutes: Int?
        var efficiencyPercent: Int?
        var confidence: Confidence
        var quality: DataQuality
    }

    struct Recovery: Codable, Equatable, Sendable {
        /// Words rather than milliseconds. The absolute HRV figure means
        /// nothing without a personal baseline, and sending the baseline too
        /// would be sending more data to say the same thing.
        var hrvStatus: BaselineStatus?
        var restingHeartRateStatus: BaselineStatus?
        var readinessScore: Int?
        var confidence: Confidence
        var quality: DataQuality

        enum BaselineStatus: String, Codable, Sendable {
            case belowBaseline = "below_baseline"
            case normal
            case aboveBaseline = "above_baseline"
            case unknown
        }
    }

    struct Activity: Codable, Equatable, Sendable {
        var steps: Int?
        var stepGoal: Int?
        var activeMinutes: Int?
        var activeMinutesGoal: Int?
        /// True while the day is still being counted, so a figure below goal
        /// isn't read as a failure at ten in the morning.
        var isPartialDay: Bool
        /// Which device produced it, in the app's own vocabulary.
        var source: String?
        var quality: DataQuality
    }

    struct Training: Codable, Equatable, Sendable {
        var plannedWorkout: String?
        var lastWorkoutDaysAgo: Int?
        /// Derived from recent volume against the user's own recent norm, not
        /// from an absolute scale — "moderate" means moderate for them.
        var recentLoad: Load?
        var sessionsThisWeek: Int

        enum Load: String, Codable, Sendable {
            case light, moderate, heavy
        }
    }

    struct Tasks: Codable, Equatable, Sendable {
        var importantRemaining: Int
        var totalRemainingToday: Int
        var nextDeadline: Date?
        /// A handful of candidates the coach may pick from, each with the id it
        /// must quote to refer to one. Capped tightly — the coach chooses one
        /// action, so sending forty tasks would be paying to transmit
        /// thirty-nine it can't use.
        var topCandidates: [Candidate]

        struct Candidate: Codable, Equatable, Sendable {
            var id: String
            var title: String
            var priority: String
            var estimatedMinutes: Int?
            var dueToday: Bool
        }
    }

    struct Habits: Codable, Equatable, Sendable {
        var remaining: Int
        var completedToday: Int
        var atRisk: [Candidate]

        struct Candidate: Codable, Equatable, Sendable {
            var id: String
            var title: String
            /// Days running, so the coach can say what's at stake.
            var streak: Int
        }
    }

    // MARK: Referencable ids

    /// Every id the coach is allowed to name in `relatedItemId`.
    ///
    /// Validation checks against this. A model that returns a well-formed
    /// recommendation quoting an id never sent would otherwise have the app
    /// completing or rescheduling something at random, and an invented id looks
    /// exactly like a real one.
    var referencableIds: Set<String> {
        var ids = Set<String>()
        ids.formUnion(tasks?.topCandidates.map(\.id) ?? [])
        ids.formUnion(habits?.atRisk.map(\.id) ?? [])
        ids.formUnion(goals.map(\.id))
        return ids
    }
}

// MARK: - Material hash

extension CoachContext {

    /// A hash of everything that would change the advice.
    ///
    /// `generatedAt` is deliberately excluded. Including it would make every
    /// hash unique, every cache lookup a miss, and every screen appearance a
    /// paid API call — which is the opposite of what the cache is for. What
    /// remains is the substance: if the sleep, steps, tasks and habits are the
    /// same as they were an hour ago, the advice would be too, so the stored
    /// answer is reused.
    ///
    /// Sorted keys matter. `JSONEncoder` does not guarantee key order between
    /// runs, and an unsorted encoding would produce a different hash for
    /// identical data, silently defeating the cache.
    var materialHash: String {
        var stable = self
        stable.generatedAt = Date(timeIntervalSince1970: 0)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(stable) else {
            // A context that can't be encoded can't be sent either, so the
            // value here only needs to be distinct and stable.
            return "unencodable"
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
