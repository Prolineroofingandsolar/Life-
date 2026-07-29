import Foundation
import HealthKit

// MARK: - HealthKit Manager

final class HealthKitManager {

    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let identifiers: [HKQuantityTypeIdentifier] = [
            // Body composition
            .bodyMass,
            .bodyFatPercentage,
            .leanBodyMass,
            .bodyMassIndex,
            // Activity
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .distanceWalkingRunning,
            .flightsClimbed,
            // Heart and recovery
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .walkingHeartRateAverage,
            .respiratoryRate,
            .oxygenSaturation,
            .vo2Max,
            .appleSleepingWristTemperature
        ]
        for id in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: id) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    // MARK: - Permission

    func requestPermissions() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Import

    struct BodyDataResult {
        var weight: [(date: Date, value: Double)] = []
        var bodyFat: [(date: Date, value: Double)] = []
        var leanMass: [(date: Date, value: Double)] = []
        var bmi: [(date: Date, value: Double)] = []
    }

    func importBodyData(daysBack: Int = 365) async -> BodyDataResult {
        guard HKHealthStore.isHealthDataAvailable() else { return BodyDataResult() }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: endDate) else {
            return BodyDataResult()
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        async let weight = fetchQuantitySamples(
            identifier: .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            predicate: predicate
        )
        async let bodyFat = fetchQuantitySamples(
            identifier: .bodyFatPercentage,
            unit: HKUnit.percent(),
            predicate: predicate
        )
        async let leanMass = fetchQuantitySamples(
            identifier: .leanBodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            predicate: predicate
        )
        async let bmi = fetchQuantitySamples(
            identifier: .bodyMassIndex,
            unit: HKUnit.count(),
            predicate: predicate
        )

        let (w, bf, lm, b) = await (weight, bodyFat, leanMass, bmi)
        return BodyDataResult(weight: w, bodyFat: bf, leanMass: lm, bmi: b)
    }

    // MARK: - Steps

    func fetchStepsForToday() async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let totals = await fetchDailyStatistics(
            identifier: .stepCount,
            unit: .count(),
            options: .cumulativeSum,
            startDate: startOfDay,
            endDate: Date()
        )
        return Int(totals[Date().dayKey] ?? 0)
    }

    // MARK: - Daily Metrics

    /// Pulls one value per day for every metric Life charts, keyed by `dayKey`.
    ///
    /// Everything here goes through `HKStatisticsCollectionQuery` rather than
    /// raw sample queries. HealthKit stores a separate set of samples per
    /// writing source, so summing raw samples double-counts whenever two
    /// devices record the same metric — an iPhone and a wrist tracker both
    /// logging steps, for instance. Statistics queries deduplicate across
    /// sources; raw sample queries do not.
    func fetchDailyMetrics(daysBack: Int = 30) async -> [String: HealthDay] {
        guard HKHealthStore.isHealthDataAvailable() else { return [:] }

        let endDate = Date()
        guard let rawStart = Calendar.current.date(byAdding: .day, value: -daysBack, to: endDate) else {
            return [:]
        }
        let startDate = Calendar.current.startOfDay(for: rawStart)

        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

        async let activeEnergy = fetchDailyStatistics(
            identifier: .activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum,
            startDate: startDate, endDate: endDate)
        async let exerciseTime = fetchDailyStatistics(
            identifier: .appleExerciseTime, unit: .minute(), options: .cumulativeSum,
            startDate: startDate, endDate: endDate)
        async let distance = fetchDailyStatistics(
            identifier: .distanceWalkingRunning, unit: .meterUnit(with: .kilo), options: .cumulativeSum,
            startDate: startDate, endDate: endDate)
        async let flights = fetchDailyStatistics(
            identifier: .flightsClimbed, unit: .count(), options: .cumulativeSum,
            startDate: startDate, endDate: endDate)
        async let restingHr = fetchDailyStatistics(
            identifier: .restingHeartRate, unit: beatsPerMinute, options: .discreteAverage,
            startDate: startDate, endDate: endDate)
        async let hrv = fetchDailyStatistics(
            identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), options: .discreteAverage,
            startDate: startDate, endDate: endDate)
        async let respiratory = fetchDailyStatistics(
            identifier: .respiratoryRate, unit: beatsPerMinute, options: .discreteAverage,
            startDate: startDate, endDate: endDate)
        async let oxygen = fetchDailyStatistics(
            identifier: .oxygenSaturation, unit: .percent(), options: .discreteAverage,
            startDate: startDate, endDate: endDate)
        async let wristTemp = fetchDailyStatistics(
            identifier: .appleSleepingWristTemperature, unit: .degreeCelsius(), options: .discreteAverage,
            startDate: startDate, endDate: endDate)
        async let vo2 = fetchDailyStatistics(
            identifier: .vo2Max, unit: HKUnit(from: "ml/kg*min"), options: .discreteAverage,
            startDate: startDate, endDate: endDate)
        async let sleepNights = fetchSleep(startDate: startDate, endDate: endDate)

        let (energyByDay, exerciseByDay, distanceByDay, flightsByDay) =
            await (activeEnergy, exerciseTime, distance, flights)
        let (restingByDay, hrvByDay, respiratoryByDay, oxygenByDay) =
            await (restingHr, hrv, respiratory, oxygen)
        let (tempByDay, vo2ByDay, sleepByDay) = await (wristTemp, vo2, sleepNights)

        var days: [String: HealthDay] = [:]
        func day(_ key: String) -> HealthDay {
            days[key] ?? HealthDay(dayKey: key)
        }

        for (key, value) in energyByDay where value > 0 {
            var d = day(key); d.activeEnergyKcal = (value * 10).rounded() / 10; days[key] = d
        }
        for (key, value) in exerciseByDay where value > 0 {
            var d = day(key); d.exerciseMinutes = Int(value.rounded()); days[key] = d
        }
        for (key, value) in distanceByDay where value > 0 {
            var d = day(key); d.distanceKm = (value * 100).rounded() / 100; days[key] = d
        }
        for (key, value) in flightsByDay where value > 0 {
            var d = day(key); d.flights = Int(value.rounded()); days[key] = d
        }
        for (key, value) in restingByDay where value > 0 {
            var d = day(key); d.restingHr = value.rounded(); days[key] = d
        }
        for (key, value) in hrvByDay where value > 0 {
            var d = day(key); d.hrvMs = value.rounded(); days[key] = d
        }
        for (key, value) in respiratoryByDay where value > 0 {
            var d = day(key); d.respiratoryRate = (value * 10).rounded() / 10; days[key] = d
        }
        // HealthKit reports oxygen saturation as a 0–1 fraction; Life stores a
        // percentage so the charts and labels can use it directly.
        for (key, value) in oxygenByDay where value > 0 {
            var d = day(key); d.spo2Pct = (value * 1000).rounded() / 10; days[key] = d
        }
        for (key, value) in tempByDay {
            var d = day(key); d.wristTempC = (value * 10).rounded() / 10; days[key] = d
        }
        for (key, value) in vo2ByDay where value > 0 {
            var d = day(key); d.vo2Max = (value * 10).rounded() / 10; days[key] = d
        }
        for (key, summary) in sleepByDay {
            var d = day(key)
            d.sleepMin = summary.asleepMinutes
            d.deepMin = summary.deepMinutes > 0 ? summary.deepMinutes : nil
            d.remMin = summary.remMinutes > 0 ? summary.remMinutes : nil
            d.lightMin = summary.lightMinutes > 0 ? summary.lightMinutes : nil
            d.awakeMin = summary.awakeMinutes > 0 ? summary.awakeMinutes : nil
            d.bedtime = summary.bedtime
            d.wakeTime = summary.wakeTime
            days[key] = d
        }

        // Steps deliberately aren't part of `HealthDay` — they already live on
        // `CareDay`, where they drive the Move ring. See `fetchDailySteps`.
        return days.filter { !$0.value.isEmpty }
    }

    /// Day-bucketed step totals, keyed by `dayKey`. Used for back-filling the
    /// Move ring's history.
    func fetchDailySteps(daysBack: Int = 30) async -> [String: Int] {
        guard HKHealthStore.isHealthDataAvailable() else { return [:] }
        let endDate = Date()
        guard let rawStart = Calendar.current.date(byAdding: .day, value: -daysBack, to: endDate) else {
            return [:]
        }
        let totals = await fetchDailyStatistics(
            identifier: .stepCount,
            unit: .count(),
            options: .cumulativeSum,
            startDate: Calendar.current.startOfDay(for: rawStart),
            endDate: endDate
        )
        return totals.compactMapValues { $0 > 0 ? Int($0.rounded()) : nil }
    }

    // MARK: - Sleep

    struct SleepSummary {
        var deepMinutes: Int = 0
        var remMinutes: Int = 0
        var lightMinutes: Int = 0
        var unspecifiedMinutes: Int = 0
        var awakeMinutes: Int = 0
        var bedtime: Date? = nil
        var wakeTime: Date? = nil

        /// Total time actually asleep. Trackers that report no stage breakdown
        /// still land here via `unspecifiedMinutes`, so this is always the
        /// figure to show as "slept".
        var asleepMinutes: Int {
            deepMinutes + remMinutes + lightMinutes + unspecifiedMinutes
        }
    }

    private enum SleepStage {
        case inBed, awake, light, deep, rem, unspecified
    }

    /// A sleep sample flattened to plain values, so `HKCategorySample` never
    /// has to cross the query's completion boundary.
    private struct SleepRecord {
        let start: Date
        let end: Date
        let stage: SleepStage
        let source: String
    }

    /// Summarises sleep per night, keyed by the `dayKey` of the morning the
    /// night ended — the convention both Apple and Fitbit use, so Monday's
    /// figure is the sleep you woke up from on Monday.
    func fetchSleep(startDate: Date, endDate: Date) async -> [String: SleepSummary] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }

        // Widen the window a night backwards so a session that began before
        // `startDate` but ended inside it is still complete.
        let queryStart = Calendar.current.date(byAdding: .hour, value: -24, to: startDate) ?? startDate
        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: endDate, options: [])

        let samples: [SleepRecord] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                guard error == nil, let categorySamples = results as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: categorySamples.map {
                    SleepRecord(
                        start: $0.startDate,
                        end: $0.endDate,
                        stage: Self.stage(for: $0.value),
                        source: $0.sourceRevision.source.bundleIdentifier
                    )
                })
            }
            store.execute(query)
        }

        guard !samples.isEmpty else { return [:] }

        // Split into sessions on any gap longer than an hour, so an afternoon
        // nap is never welded onto the previous night.
        var sessions: [[SleepRecord]] = []
        var current: [SleepRecord] = []
        var currentEnd: Date? = nil
        for sample in samples {
            if let end = currentEnd, sample.start.timeIntervalSince(end) > 60 * 60 {
                sessions.append(current)
                current = []
                currentEnd = nil
            }
            current.append(sample)
            currentEnd = max(currentEnd ?? sample.end, sample.end)
        }
        if !current.isEmpty { sessions.append(current) }

        var byDay: [String: SleepSummary] = [:]
        for session in sessions {
            guard let summary = summarise(session: session),
                  summary.asleepMinutes > 0,
                  let wake = summary.wakeTime else { continue }
            let key = wake.dayKey
            // A day can hold a night plus naps; keep whichever slept longest so
            // a 20-minute nap never replaces the night's figure.
            if let existing = byDay[key], existing.asleepMinutes >= summary.asleepMinutes { continue }
            byDay[key] = summary
        }
        // Drop anything from the padding night that falls outside the window.
        let firstKey = startDate.dayKey
        return byDay.filter { $0.key >= firstKey }
    }

    /// Reduces one sleep session to a single summary.
    ///
    /// If more than one app wrote the night — an Apple Watch and a tracker
    /// bridging its data in, say — their samples cover the same hours twice and
    /// adding them together roughly doubles the total. So a single source wins
    /// the whole session: whichever recorded the most stage detail, breaking
    /// ties on total time asleep.
    private func summarise(session: [SleepRecord]) -> SleepSummary? {
        let bySource = Dictionary(grouping: session, by: \.source)
        guard !bySource.isEmpty else { return nil }

        func detailScore(_ records: [SleepRecord]) -> (Int, TimeInterval) {
            let stages = Set(records.map(\.stage))
            let detail = stages.intersection([.light, .deep, .rem]).count
            let asleep = records
                .filter { $0.stage != .inBed && $0.stage != .awake }
                .reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
            return (detail, asleep)
        }

        guard let best = bySource.values.max(by: { lhs, rhs in
            let l = detailScore(lhs), r = detailScore(rhs)
            return l.0 != r.0 ? l.0 < r.0 : l.1 < r.1
        }) else { return nil }

        // Union the intervals per stage before totalling. Overlapping samples
        // within one source are unusual but do happen, and unioning keeps the
        // total honest where plain addition would inflate it.
        var intervalsByStage: [SleepStage: [(Date, Date)]] = [:]
        for record in best {
            intervalsByStage[record.stage, default: []].append((record.start, record.end))
        }

        func minutes(_ stage: SleepStage) -> Int {
            guard let intervals = intervalsByStage[stage] else { return 0 }
            return Int((mergedDuration(of: intervals) / 60).rounded())
        }

        var summary = SleepSummary()
        summary.deepMinutes = minutes(.deep)
        summary.remMinutes = minutes(.rem)
        summary.lightMinutes = minutes(.light)
        summary.unspecifiedMinutes = minutes(.unspecified)
        summary.awakeMinutes = minutes(.awake)

        // Fall back to the in-bed window when a source logs no asleep samples
        // at all, so bedtime/wake still render rather than showing blank.
        let asleep = best.filter { $0.stage != .inBed && $0.stage != .awake }
        let window = asleep.isEmpty ? best : asleep
        summary.bedtime = window.map(\.start).min()
        summary.wakeTime = window.map(\.end).max()
        return summary
    }

    /// Total time covered by a set of intervals, counting overlaps once.
    private func mergedDuration(of intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var currentStart: Date? = nil
        var currentEnd: Date? = nil
        for (start, end) in sorted {
            guard let cs = currentStart, let ce = currentEnd else {
                currentStart = start; currentEnd = end
                continue
            }
            if start <= ce {
                currentEnd = max(ce, end)
            } else {
                total += ce.timeIntervalSince(cs)
                currentStart = start; currentEnd = end
            }
        }
        if let cs = currentStart, let ce = currentEnd {
            total += ce.timeIntervalSince(cs)
        }
        return total
    }

    private static func stage(for value: Int) -> SleepStage {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .some(.inBed):              return .inBed
        case .some(.awake):              return .awake
        case .some(.asleepCore):         return .light
        case .some(.asleepDeep):         return .deep
        case .some(.asleepREM):          return .rem
        case .some(.asleepUnspecified):  return .unspecified
        default:                         return .unspecified
        }
    }

    // MARK: - Private

    /// One value per calendar day for a quantity type, keyed by `dayKey`.
    ///
    /// Days with no data are omitted rather than returned as zero — a day the
    /// tracker wasn't worn is a gap in the chart, not a reading of nothing.
    private func fetchDailyStatistics(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        startDate: Date,
        endDate: Date
    ) async -> [String: Double] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return [:]
        }

        let anchor = Calendar.current.startOfDay(for: startDate)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }
                var result: [String: Double] = [:]
                collection.enumerateStatistics(from: anchor, to: endDate) { statistics, _ in
                    let quantity = options.contains(.cumulativeSum)
                        ? statistics.sumQuantity()
                        : statistics.averageQuantity()
                    guard let quantity else { return }
                    result[statistics.startDate.dayKey] = quantity.doubleValue(for: unit)
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func fetchQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async -> [(date: Date, value: Double)] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil,
                      let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let result = quantitySamples.map { sample in
                    (date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }
}
