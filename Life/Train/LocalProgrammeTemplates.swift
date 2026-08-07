import Foundation

// MARK: - Local Programme Templates

/// Programmes and sessions built on the device, with no network and no model.
///
/// Deliberately not a stub. It has three jobs and has to be genuinely useful for
/// all of them:
///
/// 1. **The whole feature when cloud AI is off.** `CoachSettings.cloudEnabled`
///    defaults to false, so on first run *every* user is pre-consent. An
///    onboarding flow that offered to build a first programme and then produced
///    nothing would be worse than not offering.
/// 2. **The fallback when a call fails.** A sheet that says "couldn't reach the
///    coach" where a usable programme could be has failed twice: no programme,
///    and a complaint.
/// 3. **The floor on quality.** If Gemini can't beat these, it isn't earning its
///    cost — and the comparison is only possible because these exist.
///
/// These emit `WorkoutBlueprint`s, exactly like the model does, so they travel
/// the same resolver and the same preview. There is no second code path with its
/// own bugs, and the equipment substitution and missing-muscle notes work
/// identically whether Gemini or this produced the shape.
enum LocalProgrammeTemplates {

    enum Result: Equatable {
        case workout(WorkoutBlueprint)
        case plan(PlanBlueprint)
    }

    /// A blueprint matching the brief, or nil when the brief asks for something
    /// no template covers.
    static func blueprint(for brief: WorkoutBrief, kind: WorkoutPreviewSheet.Kind) -> Result? {
        switch kind {
        case .workout: return .workout(session(for: brief))
        case .plan:    return plan(for: brief).map { Result.plan($0) }
        }
    }

    // MARK: Sessions

    /// A single session sized to the time available.
    ///
    /// Roughly one exercise per seven minutes, the same budget the model is
    /// given, so a template session and a generated one are about the same
    /// length for the same request.
    static func session(for brief: WorkoutBrief) -> WorkoutBlueprint {
        let slotCount = max(3, min(8, brief.availableMinutes / 7))
        let pattern = pattern(for: brief)
        let muscles = (0..<slotCount).map { pattern[$0 % pattern.count] }

        let (sets, repMin, repMax, rest) = prescription(for: brief)

        let slots = muscles.enumerated().map { index, muscle in
            WorkoutSlot(
                muscle: muscle,
                equipment: brief.availableEquipment.count == 1 ? brief.availableEquipment.first : nil,
                // Compounds first, isolation later — the same ordering rule the
                // model is given, applied deterministically.
                movementType: index < 2 ? .compound : .isolation,
                sets: sets,
                repMin: repMin,
                repMax: repMax,
                restSeconds: rest,
                rir: brief.energy == .low ? 3 : 2
            )
        }

        return WorkoutBlueprint(
            name: name(for: pattern, brief: brief),
            focus: focus(for: brief),
            slots: slots,
            notes: nil
        )
    }

    // MARK: Plans

    /// A split sized to the days available.
    ///
    /// Two days is full body twice; three is push/pull/legs; four is an
    /// upper/lower split doubled; five and six add arms and a second lower day.
    /// Conventional on purpose — a template's job is to be sound, not novel.
    static func plan(for brief: WorkoutBrief) -> PlanBlueprint? {
        let days = max(2, min(6, brief.daysPerWeek))
        let splits = split(forDays: days, brief: brief)
        guard !splits.isEmpty else { return nil }

        let sessions = splits.map { split in
            PlanSession(
                key: split.key,
                blueprint: WorkoutBlueprint(
                    name: split.name,
                    focus: focus(for: brief),
                    slots: slots(for: split.muscles, brief: brief),
                    notes: nil
                )
            )
        }

        let weekdays = scheduleWeekdays(count: days, preferred: brief.preferredWeekdays)
        let assigned = weekdays.enumerated().map { index, weekday in
            PlanWeekday(weekday: weekday, sessionKey: splits[index % splits.count].key)
        }

        return PlanBlueprint(
            name: planName(forDays: days, brief: brief),
            weeks: max(1, min(12, brief.weeks)),
            sessions: sessions,
            weekdays: assigned,
            progression: progressionText(for: brief)
        )
    }

    // MARK: Splits

    private struct Split {
        var key: String
        var name: String
        var muscles: [BlueprintMuscle]
    }

    /// The day's muscles, in priority order and **with the primary muscle
    /// repeated**.
    ///
    /// This is the fix for a leg day that gave legs four sets a week against a
    /// target of twelve. The lists used to name each muscle once — legs, glutes,
    /// calves, core — so a leg day was one leg exercise and three accessories,
    /// and since legs are trained once in a push/pull/legs week that was the
    /// whole weekly volume. A real leg session is three or four *leg* movements.
    ///
    /// Order matters as much as content: `slots(for:brief:)` truncates to fit
    /// the time available, so the primary muscle has to come first or a
    /// 30-minute session drops the squats and keeps the calf raises.
    private static func split(forDays days: Int, brief: WorkoutBrief) -> [Split] {
        let push: [BlueprintMuscle] = [.chest, .chest, .shoulders, .triceps, .shoulders, .triceps]
        let pull: [BlueprintMuscle] = [.back, .back, .biceps, .back, .biceps, .core]
        let legs: [BlueprintMuscle] = [.legs, .legs, .glutes, .legs, .calves, .core]
        let upper: [BlueprintMuscle] = [.chest, .back, .shoulders, .chest, .back, .biceps, .triceps]
        let lower: [BlueprintMuscle] = [.legs, .legs, .glutes, .legs, .calves, .core]
        let full: [BlueprintMuscle] = [.legs, .chest, .back, .legs, .shoulders, .core]

        switch days {
        case 2:
            return [
                Split(key: "full-a", name: "Full Body A", muscles: full),
                Split(key: "full-b", name: "Full Body B", muscles: [.legs, .back, .chest, .glutes, .biceps, .core]),
            ]
        case 3:
            return [
                Split(key: "push", name: "Push", muscles: push),
                Split(key: "pull", name: "Pull", muscles: pull),
                Split(key: "legs", name: "Legs", muscles: legs),
            ]
        case 4:
            return [
                Split(key: "upper-a", name: "Upper A", muscles: upper),
                Split(key: "lower-a", name: "Lower A", muscles: lower),
                Split(key: "upper-b", name: "Upper B", muscles: [.back, .back, .chest, .shoulders, .triceps, .biceps]),
                Split(key: "lower-b", name: "Lower B", muscles: [.legs, .glutes, .legs, .glutes, .calves, .core]),
            ]
        default:
            return [
                Split(key: "push", name: "Push", muscles: push),
                Split(key: "pull", name: "Pull", muscles: pull),
                Split(key: "legs", name: "Legs", muscles: legs),
                Split(key: "upper", name: "Upper", muscles: upper),
                Split(key: "lower", name: "Lower", muscles: lower),
                Split(key: "arms", name: "Arms & Core", muscles: [.biceps, .triceps, .biceps, .triceps, .shoulders, .core]),
            ].prefix(days).map { $0 }
        }
    }

    private static func slots(for muscles: [BlueprintMuscle], brief: WorkoutBrief) -> [WorkoutSlot] {
        // Four is the floor rather than three. Three slots across a day whose
        // list leads with two of the same muscle is a session; three slots
        // spread over three different muscles is a warm-up, and it was how a
        // leg day ended up with one leg movement in it.
        let limit = max(4, min(muscles.count, brief.availableMinutes / 8))
        let (sets, repMin, repMax, rest) = prescription(for: brief)

        return muscles.prefix(limit).enumerated().map { index, muscle in
            WorkoutSlot(
                muscle: muscle,
                equipment: brief.availableEquipment.count == 1 ? brief.availableEquipment.first : nil,
                movementType: index < 2 ? .compound : .isolation,
                sets: sets,
                repMin: repMin,
                repMax: repMax,
                restSeconds: rest,
                rir: brief.energy == .low ? 3 : 2
            )
        }
    }

    /// Which weekdays to train on.
    ///
    /// Honours a stated preference; otherwise spreads sessions out rather than
    /// stacking them, so a three-day week is Monday, Wednesday, Friday and not
    /// Monday, Tuesday, Wednesday.
    static func scheduleWeekdays(count: Int, preferred: Set<Int>) -> [Int] {
        if !preferred.isEmpty {
            let chosen = preferred.filter { (1...7).contains($0) }.sorted()
            if chosen.count >= count { return Array(chosen.prefix(count)) }
            // Fewer preferred days than sessions: use them all, then fill.
            let remaining = (1...7).filter { !chosen.contains($0) }
            return (chosen + remaining.prefix(count - chosen.count)).sorted()
        }

        switch count {
        case 2: return [1, 4]
        case 3: return [1, 3, 5]
        case 4: return [1, 2, 4, 5]
        case 5: return [1, 2, 3, 5, 6]
        default: return [1, 2, 3, 4, 5, 6]
        }
    }

    // MARK: Prescriptions

    /// Sets, rep range and rest, from the goal.
    ///
    /// Conventional ranges: heavy and slow for strength, moderate for
    /// hypertrophy, light and quick for endurance. Nothing here is a claim about
    /// what is optimal — it is a defensible default that a person can then edit.
    private static func prescription(
        for brief: WorkoutBrief
    ) -> (sets: Int, repMin: Int, repMax: Int, rest: Int) {
        let base: (Int, Int, Int, Int)
        switch brief.goal {
        case .strength:  base = (4, 4, 6, 180)
        case .muscle:    base = (4, 8, 12, 90)
        case .endurance: base = (3, 15, 20, 45)
        case .general:   base = (3, 8, 12, 90)
        }

        // A low-energy day is a lighter day, not a shorter one — dropping a set
        // keeps the movement pattern and reduces the load.
        if brief.energy == .low {
            return (max(2, base.0 - 1), base.1, base.2, base.3)
        }
        if brief.experience == .beginner {
            return (max(2, base.0 - 1), base.1, base.2, base.3)
        }
        return base
    }

    private static func pattern(for brief: WorkoutBrief) -> [BlueprintMuscle] {
        if !brief.focusMuscles.isEmpty {
            return brief.focusMuscles.sorted { $0.rawValue < $1.rawValue }
        }
        let all: [BlueprintMuscle] = [.chest, .back, .legs, .shoulders, .biceps, .triceps, .core, .glutes]
        let allowed = all.filter { !brief.avoidMuscles.contains($0) }
        return allowed.isEmpty ? [.core] : allowed
    }

    private static func name(for pattern: [BlueprintMuscle], brief: WorkoutBrief) -> String {
        if pattern.count <= 2 {
            return pattern.map(\.rawValue).joined(separator: " & ") + " session"
        }
        switch brief.goal {
        case .strength:  return "Full Body — Strength"
        case .muscle:    return "Full Body — Hypertrophy"
        case .endurance: return "Full Body — Conditioning"
        case .general:   return "Full Body"
        }
    }

    private static func planName(forDays days: Int, brief: WorkoutBrief) -> String {
        switch days {
        case 2: return "Two-Day Full Body"
        case 3: return "Push / Pull / Legs"
        case 4: return "Upper / Lower Split"
        case 5: return "Five-Day Split"
        default: return "Six-Day Split"
        }
    }

    private static func focus(for brief: WorkoutBrief) -> String {
        switch brief.goal {
        case .strength:  return "Heavy compound work with long rests."
        case .muscle:    return "Moderate loads, controlled tempo, short rests."
        case .endurance: return "Higher reps and brief rests."
        case .general:   return "A balanced mix of pushing, pulling and legs."
        }
    }

    private static func progressionText(for brief: WorkoutBrief) -> String {
        switch brief.goal {
        case .strength:
            return "When you hit the top of the rep range on every set, add a small amount of load next session."
        case .endurance:
            return "Add a rep or shorten the rest before adding load."
        default:
            return "Add a rep each week; once you reach the top of the range on all sets, add load and start again at the bottom."
        }
    }
}
