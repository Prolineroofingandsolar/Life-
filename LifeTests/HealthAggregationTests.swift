import Testing
import Foundation
@testable import Life

// MARK: - Interval reduction
//
// These cover `GoogleHealthService.reduceToDailyTotals`, the point at which a
// day's worth of raw readings becomes the one figure the app displays. Every
// step-inflation bug reported so far has been a fault in this reduction, and
// each is pinned here so it cannot come back quietly.

@MainActor
struct IntervalReductionTests {

    /// Builds a data point in the shape the API returns.
    private func point(
        id: String? = nil,
        source: String? = nil,
        day: String = "2026-08-05",
        from: String = "T08:00:00Z",
        to: String = "T08:15:00Z",
        count: Int
    ) -> [String: Any] {
        let body: [String: Any] = [
            "interval": [
                "startTime": "\(day)\(from)",
                "endTime": "\(day)\(to)",
                "civilStartTime": "\(day)T00:00:00"
            ],
            // The API sends int64 fields as JSON strings; keep that faithful.
            "count": "\(count)"
        ]

        var out: [String: Any] = ["steps": body]
        if let id { out["dataPointId"] = id }
        if let source { out["originDataSourceId"] = source }
        return out
    }

    private func reduce(_ points: [[String: Any]]) -> [String: Double] {
        let type = GoogleHealthService.DataType.interval("steps")
        let parsed = points.compactMap { raw in
            GoogleHealthService.intervalPoint(raw, type: type) {
                GoogleHealthService.double($0["count"])
            }
        }
        return GoogleHealthService.reduceToDailyTotals(parsed)
    }

    @Test func disjointSlicesFromOneSourceAreSummed() {
        let total = reduce([
            point(id: "a", source: "fitbit", from: "T08:00:00Z", to: "T08:15:00Z", count: 1_000),
            point(id: "b", source: "fitbit", from: "T09:00:00Z", to: "T09:15:00Z", count: 2_000),
        ])
        #expect(total["2026-08-05"] == 3_000)
    }

    /// The original inflation: the same reading arriving on two pages.
    @Test func repeatedPointIsCountedOnce() {
        let total = reduce([
            point(id: "a", source: "fitbit", count: 1_000),
            point(id: "a", source: "fitbit", count: 1_000),
        ])
        #expect(total["2026-08-05"] == 1_000)
    }

    /// A source that reports a running daily total rather than slices.
    @Test func wholeDaySnapshotsTakeTheLargest() {
        let total = reduce([
            point(id: "a", source: "fitbit", from: "T00:00:00Z", to: "T22:00:00Z", count: 4_000),
            point(id: "b", source: "fitbit", from: "T00:00:00Z", to: "T23:30:00Z", count: 9_000),
        ])
        #expect(total["2026-08-05"] == 9_000)
    }

    /// Two devices recording the same walk. Adding them reported a day at
    /// roughly double, which is the bug this pins.
    @Test func twoSourcesAreNotSummedTogether() {
        let total = reduce([
            point(id: "f1", source: "fitbit", from: "T08:00:00Z", to: "T08:15:00Z", count: 5_000),
            point(id: "f2", source: "fitbit", from: "T09:00:00Z", to: "T09:15:00Z", count: 3_000),
            point(id: "p1", source: "phone", from: "T08:00:00Z", to: "T08:15:00Z", count: 4_000),
            point(id: "p2", source: "phone", from: "T09:00:00Z", to: "T09:15:00Z", count: 2_000),
        ])
        // Fitbit 8,000 against the phone's 6,000 — not 14,000.
        #expect(total["2026-08-05"] == 8_000)
    }

    /// The fuller record wins, whichever source it happens to be.
    @Test func thePhoneWinsWhenItRecordedMore() {
        let total = reduce([
            point(id: "f1", source: "fitbit", count: 1_000),
            point(id: "p1", source: "phone", from: "T09:00:00Z", to: "T09:15:00Z", count: 7_000),
        ])
        #expect(total["2026-08-05"] == 7_000)
    }

    /// Attribution is optional in the payload. Without it every point falls
    /// into one bucket and the old summing behaviour stands — anything else
    /// would silently discard readings.
    @Test func unattributedPointsStillSum() {
        let total = reduce([
            point(id: "a", from: "T08:00:00Z", to: "T08:15:00Z", count: 1_000),
            point(id: "b", from: "T09:00:00Z", to: "T09:15:00Z", count: 2_000),
        ])
        #expect(total["2026-08-05"] == 3_000)
    }

    /// Two devices can record the identical interval. Before the source formed
    /// part of the identity, one of them was discarded as a repeat of the other
    /// — which is only correct by accident, and wrong as soon as the two
    /// disagree.
    @Test func identicalIntervalsFromDifferentSourcesAreDistinct() {
        let total = reduce([
            point(source: "fitbit", count: 5_000),
            point(source: "phone", count: 3_000),
        ])
        #expect(total["2026-08-05"] == 5_000)
    }

    @Test func daysAreReducedIndependently() {
        let total = reduce([
            point(id: "a", source: "fitbit", day: "2026-08-04", count: 1_000),
            point(id: "b", source: "fitbit", day: "2026-08-05", count: 2_000),
        ])
        #expect(total["2026-08-04"] == 1_000)
        #expect(total["2026-08-05"] == 2_000)
    }

    @Test func sourceIsReadFromEitherSpelling() {
        #expect(GoogleHealthService.sourceIdentity(["originDataSourceId": "a"]) == "a")
        #expect(GoogleHealthService.sourceIdentity(["dataSourceId": "b"]) == "b")
        #expect(GoogleHealthService.sourceIdentity(["dataOrigin": ["packageName": "c"]]) == "c")
        #expect(GoogleHealthService.sourceIdentity(["unrelated": "d"]) == "")
    }
}

// MARK: - Snapshot merging

/// Sign-in must never be able to lose a workout. The merge is the last line of
/// defence for that; the upload suppression in `AppState.loadFromCloud` is the
/// first.
struct SnapshotMergeTests {

    private func session(_ id: String) -> WorkoutSession {
        var out = WorkoutSession(name: "Session \(id)")
        out.id = id
        out.finishedAt = Date()
        return out
    }

    @Test func mergeKeepsSessionsFromBothSides() {
        var cloud = StateSnapshot()
        cloud.sessions = [session("a"), session("b")]

        var local = StateSnapshot()
        local.sessions = [session("c")]

        let merged = StateSnapshot.merged(preferring: local, with: cloud)
        #expect(Set(merged.sessions.map(\.id)) == ["a", "b", "c"])
    }

    /// The reinstall case: the device holds nothing but the account holds a
    /// history. Merging in either direction has to bring all of it back.
    @Test func emptyLocalNeverErasesCloudSessions() {
        var cloud = StateSnapshot()
        cloud.sessions = [session("a"), session("b")]

        let merged = StateSnapshot.merged(preferring: StateSnapshot(), with: cloud)
        #expect(merged.sessions.count == 2)
    }

    @Test func theSameSessionOnBothSidesIsNotDuplicated() {
        var cloud = StateSnapshot()
        cloud.sessions = [session("a")]

        var local = StateSnapshot()
        local.sessions = [session("a")]

        let merged = StateSnapshot.merged(preferring: local, with: cloud)
        #expect(merged.sessions.count == 1)
    }
}
