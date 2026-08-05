import Foundation
import HealthKit

// MARK: - HealthKit Manager

final class HealthKitManager {

    /// The instance the app's background machinery uses.
    ///
    /// Views each build their own, which is harmless for one-off queries, but
    /// observer queries and background delivery have to outlive any view and be
    /// registered exactly once — a second registration for the same type
    /// replaces the first, so "whichever screen was last on top" is not an
    /// acceptable owner.
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    /// The running live heart-rate query, kept so it can be stopped. Only one
    /// runs at a time.
    private var heartRateQuery: HKAnchoredObjectQuery?

    /// Long-lived observer queries, one per watched type.
    private var observerQueries: [HKObserverQuery] = []

    /// Exposed so callers can ask about availability without importing HealthKit.
    static var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

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
            .heartRate,
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

    // MARK: - Background delivery

    /// The types worth waking the app for.
    ///
    /// Deliberately not every type Life reads. Each one costs a wake-up, and
    /// iOS budgets those — asking to be woken for body-mass index and VO₂ max,
    /// which change weekly at most, spends the allowance that steps and sleep
    /// need. Body composition and the rest still arrive on the next ordinary
    /// sync.
    private var backgroundTypes: [HKSampleType] {
        var types: [HKSampleType] = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .distanceWalkingRunning,
            .restingHeartRate,
            .heartRateVariabilitySDNN
        ]
        for id in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: id) { types.append(type) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.append(sleep)
        }
        return types
    }

    /// Starts watching HealthKit and asks iOS to wake Life when new data lands.
    ///
    /// Two halves that only work together. `enableBackgroundDelivery` is the
    /// request to be woken; the `HKObserverQuery` is what iOS actually delivers
    /// to. Enabling delivery without a running observer achieves nothing at
    /// all, which is a quiet way to ship a feature that appears to exist.
    ///
    /// The observer survives the app being suspended and, for these types, the
    /// app being terminated — iOS relaunches Life in the background to hand the
    /// notification over. That is the whole point: data arrives without the app
    /// having been opened.
    ///
    /// A note on frequency, because it sets expectations. `.immediate` is a
    /// request, not a promise: iOS honours it for sleep and other episodic
    /// types, and throttles cumulative ones like step count to roughly hourly
    /// however often the samples themselves arrive. Nothing here can make a
    /// step count update every minute in the background, and code that claimed
    /// to would simply be wrong.
    ///
    /// `onChange` is called on a background task. It must call through to
    /// whatever performs the sync and return when that is finished — the
    /// completion handler below is what tells iOS the wake-up was used
    /// properly, and failing to call it is how an app loses the privilege.
    func startObservingHealthChanges(onChange: @escaping () async -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        stopObservingHealthChanges()

        for type in backgroundTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                // Still acknowledged on error. Leaving it unacknowledged makes
                // iOS retry with backoff and eventually stop delivering.
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task {
                    await onChange()
                    completionHandler()
                }
            }
            observerQueries.append(query)
            store.execute(query)

            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in
                // Deliberately unreported. A refusal here means this device or
                // this authorisation state doesn't support waking for the type,
                // which is not a fault the user can act on, and the foreground
                // sync still covers it.
            }
        }
    }

    func stopObservingHealthChanges() {
        for query in observerQueries { store.stop(query) }
        observerQueries.removeAll()
    }

    /// Withdraws the wake-up requests as well as stopping the observers, for
    /// when the user turns background refresh off. Stopping the queries alone
    /// would leave iOS still launching Life to deliver notifications nothing is
    /// listening for.
    func disableBackgroundDelivery() {
        stopObservingHealthChanges()
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.disableAllBackgroundDelivery { _, _ in }
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

    // MARK: - Heart rate

    /// Every heart-rate reading recorded on a day.
    ///
    /// A raw sample query rather than a statistics query, deliberately: the
    /// warning on `fetchDailyMetrics` about double-counting applies to
    /// *summing* across sources, and nothing here is summed. These points are
    /// drawn as a curve, tagged by source, so two devices recording at once
    /// show as two series rather than one inflated total.
    func fetchHeartRateSamples(on day: Date) async -> [(date: Date, value: Double)] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? Date()
        return await fetchQuantitySamples(
            identifier: .heartRate,
            unit: Self.bpm,
            predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        )
    }

    /// Delivers heart-rate samples as HealthKit receives them.
    ///
    /// This is the only genuinely live path in the app. It fires within seconds
    /// of a reading arriving from an Apple Watch or from heart-rate-capable
    /// AirPods during a workout — as opposed to the Fitbit path, where
    /// freshness is capped by how often the band syncs to Google.
    ///
    /// Does nothing if no such device is writing; that's the expected outcome
    /// on a Fitbit-only setup, not a failure.
    func startHeartRateUpdates(_ onSamples: @escaping ([(date: Date, value: Double)]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        stopHeartRateUpdates()

        // Today only: the point is what's happening now, and an unbounded
        // predicate would hand back the entire history on the first callback.
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: Date()), end: nil, options: []
        )

        func deliver(_ samples: [HKSample]?) {
            let points = (samples as? [HKQuantitySample] ?? []).map {
                (date: $0.startDate, value: $0.quantity.doubleValue(for: Self.bpm))
            }
            guard !points.isEmpty else { return }
            onSamples(points)
        }

        let query = HKAnchoredObjectQuery(
            type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in deliver(samples) }
        // Without this the query answers once and never speaks again.
        query.updateHandler = { _, samples, _, _, _ in deliver(samples) }

        heartRateQuery = query
        store.execute(query)
    }

    func stopHeartRateUpdates() {
        if let heartRateQuery { store.stop(heartRateQuery) }
        heartRateQuery = nil
    }

    private static let bpm = HKUnit.count().unitDivided(by: .minute())

    // MARK: - Daily Metrics

    /// Pulls one value per day for every metric Life charts, keyed by `dayKey`.
    ///
    /// Everything here goes through `HKStatisticsCollectionQuery` rather than
    /// raw sample queries. HealthKit stores a separate set of samples per
    /// writing source, so summing raw samples double-counts whenever two
    /// devices record the same metric — an iPhone and a wrist tracker both
    /// logging steps, for instance.
    ///
    /// A statistics query does *not* fix that on its own, which an earlier
    /// version of this comment claimed and which is why totals were still
    /// inflated: `sumQuantity()` adds every source together just as a manual
    /// sum would. The de-duplication happens in `singleSourceSum`, which is why
    /// cumulative queries below ask for `.separateBySource`.
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

    // MARK: - Sources

    /// Names of the apps and devices writing the data Life reads — a watch, a
    /// ring, a smart scale, the iPhone itself.
    ///
    /// Sampled from a handful of recent samples per type rather than the full
    /// history: this only exists to list what's contributing, so a small recent
    /// window answers it far more cheaply than a year-long scan.
    func fetchDataSources(daysBack: Int = 14) async -> [String] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        guard let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])

        var types: [HKSampleType] = []
        for id in [HKQuantityTypeIdentifier.stepCount, .restingHeartRate, .heartRateVariabilitySDNN, .bodyMass] {
            if let type = HKQuantityType.quantityType(forIdentifier: id) { types.append(type) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.append(sleep) }

        var names = Set<String>()
        for type in types {
            names.formUnion(await sourceNames(for: type, predicate: predicate))
        }
        return names.sorted()
    }

    private func sourceNames(for type: HKSampleType, predicate: NSPredicate) async -> [String] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 200,
                sortDescriptors: nil
            ) { _, samples, error in
                guard error == nil, let samples else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: samples.map { $0.sourceRevision.source.name })
            }
            store.execute(query)
        }
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

        let isCumulative = options.contains(.cumulativeSum)
        // Asked for so each writing app or device can be totalled separately
        // below. Without it `HKStatistics` has no per-source breakdown to give.
        let queryOptions: HKStatisticsOptions = isCumulative
            ? options.union(.separateBySource)
            : options

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: queryOptions,
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
                    let quantity = isCumulative
                        ? Self.singleSourceSum(statistics, unit: unit)
                        : statistics.averageQuantity().map { $0.doubleValue(for: unit) }
                    guard let quantity else { return }
                    result[statistics.startDate.dayKey] = quantity
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// A day's total for a cumulative metric, counting only the source that
    /// recorded the most of it.
    ///
    /// `statistics.sumQuantity()` adds up every sample in the interval from
    /// every app and device that wrote one. That is the documented behaviour
    /// and it is wrong for this app's purpose: an iPhone counting steps in a
    /// pocket and a wrist tracker counting the same walk are two records of one
    /// set of steps, and adding them reported a day at roughly double. The same
    /// applies to distance and active energy, and it gets worse with each extra
    /// device — the Fitbit app writing into Apple Health alongside the iPhone's
    /// own motion data is exactly this case.
    ///
    /// The largest source wins rather than the sum or the average. They differ
    /// because they observe different amounts, not because one is inaccurate: a
    /// phone left on a desk misses the walk, the wrist tracker misses nothing.
    /// This mirrors how the Health app itself resolves the same conflict, and
    /// how `GoogleHealthService` resolves it on the Fitbit path.
    private static func singleSourceSum(_ statistics: HKStatistics, unit: HKUnit) -> Double? {
        guard let sources = statistics.sources, sources.count > 1 else {
            // One source, or no breakdown available: the plain total is already
            // the answer, and it is what earlier versions used throughout.
            return statistics.sumQuantity()?.doubleValue(for: unit)
        }
        let perSource = sources.compactMap {
            statistics.sumQuantity(for: $0)?.doubleValue(for: unit)
        }
        return perSource.max() ?? statistics.sumQuantity()?.doubleValue(for: unit)
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
