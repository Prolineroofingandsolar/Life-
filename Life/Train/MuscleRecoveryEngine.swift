import Foundation

// MARK: - Muscle Recovery Engine

/// How fatigued each muscle is, and how that figure is arrived at.
///
/// Every line of this was previously a `private` method on
/// `MuscleRecoveryMapView`. That made it unreachable from anywhere else and
/// untestable from everywhere: the workout builder had no way to know that legs
/// were trained yesterday, and the arithmetic behind a number the app states as
/// a percentage had never been asserted on once.
///
/// The extraction is deliberately behaviour-preserving — the same constants, the
/// same rounding, the same order of operations. Anything that looked like it
/// could be tidied was left alone, because a refactor that also changes the
/// answer is two changes wearing one commit message.
///
/// The arithmetic is `nonisolated` and takes plain numbers, so it can be tested
/// without an `AppState`. Only the two lookups that read the store are
/// `@MainActor`.
enum MuscleRecoveryEngine {

    // MARK: Status

    /// One muscle group's recovery state.
    struct Status: Equatable, Identifiable, Sendable {
        /// The group's stable id — "front-chest", "back-lats".
        var id: String
        /// The muscle key shared by front and back views: "chest", "lats".
        var key: String
        var name: String
        /// The `AppState` muscle string this group maps onto, when it maps onto
        /// one at all. Forearms don't.
        var appMuscle: String?

        /// 0–100. Zero when there is no history, which is *not* the same as
        /// recovered — see `hasTrainingHistory`.
        var fatigue: Int
        var daysSinceTrained: Int?
        var weeklySets: Int
        var weeklyTarget: ClosedRange<Int>

        /// Whether this muscle has ever been trained, as far as the app knows.
        ///
        /// The same missing-vs-zero distinction `HealthSnapshot` enforces, and
        /// it matters more here than it looks: a muscle never trained scores
        /// zero fatigue, which reads as "fully recovered, go hard". Telling
        /// someone their neglected calves are fresh is technically true and
        /// completely useless.
        var hasTrainingHistory: Bool

        var band: Band { Band(fatigue: fatigue) }

        /// Days until this muscle is expected to be fresh again. Nil when it
        /// already is, or when there is nothing to base it on.
        var freshInDays: Int?
    }

    /// The four bands the map colours by, named once so the wording can't drift
    /// between the map, the coach and the builder.
    enum Band: String, Equatable, Sendable {
        case fresh, light, recovering, fatigued

        init(fatigue: Int) {
            if fatigue >= 70 { self = .fatigued }
            else if fatigue >= 45 { self = .recovering }
            else if fatigue >= 25 { self = .light }
            else { self = .fresh }
        }

        var label: String {
            switch self {
            case .fatigued:   return "Fatigued"
            case .recovering: return "Recovering"
            case .light:      return "Light"
            case .fresh:      return "Fresh"
            }
        }
    }

    // MARK: The arithmetic

    /// Set-count baseline — meaningful from the very first session, with no
    /// training history required.
    ///
    /// A personal-best comparison alone collapses to "full effort" whenever the
    /// latest session happens to also be the only one on record, which is
    /// exactly the case for anyone who hasn't logged much yet.
    nonisolated static func setIntensity(_ sets: Int) -> Double {
        switch sets {
        case ..<3:   return 0.35
        case 3..<6:  return 0.6
        case 6..<10: return 0.85
        default:     return 1.0
        }
    }

    /// Blends the set-count baseline with this session's volume relative to the
    /// best single session ever recorded for the muscle, once there is a prior
    /// session to compare against. Falls back to the baseline alone otherwise,
    /// so a light session reads as light from day one.
    nonisolated static func intensity(sets: Int, volume: Double, personalBest: Double) -> Double {
        let bySets = setIntensity(sets)
        guard personalBest > 0 else { return bySets }
        let byVolume = Swift.min(1.0, volume / personalBest)
        return (bySets + byVolume) / 2
    }

    /// Day-based fatigue for a muscle with the given full-recovery window.
    ///
    /// Always high right after training, then tapers to a small residual floor
    /// by the time that muscle's own window has elapsed — so a 1.5-day muscle
    /// (biceps) is back to baseline well before a 3-day one (legs, back).
    nonisolated static func dayFatigue(daysAgo: Int, recoveryDays: Double) -> Double {
        guard daysAgo > 0 else { return 85 }
        let remaining = Swift.max(0, 1 - Double(daysAgo) / recoveryDays)
        return 8 + remaining * 77
    }

    /// The published percentage, from the pieces that make it.
    nonisolated static func fatigue(
        daysAgo: Int,
        recoveryDays: Double,
        sets: Int,
        volume: Double,
        personalBest: Double
    ) -> Int {
        let base = dayFatigue(daysAgo: daysAgo, recoveryDays: recoveryDays)
        let effort = intensity(sets: sets, volume: volume, personalBest: personalBest)
        return Int((base * effort).rounded())
    }

    /// Days until fresh, or nil when it already is.
    nonisolated static func freshInDays(fatigue: Int, daysAgo: Int, recoveryDays: Double) -> Int? {
        guard fatigue >= 25 else { return nil }
        return Swift.max(1, Int(recoveryDays.rounded(.up)) - daysAgo)
    }

    /// Whole-body readiness: 100 minus mean fatigue.
    ///
    /// Integer division, matching what the map has always shown. Rounding it
    /// differently here would make the ring and the coach disagree by a point,
    /// which is the kind of small contradiction this whole session has been
    /// about removing.
    nonisolated static func readiness(from statuses: [Status]) -> Int {
        guard !statuses.isEmpty else { return 100 }
        let average = statuses.map(\.fatigue).reduce(0, +) / statuses.count
        return Swift.max(0, Swift.min(100, 100 - average))
    }

    // MARK: Reading the store

    @MainActor
    static func status(for group: MuscleGroup, appState: AppState) -> Status {
        guard let muscle = group.appMuscle else {
            // Forearms and anything else the app doesn't track: no history, and
            // honestly labelled as such rather than reported as fresh.
            return Status(
                id: group.id,
                key: group.key,
                name: group.name,
                appMuscle: nil,
                fatigue: 0,
                daysSinceTrained: nil,
                weeklySets: 0,
                weeklyTarget: 8...16,
                hasTrainingHistory: false,
                freshInDays: nil
            )
        }

        let target = appState.weeklySetTarget(forMuscle: muscle)
        let weeklySets = appState.setsThisWeekByMuscle().first { $0.muscle == muscle }?.sets ?? 0

        guard let info = appState.lastTrainingInfo(muscle: muscle) else {
            return Status(
                id: group.id,
                key: group.key,
                name: group.name,
                appMuscle: muscle,
                fatigue: 0,
                daysSinceTrained: nil,
                weeklySets: weeklySets,
                weeklyTarget: target.min...Swift.max(target.min, target.max),
                hasTrainingHistory: false,
                freshInDays: nil
            )
        }

        let recoveryDays = appState.recoveryDays(forMuscle: muscle)
        let best = appState.personalBestVolume(muscle: muscle, excludingSessionId: info.sessionId)
        let value = fatigue(
            daysAgo: info.daysAgo,
            recoveryDays: recoveryDays,
            sets: info.completedSets,
            volume: info.volume,
            personalBest: best
        )

        return Status(
            id: group.id,
            key: group.key,
            name: group.name,
            appMuscle: muscle,
            fatigue: value,
            daysSinceTrained: info.daysAgo,
            weeklySets: weeklySets,
            weeklyTarget: target.min...Swift.max(target.min, target.max),
            hasTrainingHistory: true,
            freshInDays: freshInDays(fatigue: value, daysAgo: info.daysAgo, recoveryDays: recoveryDays)
        )
    }

    /// One status per unique muscle key — the set the readiness ring averages
    /// over, and the set the coach is told about. Front and back share a key
    /// where they share a muscle, so nothing is counted twice.
    @MainActor
    static func statuses(appState: AppState) -> [Status] {
        MuscleGroup.allUnique.map { status(for: $0, appState: appState) }
    }

    /// The groups worth resting, most fatigued first.
    @MainActor
    static func needingRecovery(appState: AppState, threshold: Int = 40, limit: Int = 4) -> [Status] {
        statuses(appState: appState)
            .filter { $0.fatigue >= threshold }
            .sorted { $0.fatigue > $1.fatigue }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Blueprint mapping

extension MuscleRecoveryEngine.Status {

    /// The blueprint muscle this group counts towards, if any.
    ///
    /// Several groups map onto one: lats, traps and lower back are all "Back".
    /// The builder needs the blueprint vocabulary, so it aggregates through
    /// this rather than through the map's own finer-grained keys.
    var blueprintMuscle: BlueprintMuscle? {
        appMuscle.flatMap { BlueprintMuscle(appMuscle: $0) }
    }
}
