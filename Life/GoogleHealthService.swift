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

        func day(_ key: String) -> HealthDay { byDay[key] ?? HealthDay(dayKey: key) }

        func attempt(_ name: String, _ work: () async throws -> Void) async {
            guard !authFailed else { return }
            do {
                try await work()
            } catch let error as GoogleHealthError {
                if case .http(401, _) = error { authFailed = true }
                if case .http(403, _) = error { authFailed = true }
                result.failures.append(name)
            } catch {
                result.failures.append(name)
            }
        }

        // Sleep — filtered on civil end time, so a night belongs to the morning
        // it finished, matching the HealthKit import's convention.
        await attempt("sleep") {
            for point in try await list(.sleep, start: start, end: end) {
                guard let sleep = point["sleep"] as? [String: Any],
                      let interval = sleep["interval"] as? [String: Any],
                      let endTime = interval["endTime"] as? String,
                      let wake = Self.rfc3339.date(from: endTime) else { continue }

                // Skip naps. They're keyed to the same morning as the night
                // before, so without this an afternoon doze overwrites a full
                // night's figures with 20 minutes.
                let metadata = sleep["metadata"] as? [String: Any]
                if metadata?["nap"] as? Bool == true { continue }

                // Belt and braces for anything the nap flag misses: never let a
                // shorter session replace a longer one on the same day.
                let asleep = Self.int((sleep["summary"] as? [String: Any])?["minutesAsleep"]) ?? 0
                if let existing = byDay[wake.dayKey]?.sleepMin, existing >= asleep { continue }

                var d = day(wake.dayKey)
                if let summary = sleep["summary"] as? [String: Any] {
                    d.sleepMin = Self.int(summary["minutesAsleep"])
                    d.awakeMin = Self.int(summary["minutesAwake"])
                    for stage in summary["stagesSummary"] as? [[String: Any]] ?? [] {
                        guard let minutes = Self.int(stage["minutes"]) else { continue }
                        switch stage["type"] as? String {
                        case "DEEP":  d.deepMin = minutes
                        case "REM":   d.remMin = minutes
                        case "LIGHT": d.lightMin = minutes
                        case "AWAKE": d.awakeMin = minutes
                        // CLASSIC-type sleep reports a flat ASLEEP total with no
                        // stage breakdown; it's already in minutesAsleep.
                        default:      break
                        }
                    }
                }
                d.wakeTime = wake
                if let startTime = interval["startTime"] as? String {
                    d.bedtime = Self.rfc3339.date(from: startTime)
                }
                byDay[wake.dayKey] = d
            }
        }

        await attempt("resting heart rate") {
            for (key, value) in try await daily(.daily("dailyRestingHeartRate"), field: "beatsPerMinute", start: start, end: end) {
                var d = day(key); d.restingHr = value; byDay[key] = d
            }
        }

        await attempt("HRV") {
            for (key, value) in try await daily(.daily("dailyHeartRateVariability"),
                                                field: "averageHeartRateVariabilityMilliseconds",
                                                start: start, end: end) {
                var d = day(key); d.hrvMs = value; byDay[key] = d
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
            for (key, value) in try await daily(.daily("dailySleepTemperatureDerivations"),
                                                field: "nightlyTemperatureCelsius",
                                                start: start, end: end) {
                var d = day(key); d.wristTempC = value; byDay[key] = d
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

        if authFailed, let first = result.failures.first {
            throw GoogleHealthError.http(403, "failed on \(first)")
        }

        result.days = byDay.values.filter { !$0.isEmpty }
        return result
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
        let isDaily = type.timeField == "date"
        let from = isDaily ? Self.isoDay.string(from: start) : Self.isoDay.string(from: start)
        let to = isDaily ? Self.isoDay.string(from: end) : Self.isoDay.string(from: end)
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

    private static func int(_ raw: Any?) -> Int? {
        double(raw).map { Int($0.rounded()) }
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
