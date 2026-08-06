import Foundation
@testable import Life

// MARK: - Shared test doubles

/// A transport that returns whatever the test tells it to, and records what it
/// was sent.
///
/// Lifted out of `CoachServiceTests`, where it started life nested, so the
/// workout-builder suites use the same double rather than a copy that drifts.
/// Two stubs with subtly different behaviour is how one suite starts passing
/// for a reason the other would have caught.
///
/// The call count is the point in several tests: "did this cost one call or
/// two" is the difference between pennies and pounds.
final class StubTransport: CoachTransport, @unchecked Sendable {

    var responses: [Result<[String: Any], Error>]
    private(set) var sentBodies: [[String: Any]] = []

    init(_ responses: [Result<[String: Any], Error>]) {
        self.responses = responses
    }

    convenience init(_ single: [String: Any]) {
        self.init([.success(single)])
    }

    var callCount: Int { sentBodies.count }

    /// The mode string of the nth request, for asserting the right endpoint
    /// behaviour was asked for.
    func mode(at index: Int) -> String? {
        guard sentBodies.indices.contains(index) else { return nil }
        return sentBodies[index]["mode"] as? String
    }

    func question(at index: Int) -> String? {
        guard sentBodies.indices.contains(index) else { return nil }
        return sentBodies[index]["question"] as? String
    }

    func send(_ body: [String: Any], idToken: String) async throws -> [String: Any] {
        sentBodies.append(body)
        guard !responses.isEmpty else { return ["ok": true] }
        switch responses.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}

/// Fresh `UserDefaults` per test, so the cache in one doesn't answer another.
func isolatedCoachDefaults() -> UserDefaults {
    UserDefaults(suiteName: "coach-tests-\(UUID().uuidString)") ?? .standard
}

/// Cloud AI on and consented — the settings most tests need, spelled out once.
func cloudCoachSettings() -> CoachSettings {
    var settings = CoachSettings()
    settings.enabled = true
    settings.cloudEnabled = true
    settings.hasConsented = true
    return settings
}
