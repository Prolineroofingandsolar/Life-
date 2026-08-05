import Foundation

// MARK: - Stage vocabulary

/// A sleep stage, normalised away from any one provider's spelling.
enum SleepStageClass: String, Codable, CaseIterable {
    case deep
    case rem
    case light
    /// Reported asleep with no stage detail — "classic" tracking.
    case asleep
    case awake
    case outOfBed
    case unknown

    /// Maps the Google Health API's `SLEEP_STAGE_TYPE` enum. `RESTLESS` counts
    /// as awake time rather than sleep: it's movement inside the sleep period,
    /// not a sleeping stage.
    static func fromAPI(_ raw: String) -> SleepStageClass {
        switch raw.uppercased() {
        case "DEEP":      return .deep
        case "REM":       return .rem
        case "LIGHT":     return .light
        case "ASLEEP":    return .asleep
        case "AWAKE":     return .awake
        case "RESTLESS":  return .awake
        case "OUT_OF_BED": return .outOfBed
        default:          return .unknown
        }
    }

    /// Whether this counts toward minutes asleep.
    var isSleeping: Bool {
        switch self {
        case .deep, .rem, .light, .asleep: return true
        default: return false
        }
    }

    /// Awake or out of bed — the states that interrupt a night.
    var isInterruption: Bool {
        self == .awake || self == .outOfBed
    }

    /// Deep and REM only. Named "restorative" deliberately: it is **not**
    /// Google's "sound sleep", which is derived from epoch-level heart rate and
    /// movement that this app has no access to. Deep + REM is a stage-only
    /// approximation and is labelled as such everywhere it surfaces.
    var isRestorative: Bool {
        self == .deep || self == .rem
    }

    /// The canonical API spelling, for round-tripping through stored segments.
    var apiName: String {
        switch self {
        case .deep:      return "DEEP"
        case .rem:       return "REM"
        case .light:     return "LIGHT"
        case .asleep:    return "ASLEEP"
        case .awake:     return "AWAKE"
        case .outOfBed:  return "OUT_OF_BED"
        case .unknown:   return "UNKNOWN"
        }
    }
}

// MARK: - Inputs

/// One stage interval exactly as the source reported it.
struct SleepInterval {
    var start: Date
    var end: Date
    var stage: SleepStageClass
    /// False when Life inferred the stage rather than reading it from the
    /// source. Source-derived intervals always win a conflict.
    var sourceDerived: Bool = true

    var minutes: Double { max(0, end.timeIntervalSince(start)) / 60 }
}

/// Where a session came from. Preserved so a night can say which device
/// measured it, and so two sources can be told apart.
struct SleepProvenance: Codable, Equatable {
    var platform: String? = nil
    var deviceName: String? = nil
    var manufacturer: String? = nil
    var formFactor: String? = nil
    var recordingMethod: String? = nil
    /// Seconds east of UTC in effect at the *end* of the session. Kept so the
    /// calendar day is computed in the user's local time at the time of the
    /// night, which is what makes travel and DST behave.
    var utcOffsetSeconds: Int? = nil

    /// "Pixel Watch" / "Fitbit" / whatever the source gave, for display.
    var displayLabel: String? {
        deviceName ?? manufacturer ?? platform
    }
}

/// One sleep session as imported, before any merging or selection.
struct SleepSessionInput {
    var start: Date
    var end: Date
    var stages: [SleepInterval] = []
    var outOfBed: [SleepInterval] = []
    /// The source's own nap flag, where it has one.
    var isNap: Bool = false
    /// True when the source supplied real stages rather than a flat total.
    var hasSourceStages: Bool = false
    var provenance: SleepProvenance = SleepProvenance()
}

// MARK: - Output

/// A fully analysed sleep period with every derived measurement.
///
/// Field names follow the measurement definitions rather than any provider's
/// vocabulary, so it stays obvious what each one actually is.
struct AnalysedSleep: Equatable {
    /// Calendar day the night is filed under: the local day it *ended*.
    var dayKey: String = ""

    // Boundaries
    /// Start of the first sleeping stage.
    var sleepStart: Date?
    /// End of the final sleeping stage.
    var sleepEnd: Date?
    /// When the sleep period was entered — the source's session start.
    var attemptedBedtime: Date?
    /// End of the sleep period, including any awake tail.
    var finalWakeTime: Date?

    // Durations, all in minutes
    var minutesAsleep: Int = 0
    var timeInSleepWindow: Int = 0
    var deepMinutes: Int = 0
    var remMinutes: Int = 0
    var lightMinutes: Int = 0
    /// Time reported asleep with no stage detail.
    var genericAsleepMinutes: Int = 0
    /// Awake or out of bed for strictly more than five minutes, inside the night.
    var interruptionMinutes: Int = 0
    /// Brief internal awake or transitional intervals of five minutes or less.
    var restlessMinutes: Int = 0
    var sleepLatencyMinutes: Int?

    // Counts
    var fullAwakeningCount: Int = 0
    var stageTransitionCount: Int = 0
    /// How many separate sessions were merged into this night.
    var mergedSessionCount: Int = 1

    // Shape
    /// Midpoint between sleep start and sleep end — the clock time your night
    /// centres on, and the stable way to talk about schedule.
    var sleepMidpoint: Date?

    var isNap: Bool = false
    var provenance: SleepProvenance = SleepProvenance()

    /// The de-overlapped timeline the measurements were taken from, ready to
    /// store and chart. The hypnogram and the numbers come from the same pass,
    /// so they can't disagree.
    var segments: [SleepSegment] = []

    // Quality of the data itself
    /// Share of the sleep window covered by stage intervals, 0–1. Low coverage
    /// means the night is only partly described and shouldn't be scored.
    var stageCoverage: Double = 0
    var hasSourceStages: Bool = false

    /// Minutes asleep over time in the sleep window.
    var sleepEfficiency: Double? {
        guard timeInSleepWindow > 0 else { return nil }
        return min(1, Double(minutesAsleep) / Double(timeInSleepWindow))
    }

    /// Deep + REM as a share of time asleep.
    ///
    /// A stage-only approximation, **not** Google's "sound sleep" — that needs
    /// epoch-level heart rate and movement data this app doesn't receive.
    var restorativeShare: Double? {
        guard minutesAsleep > 0, hasSourceStages else { return nil }
        return Double(deepMinutes + remMinutes) / Double(minutesAsleep)
    }

    var restorativeMinutes: Int { deepMinutes + remMinutes }
}

// MARK: - Analysis

/// Turns raw imported sleep sessions into analysed nights.
///
/// Pure Foundation and free of app state so the rules below can be tested
/// directly — split nights, naps, travel, daylight saving, overlapping
/// intervals and the exact five-minute boundary all have cases in
/// `LifeTests/SleepAnalysisTests.swift`.
enum SleepAnalysis {

    // MARK: Tunable rules

    /// Two sessions belong to the same intended sleep period when the gap
    /// between them is no longer than this. Beyond it, getting up counts as
    /// ending the night rather than interrupting it.
    static let sessionMergeGapMinutes: Double = 60

    /// An interruption must last *strictly* more than five minutes to count as
    /// a full awakening. Exactly five minutes is restlessness.
    static let fullAwakeningThresholdMinutes: Double = 5

    /// A night described by fewer stage intervals than this share of its window
    /// is too sparse to score.
    static let minimumStageCoverage: Double = 0.5

    /// Naps are never the main night. Anything shorter than this that the
    /// source didn't already flag is treated as one.
    static let napCeilingMinutes: Double = 180

    // MARK: Entry point

    struct Result {
        /// The main overnight period per day, keyed by `dayKey`.
        var nights: [String: AnalysedSleep] = [:]
        /// Naps and secondary periods, kept out of the nightly figures entirely.
        var naps: [AnalysedSleep] = []
    }

    /// Analyses every imported session: merges what belongs together, picks the
    /// main overnight period per day, and keeps naps separate.
    static func analyse(sessions: [SleepSessionInput]) -> Result {
        var result = Result()
        guard !sessions.isEmpty else { return result }

        let merged = mergeSessions(sessions.sorted { $0.start < $1.start })

        for session in merged {
            let analysed = measure(session)
            guard analysed.finalWakeTime != nil else { continue }

            if analysed.isNap {
                result.naps.append(analysed)
                continue
            }

            // Longest wins the day. Two genuine overnight periods ending on the
            // same morning is unusual, but a long lie-in after an early start
            // shouldn't displace the real night.
            if let existing = result.nights[analysed.dayKey],
               existing.minutesAsleep >= analysed.minutesAsleep {
                result.naps.append(analysed)
            } else {
                if let displaced = result.nights[analysed.dayKey] { result.naps.append(displaced) }
                result.nights[analysed.dayKey] = analysed
            }
        }
        return result
    }

    // MARK: Merging

    /// Joins sessions separated by a short gap into one sleep period.
    ///
    /// Waking at 3am and going back to sleep at 3:20 is one night with an
    /// interruption, not two nights — and scoring it as two would halve both
    /// halves' duration. Naps never merge into a night.
    static func mergeSessions(_ sessions: [SleepSessionInput]) -> [SleepSessionInput] {
        var out: [SleepSessionInput] = []

        for session in sessions {
            guard var last = out.last else { out.append(session); continue }

            let gap = session.start.timeIntervalSince(last.end) / 60
            let bothOvernight = !isNap(session) && !isNap(last)

            if gap >= 0, gap <= sessionMergeGapMinutes, bothOvernight {
                // The gap itself is time awake inside the merged period, and has
                // to be recorded or it silently vanishes from the window.
                let bridge = SleepInterval(start: last.end, end: session.start, stage: .awake)
                last.stages.append(contentsOf: session.stages)
                if gap > 0 { last.stages.append(bridge) }
                last.outOfBed.append(contentsOf: session.outOfBed)
                last.end = max(last.end, session.end)
                last.hasSourceStages = last.hasSourceStages || session.hasSourceStages
                out[out.count - 1] = last
            } else {
                out.append(session)
            }
        }
        return out
    }

    /// A session counts as a nap if the source says so, or if it's short and
    /// carries no stage detail.
    static func isNap(_ session: SleepSessionInput) -> Bool {
        if session.isNap { return true }
        let minutes = session.end.timeIntervalSince(session.start) / 60
        return minutes < napCeilingMinutes && !session.hasSourceStages
    }

    // MARK: Measurement

    /// Derives every measurement for a single (already merged) session.
    static func measure(_ session: SleepSessionInput) -> AnalysedSleep {
        var out = AnalysedSleep()
        out.isNap = isNap(session)
        out.provenance = session.provenance
        out.hasSourceStages = session.hasSourceStages
        out.attemptedBedtime = session.start
        out.finalWakeTime = session.end
        out.mergedSessionCount = 1

        // Out-of-bed intervals are stages for accounting purposes; the API
        // supplies them separately and says they may overlap sleep stages, so
        // they go through the same de-overlapping pass rather than being summed
        // on top.
        let combined = session.stages + session.outOfBed.map {
            SleepInterval(start: $0.start, end: $0.end, stage: .outOfBed, sourceDerived: $0.sourceDerived)
        }
        let timeline = flatten(combined)

        guard !timeline.isEmpty else {
            out.timeInSleepWindow = Int((session.end.timeIntervalSince(session.start) / 60).rounded())
            out.dayKey = dayKey(for: session.end, offsetSeconds: session.provenance.utcOffsetSeconds)
            return out
        }

        // Accumulated in minutes-as-a-fraction and rounded once at the end,
        // never per interval.
        //
        // A staged night is thirty to fifty intervals, and rounding each one to
        // a whole minute before adding it up throws away up to half a minute
        // per interval. Those errors don't cancel reliably — they accumulate
        // into a total several minutes adrift of what the tracker itself
        // reports for the identical night, which is exactly the sort of
        // disagreement that makes a health app look untrustworthy when the
        // underlying data was never in dispute.
        var deep = 0.0, rem = 0.0, light = 0.0, generic = 0.0
        for interval in timeline {
            switch interval.stage {
            case .deep:   deep += interval.minutes
            case .rem:    rem += interval.minutes
            case .light:  light += interval.minutes
            case .asleep: generic += interval.minutes
            default:      break
            }
        }
        out.deepMinutes += Int(deep.rounded())
        out.remMinutes += Int(rem.rounded())
        out.lightMinutes += Int(light.rounded())
        out.genericAsleepMinutes += Int(generic.rounded())

        // Rounded from the true total rather than from the four rounded parts,
        // so the headline figure is right even when the breakdown has to be
        // whole minutes. The parts can therefore differ from the total by a
        // minute — correct, and preferable to a total that is wrong.
        out.minutesAsleep = Int((deep + rem + light + generic).rounded())

        let sleeping = timeline.filter { $0.stage.isSleeping }
        out.sleepStart = sleeping.first?.start
        out.sleepEnd = sleeping.last?.end

        // The window runs from getting into bed to the final wake, so it
        // includes the time spent falling asleep. That's what makes efficiency
        // honest rather than flattering.
        let windowStart = session.start
        let windowEnd = max(session.end, out.sleepEnd ?? session.end)
        out.timeInSleepWindow = Int((windowEnd.timeIntervalSince(windowStart) / 60).rounded())

        if let sleepStart = out.sleepStart {
            out.sleepLatencyMinutes = max(0, Int((sleepStart.timeIntervalSince(windowStart) / 60).rounded()))
            if let sleepEnd = out.sleepEnd {
                out.sleepMidpoint = Date(
                    timeIntervalSince1970: (sleepStart.timeIntervalSince1970 + sleepEnd.timeIntervalSince1970) / 2
                )
            }
        }

        // Interruptions only count between falling asleep and final waking —
        // lying awake before sleep is latency, and awake after the last sleeping
        // stage is just being up.
        if let sleepStart = out.sleepStart, let sleepEnd = out.sleepEnd {
            // Totalled before rounding, for the reason given above.
            var interrupted = 0.0, restless = 0.0
            for interval in timeline where interval.stage.isInterruption {
                guard interval.start >= sleepStart, interval.end <= sleepEnd else { continue }
                let minutes = interval.minutes
                if minutes > fullAwakeningThresholdMinutes {
                    out.fullAwakeningCount += 1
                    interrupted += minutes
                } else if minutes > 0 {
                    restless += minutes
                }
            }
            out.interruptionMinutes += Int(interrupted.rounded())
            out.restlessMinutes += Int(restless.rounded())
        }

        out.stageTransitionCount = max(0, timeline.count - 1)
        out.segments = timeline.map {
            SleepSegment(start: $0.start, minutes: Int($0.minutes.rounded()), stage: $0.stage.apiName)
        }

        if out.timeInSleepWindow > 0 {
            let covered = timeline.reduce(0.0) { $0 + $1.minutes }
            out.stageCoverage = min(1, covered / Double(out.timeInSleepWindow))
        }

        out.dayKey = dayKey(for: windowEnd, offsetSeconds: session.provenance.utcOffsetSeconds)
        return out
    }

    // MARK: De-overlapping

    /// Flattens intervals into a non-overlapping timeline so no minute is ever
    /// counted twice.
    ///
    /// Where two intervals cover the same minute the earlier-starting one keeps
    /// it and the later is clipped. Source-derived intervals are sorted ahead of
    /// inferred ones at the same instant, so a stage the device actually
    /// reported always beats one Life worked out.
    static func flatten(_ intervals: [SleepInterval]) -> [SleepInterval] {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted {
                if $0.start != $1.start { return $0.start < $1.start }
                if $0.sourceDerived != $1.sourceDerived { return $0.sourceDerived }
                return $0.end > $1.end
            }

        var out: [SleepInterval] = []
        var claimedUntil: Date?

        for interval in sorted {
            var clipped = interval
            if let claimedUntil, clipped.start < claimedUntil {
                clipped.start = claimedUntil
            }
            guard clipped.end > clipped.start else { continue }
            out.append(clipped)
            claimedUntil = max(claimedUntil ?? clipped.end, clipped.end)
        }
        return out
    }

    // MARK: Calendar

    /// The local calendar day of an instant, using the UTC offset that was in
    /// effect then.
    ///
    /// Using the offset from the night itself rather than the device's current
    /// zone is what keeps a night filed correctly after flying home, and stops
    /// the clocks going back turning one night into two.
    static func dayKey(for date: Date, offsetSeconds: Int?) -> String {
        guard let offsetSeconds, let zone = TimeZone(secondsFromGMT: offsetSeconds) else {
            return date.dayKey
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        return formatter.string(from: date)
    }

    /// Parses the UTC offsets the API sends. The field is documented only as an
    /// offset, and both the `±HH:MM` and protobuf-duration (`-28800s`) spellings
    /// turn up, so both are accepted rather than assuming one.
    static func parseUTCOffset(_ raw: String?) -> Int? {
        guard var text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }

        if text.hasSuffix("s"), let seconds = Int(text.dropLast()) { return seconds }
        if text == "Z" { return 0 }

        var sign = 1
        if text.hasPrefix("-") { sign = -1; text.removeFirst() }
        else if text.hasPrefix("+") { text.removeFirst() }

        let parts = text.split(separator: ":")
        if parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) {
            return sign * (hours * 3600 + minutes * 60)
        }
        if parts.count == 1, let digits = Int(parts[0]) {
            // "0800" or "08"
            return digits > 99
                ? sign * ((digits / 100) * 3600 + (digits % 100) * 60)
                : sign * digits * 3600
        }
        return nil
    }

    // MARK: Validation

    enum Warning: String {
        case sparseStageCoverage
        case noSourceStages
        case noHeartRateOrMovement
    }

    /// Whether a night carries enough stage detail to be scored at all.
    static func isScoreable(_ night: AnalysedSleep) -> Bool {
        isScoreable(
            hasSourceStages: night.hasSourceStages,
            stageCoverage: night.stageCoverage,
            minutesAsleep: night.minutesAsleep
        )
    }

    /// What's wrong with a night's data, for surfacing rather than hiding.
    static func warnings(for night: AnalysedSleep, hasRestorationSignals: Bool) -> [Warning] {
        warnings(
            hasSourceStages: night.hasSourceStages,
            stageCoverage: night.stageCoverage,
            hasRestorationSignals: hasRestorationSignals
        )
    }

    // MARK: Stored-record overloads
    //
    // The app works from `HealthDay` while the tests work from `AnalysedSleep`.
    // Both route through the same rules below so the two can't drift — the
    // alternative is a test suite that passes while the app applies different
    // thresholds.

    static func isScoreable(_ day: HealthDay) -> Bool {
        isScoreable(
            // Inferred from the data present, not from `sleepType`. That field
            // is optional in the API, so a night with a perfectly good deep/REM
            // breakdown can arrive with no type at all — and gating on it
            // silently suppressed the score for those nights.
            hasSourceStages: day.restorativeShare != nil,
            stageCoverage: day.stageCoverage,
            minutesAsleep: day.sleepMin ?? 0
        )
    }

    static func warnings(for day: HealthDay) -> [Warning] {
        warnings(
            // Inferred from the data present, not from `sleepType`. That field
            // is optional in the API, so a night with a perfectly good deep/REM
            // breakdown can arrive with no type at all — and gating on it
            // silently suppressed the score for those nights.
            hasSourceStages: day.restorativeShare != nil,
            stageCoverage: day.stageCoverage,
            // Any overnight cardiac signal counts; without one, restoration
            // falls back to efficiency and the user should know.
            hasRestorationSignals: day.restingHr != nil || day.hrvMs != nil || day.deepSleepHrvMs != nil
        )
    }

    // MARK: Shared rules

    /// Nil coverage means the night predates coverage tracking — treat it as
    /// adequate rather than retroactively unscoring old nights.
    static func isScoreable(hasSourceStages: Bool, stageCoverage: Double?, minutesAsleep: Int) -> Bool {
        hasSourceStages
            && minutesAsleep > 0
            && (stageCoverage ?? 1) >= minimumStageCoverage
    }

    static func warnings(
        hasSourceStages: Bool,
        stageCoverage: Double?,
        hasRestorationSignals: Bool
    ) -> [Warning] {
        var out: [Warning] = []
        if !hasSourceStages {
            out.append(.noSourceStages)
        } else if (stageCoverage ?? 1) < minimumStageCoverage {
            out.append(.sparseStageCoverage)
        }
        if !hasRestorationSignals { out.append(.noHeartRateOrMovement) }
        return out
    }
}

extension SleepAnalysis.Warning {
    var message: String {
        switch self {
        case .sparseStageCoverage:
            return "Only part of this night was recorded, so the figures below cover less than the full period."
        case .noSourceStages:
            return "This night was tracked without sleep stages, so there's no deep/REM breakdown and no estimated score."
        case .noHeartRateOrMovement:
            return "No overnight heart rate for this night, so restoration is estimated from sleep efficiency instead."
        }
    }
}
