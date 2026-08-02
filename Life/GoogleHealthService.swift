import Foundation

// MARK: - Google Health Service

/// Reads Fitbit data through the Google Health API and maps it into the same
/// `HealthDay` records the Apple Health import writes, so the Health tab, the
/// insights and Today's tiles work identically whichever source fed them.
///
/// Endpoint paths, filter grammar, field names and enum values below all come
/// from Google's published `health` v4 discovery document, not from inference.
/// The shape is uniform:
///
///     GET /v4/users/me/dataTypes/{kebab-case-type}/dataPoints
///         ?filter={snake_case_type}.{timeField} >= "..." AND ... < "..."
///
/// Note the two spellings of a data type: kebab-case in the path, snake_case in
/// the filter. Both are derived from one camelCase name in `DataType` so they
/// can't drift apart.
@MainActor
final class GoogleHealthService {

    static let shared = GoogleHealthService()

    private let auth = GoogleHealthAuth.shared

    var isConnected: Bool { auth.isConnected }

    // MARK: - Data types

    /// A data type as named in the `DataPoint` union, with the two spellings the
    /// API needs and the filter field appropriate to its time model.
    private struct DataType {
        let camel: String
        /// Daily summaries filter on `.date`; interval types on
        /// `.interval.civil_start_time`. Sleep is special-cased to
        /// `civil_end_time` so a night lands on the morning it ended.
        let timeField: String

        var path: String { DataType.kebab(camel) }
        var filterField: String { "\(DataType.snake(camel)).\(timeField)" }

        static func daily(_ camel: String) -> DataType { .init(camel: camel, timeField: "date") }
        static func interval(_ camel: String) -> DataType { .init(camel: camel, timeField: "interval.civil_start_time") }
        /// Point-in-time observations filter on their sample time, not an
        /// interval — the respiratory sleep summary is one of these.
        static func sample(_ camel: String) -> DataType { .init(camel: camel, timeField: "sample_time.civil_time") }
        static let sleep = DataType(camel: "sleep", timeField: "interval.civil_end_time")

        private static func kebab(_ s: String) -> String { split(s).joined(separator: "-") }
        private static func snake(_ s: String) -> String { split(s).joined(separator: "_") }

        /// "dailyHeartRateVariability" → ["daily","heart","rate","variability"].
        /// Digits stay attached to the word they follow, so "dailyVo2Max"
        /// becomes daily-vo2-max rather than daily-vo-2-max.
        private static func split(_ s: String) -> [String] {
            var words: [String] = []
            var current = ""
            for character in s {
                if character.isUppercase && !current.isEmpty {
                    words.append(current.lowercased())
                    current = String(character)
                } else {
                    current.append(character)
                }
            }
            if !current.isEmpty { words.append(current.lowercased()) }
            return words
        }
    }

    // MARK: - Result

    struct SyncResult {
        var days: [HealthDay] = []
        var nights: [SleepNight] = []
        var steps: [String: Int] = [:]
        /// Metrics that failed, so a partial sync says what's missing instead of
        /// looking complete.
        var failures: [String] = []
    }

    // MARK: - Sync

    /// Fetches everything Life stores for the last `daysBack` days.
    ///
    /// Each metric is fetched independently and a failure is recorded rather
    /// than thrown: one changed field or a rate limit shouldn't cost you the
    /// sleep data that arrived fine. Auth failures abort, since every later call
    /// would fail identically.
    func sync(daysBack: Int = 90) async throws -> SyncResult {
        guard GoogleHealthConfig.isConfigured else { throw GoogleHealthError.notConfigured }
        guard auth.isConnected else { throw GoogleHealthError.notConnected }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: end) ?? end

        var byDay: [String: HealthDay] = [:]
        var result = SyncResult()
        var authFailed = false
        var forbidden = 0
        var succeeded = 0

        func day(_ key: String) -> HealthDay { byDay[key] ?? HealthDay(dayKey: key) }

        /// Runs one metric's fetch, tolerating its failure.
        ///
        /// Only a dead token (401) stops the run. A 403 means *this* data type
        /// isn't permitted — a scope the grant doesn't cover, or a type the
        /// project hasn't enabled — and it says nothing about the next one.
        ///
        /// Treating 403 as a session-wide failure was a real bug: adding a
        /// single unpermitted type silently cost every metric declared below
        /// it, and then threw away the ones that had already worked. Sleep,
        /// steps and every vital disappeared because one new call was refused.
        func attempt(_ name: String, _ work: () async throws -> Void) async {
            guard !authFailed else { return }
            do {
                try await work()
                succeeded += 1
            } catch let error as GoogleHealthError {
                if case .http(401, _) = error { authFailed = true }
                if case .http(403, _) = error { forbidden += 1 }
                result.failures.append(name)
            } catch {
                result.failures.append(name)
            }
        }

        // Sleep. Every session is imported — naps included — and handed to
        // `SleepAnalysis`, which does the merging, main-night selection, overlap
        // removal and derivation. Keeping that logic out of the transport layer
        // is what makes it testable; see `LifeTests/SleepAnalysisTests.swift`.
        await attempt("sleep") {
            let sessions = try await list(.sleep, start: start, end: end).compactMap(Self.sessionInput)
            let analysed = SleepAnalysis.analyse(sessions: sessions)

            for (key, night) in analysed.nights {
                var d = day(key)
                d.sleepType = night.hasSourceStages ? "STAGES" : "CLASSIC"
                d.sleepMin = night.minutesAsleep
                d.deepMin = night.deepMinutes > 0 ? night.deepMinutes : nil
                d.remMin = night.remMinutes > 0 ? night.remMinutes : nil
                d.lightMin = night.lightMinutes > 0 ? night.lightMinutes : nil
                d.awakeMin = night.interruptionMinutes + night.restlessMinutes
                d.timeInBedMin = night.timeInSleepWindow
                d.latencyMin = night.sleepLatencyMinutes
                d.awakenings = night.fullAwakeningCount
                d.restlessMinutes = night.restlessMinutes
                d.interruptionMinutes = night.interruptionMinutes
                d.stageTransitions = night.stageTransitionCount
                d.sleepMidpoint = night.sleepMidpoint
                d.stageCoverage = night.stageCoverage
                d.bedtime = night.attemptedBedtime
                d.wakeTime = night.finalWakeTime
                d.sleepSourceDevice = night.provenance.displayLabel
                // `officialSleepScore` is deliberately left unset: the v4 schema
                // exposes no score field on any sleep type. If that changes it
                // gets assigned here and displayed verbatim.
                byDay[key] = d

                // Hypnogram segments come from the same de-overlapped timeline
                // the measurements were taken from, so the chart and the numbers
                // can't disagree.
                if !night.segments.isEmpty {
                    result.nights.append(SleepNight(dayKey: key, segments: night.segments, outOfBed: []))
                }
            }
        }

        await attempt("breathing by stage") {
            for point in try await list(.sample("respiratoryRateSleepSummary"), start: start, end: end) {
                guard let body = point["respiratoryRateSleepSummary"] as? [String: Any],
                      let key = Self.dayKey(fromSampleTime: body["sampleTime"]) else { continue }
                var d = day(key)
                d.breathingRem = Self.stat(body["remSleepStats"])
                d.breathingDeep = Self.stat(body["deepSleepStats"])
                d.breathingLight = Self.stat(body["lightSleepStats"])
                if d.respiratoryRate == nil { d.respiratoryRate = Self.stat(body["fullSleepStats"]) }
                byDay[key] = d
            }
        }

        await attempt("resting heart rate") {
            for (key, value) in try await daily(.daily("dailyRestingHeartRate"), field: "beatsPerMinute", start: start, end: end) {
                var d = day(key); d.restingHr = value; byDay[key] = d
            }
        }

        await attempt("HRV") {
            for point in try await list(.daily("dailyHeartRateVariability"), start: start, end: end) {
                guard let body = point["dailyHeartRateVariability"] as? [String: Any],
                      let date = body["date"] as? [String: Any],
                      let key = Self.dayKey(from: date) else { continue }
                var d = day(key)
                d.hrvMs = Self.double(body["averageHeartRateVariabilityMilliseconds"])
                // Deep sleep is the cleanest window for HRV — least movement,
                // least breathing variation — so it's worth keeping separately
                // from the whole-night average.
                d.deepSleepHrvMs = Self.double(body["deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds"])
                byDay[key] = d
            }
        }

        await attempt("breathing rate") {
            for (key, value) in try await daily(.daily("dailyRespiratoryRate"), field: "breathsPerMinute", start: start, end: end) {
                var d = day(key); d.respiratoryRate = value; byDay[key] = d
            }
        }

        await attempt("SpO₂") {
            for (key, value) in try await daily(.daily("dailyOxygenSaturation"), field: "averagePercentage", start: start, end: end) {
                var d = day(key); d.spo2Pct = value; byDay[key] = d
            }
        }

        await attempt("cardio fitness") {
            for (key, value) in try await daily(.daily("dailyVo2Max"), field: "vo2Max", start: start, end: end) {
                var d = day(key); d.vo2Max = value; byDay[key] = d
            }
        }

        // Unlike the legacy Fitbit API — which only exposed a relative nightly
        // variation — this reports an absolute figure, so it's comparable with
        // HealthKit's wrist temperature and safe to store in the same field.
        await attempt("skin temperature") {
            for point in try await list(.daily("dailySleepTemperatureDerivations"), start: start, end: end) {
                guard let body = point["dailySleepTemperatureDerivations"] as? [String: Any],
                      let date = body["date"] as? [String: Any],
                      let key = Self.dayKey(from: date) else { continue }
                var d = day(key)
                d.wristTempC = Self.double(body["nightlyTemperatureCelsius"])
                // Without the baseline an absolute skin temperature is
                // uninterpretable; with it, the deviation is the whole point.
                d.tempBaselineC = Self.double(body["baselineTemperatureCelsius"])
                byDay[key] = d
            }
        }

        await attempt("steps") {
            for (key, value) in try await intervalTotals(.interval("steps"), field: "count", start: start, end: end) where value > 0 {
                result.steps[key] = Int(value)
            }
        }

        await attempt("calories") {
            for (key, value) in try await intervalTotals(.interval("activeEnergyBurned"), field: "kcal", start: start, end: end) {
                var d = day(key); d.activeEnergyKcal = (value * 10).rounded() / 10; byDay[key] = d
            }
        }

        await attempt("distance") {
            for (key, value) in try await intervalTotals(.interval("distance"), field: "millimeters", start: start, end: end) {
                // Reported in millimetres; HealthDay stores kilometres.
                var d = day(key); d.distanceKm = (value / 1_000_000 * 100).rounded() / 100; byDay[key] = d
            }
        }

        await attempt("floors") {
            for (key, value) in try await intervalTotals(.interval("floors"), field: "count", start: start, end: end) {
                var d = day(key); d.flights = Int(value); byDay[key] = d
            }
        }

        await attempt("active minutes") {
            for (key, value) in try await activeMinutes(start: start, end: end) {
                var d = day(key); d.exerciseMinutes = Int(value); byDay[key] = d
            }
        }

        // Last deliberately. Zone minutes are the newest and least certain call
        // here, and anything whose permissions aren't proven belongs at the end
        // where a refusal costs nothing else.
        await attempt("heart rate zones") {
            for point in try await list(.interval("timeInHeartRateZone"), start: start, end: end) {
                guard let body = point["timeInHeartRateZone"] as? [String: Any],
                      let key = Self.dayKey(fromInterval: body["interval"]) else { continue }
                var d = day(key)
                for entry in body["timeInHeartRateZoneValues"] as? [[String: Any]] ?? [] {
                    guard let name = entry["heartRateZone"] as? String,
                          let zone = HeartRateZone(rawValue: name),
                          let minutes = Self.durationMinutes(entry["duration"]) else { continue }
                    switch zone {
                    case .light:    d.hrZoneLightMin = (d.hrZoneLightMin ?? 0) + minutes
                    case .moderate: d.hrZoneModerateMin = (d.hrZoneModerateMin ?? 0) + minutes
                    case .vigorous: d.hrZoneVigorousMin = (d.hrZoneVigorousMin ?? 0) + minutes
                    case .peak:     d.hrZonePeakMin = (d.hrZonePeakMin ?? 0) + minutes
                    }
                }
                byDay[key] = d
            }
        }

        // A revoked or expired grant refuses everything; a missing scope
        // refuses one type. Only the first is worth failing the whole sync for
        // — otherwise partial data beats none, and `failures` already names
        // what didn't come through.
        if authFailed || (forbidden > 0 && succeeded == 0) {
            throw GoogleHealthError.http(
                authFailed ? 401 : 403,
                "failed on \(result.failures.first ?? "every data type")"
            )
        }

        result.days = byDay.values.filter { !$0.isEmpty }
        return result
    }

    // MARK: - Heart rate

    /// Individual timestamped heart-rate readings for one day.
    ///
    /// Deliberately **not** part of `sync()`. `heartRate` is a sample type —
    /// up to 1,440 points a day — and the ninety-day window `sync()` uses would
    /// be a six-figure point count for a curve nobody scrolls back through.
    /// This is fetched on demand for the day being looked at, and held in
    /// memory by `HeartRateStore` rather than stored.
    func heartRateSamples(on day: Date) async throws -> [HeartRateSample] {
        guard GoogleHealthConfig.isConfigured, auth.isConnected else { return [] }

        var out: [HeartRateSample] = []
        for point in try await list(.sample("heartRate"), start: day, end: day) {
            guard let body = point["heartRate"] as? [String: Any],
                  let bpm = Self.double(body["beatsPerMinute"]),
                  let time = Self.instant(fromSampleTime: body["sampleTime"]) else { continue }
            out.append(HeartRateSample(time: time, bpm: bpm, source: .fitbit))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Workouts recorded on a day.
    ///
    /// Parsed defensively: `metricsSummary` is documented as carrying
    /// performance statistics but its exact heart-rate fields aren't pinned
    /// down in the discovery document, so a missing average or maximum comes
    /// back nil and the caller derives them from the sample curve instead.
    func exerciseSessions(on day: Date) async throws -> [ExerciseSession] {
        guard GoogleHealthConfig.isConfigured, auth.isConnected else { return [] }

        var out: [ExerciseSession] = []
        for point in try await list(.interval("exercise"), start: day, end: day) {
            guard let body = point["exercise"] as? [String: Any],
                  let interval = body["interval"] as? [String: Any],
                  let start = Self.instant(fromISO: interval["startTime"]),
                  let end = Self.instant(fromISO: interval["endTime"]) else { continue }

            let summary = body["metricsSummary"] as? [String: Any] ?? [:]
            out.append(ExerciseSession(
                id: (point["dataPointId"] as? String) ?? "\(start.timeIntervalSince1970)",
                start: start,
                end: end,
                name: Self.exerciseName(body),
                activeMinutes: Self.durationMinutes(body["activeDuration"]),
                averageBpm: Self.double(summary["averageHeartRateBeatsPerMinute"]),
                maximumBpm: Self.double(summary["maxHeartRateBeatsPerMinute"]),
                // Spelling of the calorie field isn't pinned down in the
                // discovery document I could reach, so both plausible names are
                // tried and a miss simply leaves it off the row.
                kcal: Self.double(summary["totalCaloriesKcal"])
                    ?? Self.double(summary["activeCaloriesKcal"])
            ))
        }
        return out.sorted { $0.start < $1.start }
    }

    /// "Outdoor Run" if the source named it, otherwise the enum tidied up:
    /// `RUNNING` → "Running", `HIGH_INTENSITY_INTERVAL_TRAINING` → "High
    /// Intensity Interval Training".
    private static func exerciseName(_ body: [String: Any]) -> String {
        if let display = body["displayName"] as? String, !display.isEmpty { return display }
        guard let raw = body["exerciseType"] as? String, !raw.isEmpty else { return "Workout" }
        return raw
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    // MARK: - Fetch helpers

    /// Daily-summary types: one value per calendar date, keyed by `dayKey`.
    private func daily(
        _ type: DataType, field: String, start: Date, end: Date
    ) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        for point in try await list(type, start: start, end: end) {
            guard let body = point[type.camel] as? [String: Any],
                  let date = body["date"] as? [String: Any],
                  let key = Self.dayKey(from: date),
                  let value = Self.double(body[field]) else { continue }
            out[key] = value
        }
        return out
    }

    /// Interval types: many points per day, summed into a daily total.
    private func intervalTotals(
        _ type: DataType, field: String, start: Date, end: Date
    ) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        for point in try await list(type, start: start, end: end) {
            guard let body = point[type.camel] as? [String: Any],
                  let key = Self.dayKey(fromInterval: body["interval"]),
                  let value = Self.double(body[field]) else { continue }
            out[key, default: 0] += value
        }
        return out
    }

    /// Active minutes are broken down by activity level, so the daily figure is
    /// the sum across levels.
    private func activeMinutes(start: Date, end: Date) async throws -> [String: Double] {
        let type = DataType.interval("activeMinutes")
        var out: [String: Double] = [:]
        for point in try await list(type, start: start, end: end) {
            guard let body = point[type.camel] as? [String: Any],
                  let key = Self.dayKey(fromInterval: body["interval"]) else { continue }
            let levels = body["activeMinutesByActivityLevel"] as? [[String: Any]] ?? []
            let total = levels.compactMap { Self.double($0["activeMinutes"]) }.reduce(0, +)
            if total > 0 { out[key, default: 0] += total }
        }
        return out
    }

    // MARK: - Transport

    /// Every data point for a type in a range, following pagination.
    ///
    /// Page size is capped at 25 for sleep by the API, so paging isn't optional
    /// for any range longer than a few weeks.
    private func list(_ type: DataType, start: Date, end: Date) async throws -> [[String: Any]] {
        // The upper bound is exclusive, so it has to be *tomorrow* rather than
        // today or nothing recorded today ever comes back. That bit hardest on
        // sleep, which filters on `civil_end_time`: last night ends this
        // morning, so an exclusive bound of today's date silently hid the most
        // recent night — permanently, on every sync.
        let dayAfterEnd = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
        let from = Self.isoDay.string(from: start)
        let to = Self.isoDay.string(from: dayAfterEnd)
        let filter = "\(type.filterField) >= \"\(from)\" AND \(type.filterField) < \"\(to)\""

        var out: [[String: Any]] = []
        var pageToken: String?
        var pages = 0

        repeat {
            var components = URLComponents(string: "\(GoogleHealthConfig.apiBase)/users/me/dataTypes/\(type.path)/dataPoints")!
            var items = [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "pageSize", value: type.camel == "sleep" ? "25" : "1000")
            ]
            if let pageToken = pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items

            let data = try await get(components.url!)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GoogleHealthError.badResponse("unreadable body for \(type.path)")
            }
            out.append(contentsOf: object["dataPoints"] as? [[String: Any]] ?? [])
            pageToken = object["nextPageToken"] as? String
            pages += 1
            // A guard against a malformed token looping forever; 200 pages is
            // far more than a year of any of these types.
        } while pageToken != nil && !(pageToken!.isEmpty) && pages < 200

        return out
    }

    private func get(_ url: URL) async throws -> Data {
        let token = try await auth.accessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GoogleHealthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Parsing
    //
    // The API returns int64 fields as JSON strings (steps counts, sleep minutes,
    // resting heart rate), so every numeric read goes through these rather than
    // assuming a type.

    private static func double(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    /// Average breaths per minute out of a `RespiratoryRateSleepSummaryStatistics`.
    private static func stat(_ raw: Any?) -> Double? {
        guard let stats = raw as? [String: Any] else { return nil }
        return double(stats["breathsPerMinute"])
    }

    /// Builds a raw sleep session from a data point, preserving where it came
    /// from and the UTC offset in effect, so `SleepAnalysis` can file the night
    /// under the right local day even across travel and clock changes.
    private static func sessionInput(_ point: [String: Any]) -> SleepSessionInput? {
        guard let sleep = point["sleep"] as? [String: Any],
              let interval = sleep["interval"] as? [String: Any],
              let startText = interval["startTime"] as? String,
              let endText = interval["endTime"] as? String,
              let start = rfc3339.date(from: startText),
              let end = rfc3339.date(from: endText) else { return nil }

        let metadata = sleep["metadata"] as? [String: Any]
        let source = point["dataSource"] as? [String: Any]
        let device = source?["device"] as? [String: Any]

        var provenance = SleepProvenance()
        provenance.platform = source?["platform"] as? String
        provenance.deviceName = device?["displayName"] as? String
        provenance.manufacturer = device?["manufacturer"] as? String
        provenance.formFactor = device?["formFactor"] as? String
        provenance.recordingMethod = source?["recordingMethod"] as? String
        provenance.utcOffsetSeconds =
            SleepAnalysis.parseUTCOffset(interval["endUtcOffset"] as? String)
            ?? SleepAnalysis.parseUTCOffset(interval["startUtcOffset"] as? String)

        let stages = intervals(from: sleep["stages"])

        // Whether the source classified the night is inferred from the stages
        // it actually sent, not from `type`. That field is optional, so a night
        // with a full deep/REM breakdown can arrive with no type at all —
        // trusting it alone marked such nights CLASSIC and suppressed both the
        // hypnogram and the score.
        let classified = stages.contains {
            $0.stage == .deep || $0.stage == .rem || $0.stage == .light
        }

        return SleepSessionInput(
            start: start,
            end: end,
            stages: stages,
            outOfBed: intervals(from: sleep["outOfBedSegments"], forced: .outOfBed),
            isNap: metadata?["nap"] as? Bool == true,
            hasSourceStages: classified || (sleep["type"] as? String) == "STAGES",
            provenance: provenance
        )
    }

    /// Stage or out-of-bed intervals as `SleepAnalysis` wants them.
    private static func intervals(from raw: Any?, forced: SleepStageClass? = nil) -> [SleepInterval] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let startText = entry["startTime"] as? String,
                  let endText = entry["endTime"] as? String,
                  let start = rfc3339.date(from: startText),
                  let end = rfc3339.date(from: endText),
                  end > start else { return nil }
            let stage = forced ?? SleepStageClass.fromAPI(entry["type"] as? String ?? "")
            return SleepInterval(start: start, end: end, stage: stage, sourceDerived: true)
        }
    }

    /// The local day of a point-in-time observation.
    private static func dayKey(fromSampleTime raw: Any?) -> String? {
        guard let sampleTime = raw as? [String: Any] else { return nil }
        if let civil = sampleTime["civilTime"] as? [String: Any],
           let date = civil["date"] as? [String: Any],
           let key = dayKey(from: date) {
            return key
        }
        if let physical = sampleTime["physicalTime"] as? String,
           let date = rfc3339.date(from: physical) {
            return date.dayKey
        }
        return nil
    }

    /// The absolute instant a sample was taken.
    ///
    /// `physicalTime` is required here, not merely preferred: `civilTime` is
    /// wall-clock without an offset, and "how long ago was this reading" is
    /// meaningless unless it's anchored to a real instant. A civil-only sample
    /// is dropped rather than guessed at with the device's current zone, which
    /// would silently misreport the age by hours after travelling.
    private static func instant(fromSampleTime raw: Any?) -> Date? {
        guard let sampleTime = raw as? [String: Any] else { return nil }
        return instant(fromISO: sampleTime["physicalTime"])
    }

    private static func instant(fromISO raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }
        return rfc3339.date(from: text)
    }

    /// Google's `google-duration` format: seconds with a trailing "s", as a
    /// string — `"1800s"` is thirty minutes.
    private static func durationMinutes(_ raw: Any?) -> Int? {
        guard let text = raw as? String, text.hasSuffix("s"),
              let seconds = Double(text.dropLast()) else { return nil }
        return Int((seconds / 60).rounded())
    }

    /// `{"year": 2026, "month": 8, "day": 1}` → "2026-08-01".
    private static func dayKey(from date: [String: Any]) -> String? {
        guard let year = date["year"] as? Int,
              let month = date["month"] as? Int,
              let day = date["day"] as? Int else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The local calendar day an interval starts in. `civilStartTime` is already
    /// local wall-clock, so it's preferred over the absolute timestamp — a walk
    /// at 11pm belongs to that evening, not to the next UTC day.
    private static func dayKey(fromInterval raw: Any?) -> String? {
        guard let interval = raw as? [String: Any] else { return nil }
        if let civil = interval["civilStartTime"] as? [String: Any],
           let key = dayKey(from: civil) {
            return key
        }
        if let civil = interval["civilStartTime"] as? String {
            return String(civil.prefix(10))
        }
        if let startTime = interval["startTime"] as? String,
           let date = rfc3339.date(from: startTime) {
            return date.dayKey
        }
        return nil
    }

    /// RFC-3339 with and without fractional seconds. `ISO8601DateFormatter`
    /// returns nil rather than coping when the input doesn't match its options
    /// exactly, and Google sends both forms.
    private enum rfc3339 {
        private static let withFraction: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()
        private static let plain: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()
        static func date(from string: String) -> Date? {
            withFraction.date(from: string) ?? plain.date(from: string)
        }
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
