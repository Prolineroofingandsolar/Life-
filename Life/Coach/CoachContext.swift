import Foundation

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

    /// The local day every figure below belongs to, and the zone that day
    /// boundary was drawn in.
    ///
    /// Sent because the model otherwise has to infer "today" from a timestamp,
    /// and a UTC timestamp at 23:40 local names tomorrow. Every consumer of this
    /// context and every screen alongside it takes this same key from the one
    /// `HealthSnapshot`, which is what stops Today and Ask Coach describing
    /// different days.
    var dayKey: String = ""
    var timeZoneIdentifier: String = TimeZone.current.identifier

    /// Where the health figures came from and when they last arrived.
    ///
    /// Provenance, not a measurement. It lets the coach say "based on data
    /// updated at 07:12 from Fitbit" instead of implying every number is live.
    var dataSource: String?
    var dataUpdatedAt: Date?
    /// False when the last sync is older than the freshness window, so the model
    /// hedges rather than presenting an overnight figure as the current one.
    var dataIsFresh: Bool = false

    var goals: [Goal]
    var sleep: Sleep?
    var recovery: Recovery?
    var activity: Activity?
    var training: Training?
    var tasks: Tasks?
    var habits: Habits?
    /// Small already-derived deltas, so questions like "which figure changed
    /// most since yesterday?" can be answered without raw history being sent.
    var comparisons: Comparisons?
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
        /// The same duration already formatted — "7h 51m".
        ///
        /// Sent alongside the number rather than instead of it, because the
        /// model kept relaying the raw integer: Today read "10h 17m" while Ask
        /// Coach answered "471 minutes", which is not a phrasing preference but
        /// two apparently different figures for one night. Giving it the words
        /// removes the opportunity.
        var durationText: String?
        /// Minutes above or below the user's own recent average. Nil when there
        /// isn't enough history to have an average worth comparing to — which
        /// `state` distinguishes from having no sleep at all.
        var vsBaselineMinutes: Int?
        var efficiencyPercent: Int?
        var confidence: Confidence
        var quality: DataQuality
        /// Missing, stale, no baseline yet, partial or ready. The distinction
        /// the whole snapshot exists to carry.
        var state: MetricState = .ready
    }

    /// Recovery, present whenever a *measurement* is, not only when a trend can
    /// be computed.
    ///
    /// The old rule returned nil unless a baseline existed, and nil was reported
    /// to the model as "No recovery data". So the app printed "no recovery data"
    /// while the Health tab, two taps away, showed HRV 79 ms and a resting heart
    /// rate of 59 bpm — both perfectly well recorded, just not yet backed by
    /// enough nights to say whether they were high or low. That is
    /// `insufficientHistory`, and it earns a different sentence.
    struct Recovery: Codable, Equatable, Sendable {
        /// Words rather than milliseconds. The absolute HRV figure means
        /// nothing without a personal baseline, and sending the baseline too
        /// would be sending more data to say the same thing.
        var hrvStatus: BaselineStatus?
        var restingHeartRateStatus: BaselineStatus?
        var readinessScore: Int?
        var confidence: Confidence
        var quality: DataQuality
        var state: MetricState = .ready

        /// Whether a reading exists at all, independent of whether it can be
        /// interpreted. This is the fact the model needs in order to avoid
        /// contradicting a screen the user can see.
        var hasHrvMeasurement: Bool = false
        var hasRestingHeartRateMeasurement: Bool = false
        /// Progress towards a usable baseline, so the app can say "4 of 10
        /// nights" rather than refusing without explanation.
        var baselineNightsRecorded: Int = 0
        var baselineNightsRequired: Int = 0

        enum BaselineStatus: String, Codable, Sendable {
            case belowBaseline = "below_baseline"
            case normal
            case aboveBaseline = "above_baseline"
            case unknown
        }
    }

    /// Today against yesterday, and this week against last.
    ///
    /// Derived on the device and sent as a handful of integers. Sending the
    /// underlying days instead would be sending raw history to answer a question
    /// that is one subtraction wide.
    struct Comparisons: Codable, Equatable, Sendable {
        var sleepVsYesterdayMinutes: Int?
        var stepsVsYesterday: Int?
        var restingHeartRateVsYesterday: Double?
        var workoutsThisWeek: Int?
        var workoutsLastWeek: Int?
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
        var state: MetricState = .ready
    }

    struct Training: Codable, Equatable, Sendable {
        var plannedWorkout: String?
        /// Routines the coach may offer to schedule, each with the id it must
        /// quote. Only sent when training data is allowed, and capped — the
        /// coach offers at most one workout, so a full library would be paying
        /// to transmit what it can't use.
        var routines: [Named] = []
        var lastWorkoutDaysAgo: Int?
        /// Derived from recent volume against the user's own recent norm, not
        /// from an absolute scale — "moderate" means moderate for them.
        var recentLoad: Load?
        var sessionsThisWeek: Int

        enum Load: String, Codable, Sendable {
            case light, moderate, heavy
        }
    }

    /// An id and the name that goes with it, for the things the coach may
    /// offer to act on.
    struct Named: Codable, Equatable, Sendable {
        var id: String
        var name: String
    }

    struct Tasks: Codable, Equatable, Sendable {
        /// The lists a new task could go in.
        ///
        /// Sent only when titles are allowed, and for the same reason: a list
        /// is named by the user and "Divorce" is as plausible a list name as
        /// "Work". With it off the coach can still offer to add a task; the app
        /// files it under Personal rather than asking the coach to choose.
        var lists: [Named] = []
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
    /// **Every clock reading is excluded**, and that is the rule rather than an
    /// optimisation. `generatedAt` moves on each build and `dataUpdatedAt` moves
    /// on each sync poll — including either would make every hash unique, every
    /// lookup a miss, and every appearance of the Today screen a paid API call,
    /// which is the exact opposite of what a cache is for. Timestamps are stored
    /// beside the cached answer and shown to the user; they are never keyed on.
    ///
    /// What remains is the substance, and all of it: the figures, and the
    /// *states* of those figures. A reading going stale or a baseline becoming
    /// computable changes the advice as surely as a number moving, and a key
    /// built from values alone would miss both.
    ///
    /// Sorted keys matter. `JSONEncoder` does not guarantee key order between
    /// runs, and an unsorted encoding would produce a different hash for
    /// identical data, silently defeating the cache.
    var materialHash: String {
        var stable = self
        stable.generatedAt = Date(timeIntervalSince1970: 0)
        stable.dataUpdatedAt = nil
        // `nextDeadline` is a real deadline rather than a clock reading, so it
        // stays: advice about a task due at four is different advice from the
        // same task due tomorrow.
        return StableHash.of(stable)
    }
}
