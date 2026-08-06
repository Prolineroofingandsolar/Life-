import Testing
import Foundation
@testable import Life

/// Project configuration that used to fail silently.
///
/// Every one of these was a runtime warning the app shrugged off: it launched,
/// nothing crashed, and a feature quietly didn't work. That is the worst shape
/// for a bug to take, so the checks exist to turn each one into a debug-build
/// assertion — and these tests exist because a check nobody has exercised is a
/// check that fires on the wrong thing.
struct AppConfigurationTests {

    @Test("A bundle ID that disagrees with Firebase is reported, with both values")
    func mismatchedBundleIdentifierIsReported() {
        let problems = AppConfiguration.problems(
            bundleIdentifier: "uk.co.prolineroofingandsolar.life.Life",
            firebaseBundleIdentifier: "uk.co.prolineroofingandsolar.life",
            permittedBackgroundIdentifiers: [HealthBackgroundRefresh.taskIdentifier],
            backgroundModes: ["fetch"]
        )

        #expect(problems.count == 1)
        // Both identifiers in the message. "Bundle ID mismatch" on its own sends
        // someone hunting through two plists and a build setting; the two
        // strings side by side make the typo obvious — here, Xcode's default
        // having appended the product name to an identifier already ending in it.
        #expect(problems.first?.summary.contains("this build is uk.co.prolineroofingandsolar.life.Life") == true)
        #expect(problems.first?.summary.contains("configured for uk.co.prolineroofingandsolar.life ") == true)
    }

    @Test("Matching identifiers are not a problem")
    func matchingConfigurationIsClean() {
        let problems = AppConfiguration.problems(
            bundleIdentifier: "uk.co.prolineroofingandsolar.life",
            firebaseBundleIdentifier: "uk.co.prolineroofingandsolar.life",
            permittedBackgroundIdentifiers: [HealthBackgroundRefresh.taskIdentifier],
            backgroundModes: ["fetch", "processing"]
        )

        #expect(problems.isEmpty)
    }

    @Test("No Firebase plist is a supported way to run, not a fault")
    func absentFirebasePlistIsNotAProblem() {
        // The app is designed to run local-only when there is no
        // GoogleService-Info.plist — see `FirebaseBootstrap`. Reporting that as
        // misconfiguration would make every local build assert on launch.
        let problems = AppConfiguration.problems(
            bundleIdentifier: "uk.co.prolineroofingandsolar.life",
            firebaseBundleIdentifier: nil,
            permittedBackgroundIdentifiers: [HealthBackgroundRefresh.taskIdentifier],
            backgroundModes: ["fetch"]
        )

        #expect(problems.isEmpty)
    }

    @Test("An unadvertised background task identifier is reported")
    func unadvertisedBackgroundTaskIsReported() {
        let problems = AppConfiguration.problems(
            bundleIdentifier: "uk.co.prolineroofingandsolar.life",
            firebaseBundleIdentifier: "uk.co.prolineroofingandsolar.life",
            permittedBackgroundIdentifiers: [],
            backgroundModes: ["fetch"]
        )

        #expect(problems.count == 1)
        #expect(problems.first?.summary.contains(HealthBackgroundRefresh.taskIdentifier) == true)
        // The fix names the file *and* the build setting, because the actual
        // cause was the target ignoring that file entirely.
        #expect(problems.first?.fix.contains("INFOPLIST_FILE") == true)
    }

    @Test("Missing background fetch is reported")
    func missingFetchModeIsReported() {
        let problems = AppConfiguration.problems(
            bundleIdentifier: "uk.co.prolineroofingandsolar.life",
            firebaseBundleIdentifier: "uk.co.prolineroofingandsolar.life",
            permittedBackgroundIdentifiers: [HealthBackgroundRefresh.taskIdentifier],
            backgroundModes: ["processing"]
        )

        #expect(problems.count == 1)
        #expect(problems.first?.summary.contains("fetch") == true)
    }

    @Test("Several problems are all reported, not just the first")
    func problemsAreCumulative() {
        let problems = AppConfiguration.problems(
            bundleIdentifier: "com.example.wrong",
            firebaseBundleIdentifier: "uk.co.prolineroofingandsolar.life",
            permittedBackgroundIdentifiers: [],
            backgroundModes: []
        )

        // Fixing one and relaunching to discover the next is three launches for
        // three one-line fixes.
        #expect(problems.count == 3)
    }
}

// MARK: - Provenance

/// The label under every piece of coach output.
///
/// The failure this replaced was a silent one: when Gemini failed, the card kept
/// the "AI coach" label and showed a rule-based line underneath it. Gemini
/// looked useless, the rules got the credit, and the person had no way to tell
/// which they were reading — so neither could be trusted afterwards.
struct CoachProvenanceTests {

    static let noon = Date(timeIntervalSince1970: 1_754_481_600) // 06/08/2026, 12:00 UTC

    @Test("Model output names the model and when it was written")
    func geminiIsNamed() {
        let provenance = CoachProvenance.cloud(at: Self.noon)

        #expect(provenance.primaryLabel.hasPrefix("Gemini · updated"))
        #expect(provenance.needsAttention == false)
    }

    @Test("A deliberate local suggestion is labelled on-device, not as a failure")
    func onDeviceIsNotAFailure() {
        let provenance = CoachProvenance.local(at: Self.noon)

        #expect(provenance.primaryLabel == "On-device suggestion")
        // Cloud AI being switched off is a choice, not a fault, and colouring it
        // like an error would nag someone for a setting they meant to set.
        #expect(provenance.needsAttention == false)
        #expect(provenance.isRetryable == false)
    }

    @Test("A failed call says so, and offers a retry")
    func failureIsVisible() {
        let provenance = CoachProvenance(
            origin: .offlineFallback,
            generatedAt: Self.noon,
            failureNote: "The coach is unavailable.",
            isRetryable: true
        )

        #expect(provenance.primaryLabel == "Offline suggestion · Gemini unavailable")
        #expect(provenance.needsAttention)
        #expect(provenance.isRetryable)
    }

    @Test("A spend ceiling is named as a limit and offers no retry")
    func usageLimitIsNotRetryable() {
        let provenance = CoachProvenance(
            origin: .usageLimited,
            generatedAt: Self.noon,
            failureNote: "This month's AI limit has been reached."
        )

        #expect(provenance.primaryLabel.contains("AI limit reached"))
        // Retrying a spend ceiling fails again identically, and a button that
        // never works teaches people that buttons don't work.
        #expect(provenance.isRetryable == false)
    }

    @Test("Cached output says when it was written, not when it was read")
    func cachedOutputSaysSo() {
        var provenance = CoachProvenance.cloud(at: Self.noon)
        provenance.wasCached = true

        #expect(provenance.primaryLabel.contains("cached from"))
        #expect(provenance.primaryLabel.contains("Gemini"))
    }

    @Test("Data freshness is a separate claim from when the words were written")
    func dataAgeIsStatedSeparately() {
        let provenance = CoachProvenance.cloud(
            at: Self.noon,
            dataUpdatedAt: Self.noon.addingTimeInterval(-6 * 3600)
        )

        // Advice written a minute ago from six-hour-old data is six hours old,
        // and only one of those two times tells you whether to act on it.
        #expect(provenance.dataLabel?.hasPrefix("Based on data updated") == true)
        #expect(provenance.dataLabel != provenance.primaryLabel)
    }

    @Test("Retry is offered exactly where retrying could help")
    func retryabilityMatchesTheError() {
        #expect(CoachService.isRetryable(.transport("offline")))
        #expect(CoachService.isRetryable(.invalidResponse("bad json")))
        #expect(CoachService.isRetryable(nil))

        #expect(!CoachService.isRetryable(.limitReached("no budget")))
        #expect(!CoachService.isRetryable(.disabled))
        #expect(!CoachService.isRetryable(.notSignedIn))
        #expect(!CoachService.isRetryable(.notConfigured))
    }

    @Test("The spoken label carries everything the printed one shows")
    func accessibilityLabelIsComplete() {
        let provenance = CoachProvenance(
            origin: .offlineFallback,
            generatedAt: Self.noon,
            dataUpdatedAt: Self.noon,
            failureNote: "The coach is unavailable.",
            isRetryable: true
        )

        // The provenance line is three separate `Text` views on screen. Combined
        // into one element, VoiceOver must still get all three facts rather than
        // just the first.
        #expect(provenance.accessibilityLabel.contains("Offline suggestion"))
        #expect(provenance.accessibilityLabel.contains("Based on data updated"))
        #expect(provenance.accessibilityLabel.contains("unavailable"))
    }
}
