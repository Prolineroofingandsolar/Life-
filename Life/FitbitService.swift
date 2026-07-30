import Foundation

// MARK: - Fitbit Service

/// Pulls health data from the Fitbit Web API and maps it into the same
/// `HealthDay` records the Apple Health import writes, so everything downstream
/// — the Health tab, the insights, Today's tiles — works identically whichever
/// source the data came from.
///
/// **On endpoint shapes:** `dev.fitbit.com` blocks automated access, so the
/// paths, response fields and date-range caps below come from Fitbit's
/// published reference rather than being verified against the live docs at
/// build time. They're all in one place for that reason. If a metric comes back
/// empty, check its path and JSON shape here first — and note the per-endpoint
/// error tolerance means one wrong path costs you that metric, not the sync.
@MainActor
final class FitbitService {

    static let shared = FitbitService()

    private let auth = FitbitAuth.shared

    var isConnected: Bool { auth.isConnected }

    // MARK: Range limits
    //
    // Fitbit caps how much history each endpoint returns in one request and
    // answers 400 if you ask for more. Requests are chunked to fit.

    private enum Limit {
        static let sleep = 100
        static let heart = 365
        /// hrv, br, spo2, cardioscore all share a 30-day ceiling.
        static let intradayDerived = 30
        static let timeSeries = 365
    }

    // MARK: - Result

    struct SyncResult {
        var days: [HealthDay] = []
        var steps: [String: Int] = [:]
        /// Metrics that failed, by name — surfaced so a partial sync says which
        /// parts are missing instead of silently looking complete.
        var failures: [String] = []
    }

    // MARK: - Sync

    /// Fetches everything Life stores, for the last `daysBack` days.
    ///
    /// Each metric is fetched independently and a failure in one is recorded
    /// rather than thrown: a rate limit or an endpoint change shouldn't cost you
    /// the sleep data that came back fine. Auth failures are the exception —
    /// those abort, because every subsequent call would fail the same way.
    func sync(daysBack: Int = 90) async throws -> SyncResult {
        guard FitbitConfig.isConfigured else { throw FitbitError.notConfigured }
        guard auth.isConnected else { throw FitbitError.notConnected }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: end) ?? end

        var byDay: [String: HealthDay] = [:]
        var result = SyncResult()

        func apply(_ name: String, _ work: () async throws -> Void) async {
            do {
                try await work()
            } catch let error as FitbitError {
                if case .http(401, _) = error { result.failures.append("auth") }
                else { result.failures.append(name) }
            } catch {
                result.failures.append(name)
            }
        }

        func day(_ key: String) -> HealthDay { byDay[key] ?? HealthDay(dayKey: key) }

        await apply("sleep") {
            for night in try await fetchSleep(start: start, end: end) {
                var d = day(night.dayKey)
                d.sleepMin = night.sleepMin
                d.deepMin = night.deepMin
                d.remMin = night.remMin
                d.lightMin = night.lightMin
                d.awakeMin = night.awakeMin
                d.bedtime = night.bedtime
                d.wakeTime = night.wakeTime
                byDay[night.dayKey] = d
            }
        }

        await apply("resting heart rate") {
            for (key, value) in try await fetchRestingHeartRate(start: start, end: end) {
                var d = day(key); d.restingHr = value; byDay[key] = d
            }
        }

        await apply("HRV") {
            for (key, value) in try await fetchHRV(start: start, end: end) {
                var d = day(key); d.hrvMs = value; byDay[key] = d
            }
        }

        await apply("breathing rate") {
            for (key, value) in try await fetchBreathingRate(start: start, end: end) {
                var d = day(key); d.respiratoryRate = value; byDay[key] = d
            }
        }

        await apply("SpO2") {
            for (key, value) in try await fetchSpO2(start: start, end: end) {
                var d = day(key); d.spo2Pct = value; byDay[key] = d
            }
        }

        await apply("cardio fitness") {
            for (key, value) in try await fetchVO2Max(start: start, end: end) {
                var d = day(key); d.vo2Max = value; byDay[key] = d
            }
        }

        await apply("calories") {
            for (key, value) in try await fetchTimeSeries("activities/activityCalories", start: start, end: end) {
                var d = day(key); d.activeEnergyKcal = value; byDay[key] = d
            }
        }

        await apply("active minutes") {
            for (key, value) in try await fetchTimeSeries("activities/minutesVeryActive", start: start, end: end) {
                var d = day(key); d.exerciseMinutes = Int(value); byDay[key] = d
            }
        }

        await apply("distance") {
            for (key, value) in try await fetchTimeSeries("activities/distance", start: start, end: end) {
                var d = day(key); d.distanceKm = value; byDay[key] = d
            }
        }

        await apply("floors") {
            for (key, value) in try await fetchTimeSeries("activities/floors", start: start, end: end) {
                var d = day(key); d.flights = Int(value); byDay[key] = d
            }
        }

        await apply("steps") {
            for (key, value) in try await fetchTimeSeries("activities/steps", start: start, end: end) where value > 0 {
                result.steps[key] = Int(value)
            }
        }

        // Skin temperature is deliberately not imported. Fitbit reports it as a
        // *relative* nightly variation from your own baseline, while HealthKit
        // reports an absolute wrist temperature — writing one into a field
        // holding the other would produce a chart that silently means two
        // different things. Better absent than wrong.

        if result.failures.contains("auth") { throw FitbitError.http(401, "") }

        result.days = byDay.values.filter { !$0.isEmpty }
        return result
    }

    // MARK: - Endpoints

    /// Sleep, keyed to the morning the night ended — the same convention the
    /// HealthKit import uses, and the one Fitbit's `dateOfSleep` already follows.
    private func fetchSleep(start: Date, end: Date) async throws -> [HealthDay] {
        var out: [HealthDay] = []
        for (from, to) in chunks(start: start, end: end, limit: Limit.sleep) {
            let response: SleepResponse = try await get("/1.2/user/-/sleep/date/\(key(from))/\(key(to)).json")
            for log in response.sleep where log.isMainSleep != false {
                var day = HealthDay(dayKey: log.dateOfSleep)
                day.sleepMin = log.minutesAsleep
                day.awakeMin = log.minutesAwake
                if let summary = log.levels?.summary {
                    day.deepMin = summary.deep?.minutes
                    day.remMin = summary.rem?.minutes
                    // Fitbit calls it "light"; on older devices without stage
                    // tracking it's "asleep" instead, which maps to the same slot.
                    day.lightMin = summary.light?.minutes ?? summary.asleep?.minutes
                }
                day.bedtime = Self.fitbitDateTime.date(from: log.startTime)
                day.wakeTime = Self.fitbitDateTime.date(from: log.endTime)
                out.append(day)
            }
        }
        return out
    }

    private func fetchRestingHeartRate(start: Date, end: Date) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        for (from, to) in chunks(start: start, end: end, limit: Limit.heart) {
            let response: HeartResponse = try await get("/1/user/-/activities/heart/date/\(key(from))/\(key(to)).json")
            for entry in response.activitiesHeart {
                if let resting = entry.value.restingHeartRate { out[entry.dateTime] = Double(resting) }
            }
        }
        return out
    }

    private func fetchHRV(start: Date, end: Date) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        for (from, to) in chunks(start: start, end: end, limit: Limit.intradayDerived) {
            let response: HRVResponse = try await get("/1/user/-/hrv/date/\(key(from))/\(key(to)).json")
            for entry in response.hrv { out[entry.dateTime] = entry.value.dailyRmssd }
        }
        return out
    }

    private func fetchBreathingRate(start: Date, end: Date) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        for (from, to) in chunks(start: start, end: end, limit: Limit.intradayDerived) {
            let response: BreathingResponse = try await get("/1/user/-/br/date/\(key(from))/\(key(to)).json")
            for entry in response.br { out[entry.dateTime] = entry.value.breathingRate }
        }
        return out
    }

    private func fetchSpO2(start: Date, end: Date) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        for (from, to) in chunks(start: start, end: end, limit: Limit.intradayDerived) {
            let response: [SpO2Entry] = try await get("/1/user/-/spo2/date/\(key(from))/\(key(to)).json")
            for entry in response { out[entry.dateTime] = entry.value.avg }
        }
        return out
    }

    private func fetchVO2Max(start: Date, end: Date) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        for (from, to) in chunks(start: start, end: end, limit: Limit.intradayDerived) {
            let response: CardioResponse = try await get("/1/user/-/cardioscore/date/\(key(from))/\(key(to)).json")
            for entry in response.cardioScore {
                if let value = Self.parseVO2(entry.value.vo2Max) { out[entry.dateTime] = value }
            }
        }
        return out
    }

    /// Fitbit's daily time series. Values arrive as strings, and the response
    /// key is the resource path with slashes turned into dashes — hence the
    /// dynamic decoding rather than a concrete type per metric.
    private func fetchTimeSeries(_ resource: String, start: Date, end: Date) async throws -> [String: Double] {
        var out: [String: Double] = [:]
        let responseKey = resource.replacingOccurrences(of: "/", with: "-")
        for (from, to) in chunks(start: start, end: end, limit: Limit.timeSeries) {
            let data = try await getRaw("/1/user/-/\(resource)/date/\(key(from))/\(key(to)).json")
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = object[responseKey] as? [[String: Any]] else {
                throw FitbitError.badResponse("no \(responseKey) in response")
            }
            for row in rows {
                guard let dateTime = row["dateTime"] as? String else { continue }
                if let string = row["value"] as? String, let value = Double(string) {
                    out[dateTime] = value
                } else if let number = row["value"] as? Double {
                    out[dateTime] = number
                }
            }
        }
        return out
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await getRaw(path)
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw FitbitError.badResponse("could not decode \(path)")
        }
        return decoded
    }

    private func getRaw(_ path: String) async throws -> Data {
        let token = try await auth.accessToken()
        var request = URLRequest(url: URL(string: FitbitConfig.apiBase + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Ask for metric units regardless of the account's locale, so distances
        // arrive in km and match what HealthDay stores.
        request.setValue("metric", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FitbitError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Helpers

    /// Splits a date range into windows the endpoint will actually accept.
    private func chunks(start: Date, end: Date, limit: Int) -> [(Date, Date)] {
        var out: [(Date, Date)] = []
        var cursor = start
        let calendar = Calendar.current
        while cursor < end {
            let next = calendar.date(byAdding: .day, value: limit - 1, to: cursor) ?? end
            out.append((cursor, min(next, end)))
            guard let step = calendar.date(byAdding: .day, value: limit, to: cursor) else { break }
            cursor = step
        }
        return out.isEmpty ? [(start, end)] : out
    }

    private func key(_ date: Date) -> String { date.dayKey }

    /// Fitbit reports cardio fitness either as a number or as a range like
    /// "42-46". A range collapses to its midpoint.
    private static func parseVO2(_ raw: String) -> Double? {
        if let single = Double(raw) { return single }
        let parts = raw.split(separator: "-").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0] + parts[1]) / 2
    }

    /// Fitbit's sleep timestamps are local time with no zone suffix.
    private static let fitbitDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Response Types

private struct SleepResponse: Decodable {
    let sleep: [SleepLog]
}

private struct SleepLog: Decodable {
    let dateOfSleep: String
    let minutesAsleep: Int?
    let minutesAwake: Int?
    let startTime: String
    let endTime: String
    let isMainSleep: Bool?
    let levels: SleepLevels?
}

private struct SleepLevels: Decodable {
    let summary: SleepSummaryLevels?
}

private struct SleepSummaryLevels: Decodable {
    let deep: SleepLevelDetail?
    let light: SleepLevelDetail?
    let rem: SleepLevelDetail?
    let wake: SleepLevelDetail?
    /// Devices without stage tracking report a flat "asleep" total instead.
    let asleep: SleepLevelDetail?
}

private struct SleepLevelDetail: Decodable {
    let minutes: Int?
}

private struct HeartResponse: Decodable {
    let activitiesHeart: [HeartEntry]
    enum CodingKeys: String, CodingKey { case activitiesHeart = "activities-heart" }
}

private struct HeartEntry: Decodable {
    let dateTime: String
    let value: HeartValue
}

private struct HeartValue: Decodable {
    let restingHeartRate: Int?
}

private struct HRVResponse: Decodable {
    let hrv: [HRVEntry]
}

private struct HRVEntry: Decodable {
    let dateTime: String
    let value: HRVValue
}

private struct HRVValue: Decodable {
    let dailyRmssd: Double
}

private struct BreathingResponse: Decodable {
    let br: [BreathingEntry]
}

private struct BreathingEntry: Decodable {
    let dateTime: String
    let value: BreathingValue
}

private struct BreathingValue: Decodable {
    let breathingRate: Double
}

private struct SpO2Entry: Decodable {
    let dateTime: String
    let value: SpO2Value
}

private struct SpO2Value: Decodable {
    let avg: Double
}

private struct CardioResponse: Decodable {
    let cardioScore: [CardioEntry]
}

private struct CardioEntry: Decodable {
    let dateTime: String
    let value: CardioValue
}

private struct CardioValue: Decodable {
    let vo2Max: String
}
