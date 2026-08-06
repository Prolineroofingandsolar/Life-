import Foundation

// MARK: - App Configuration Validation

/// Checks at launch that the app's identity and capabilities line up.
///
/// Three warnings prompted this, and all three had the same character: the app
/// ran, nothing crashed, and a feature quietly didn't work.
///
/// 1. **Firebase bundle-ID mismatch.** `GoogleService-Info.plist` names
///    `uk.co.prolineroofingandsolar.life`; the target was building
///    `uk.co.prolineroofingandsolar.life.Life` — Xcode's default
///    `$(ORGANIZATION_IDENTIFIER).$(PRODUCT_NAME)`, which had silently appended
///    the product name to an identifier that already ended in it. Firebase logs
///    a warning and carries on, so the symptom is intermittent auth and sync
///    oddities rather than a failure.
/// 2. **Background task not advertised.** The target had
///    `GENERATE_INFOPLIST_FILE = YES` and no `INFOPLIST_FILE`, so the
///    hand-written `Life/Info.plist` — which declares the health refresh
///    identifier and the background modes — was not the plist that shipped.
///    `BGTaskScheduler.register` warns and refuses the identifier, and
///    background health refresh never runs.
/// 3. **Two AppIcon sets.** The widget's asset catalogue was a member of the
///    app target as well as its own, so two `AppIcon` sets compiled into one
///    binary and the winner was down to build order.
///
/// The bundle ID and plist are now correct in the project. This exists so that
/// if either drifts again it fails at launch in a debug build, loudly, with the
/// actual values printed — instead of costing another afternoon of wondering
/// why background refresh stopped.
enum AppConfiguration {

    /// A single thing that is wrong, in words that name the fix.
    struct Problem: Equatable, CustomStringConvertible {
        var summary: String
        var fix: String

        var description: String { "\(summary) \(fix)" }
    }

    /// Everything wrong with the current bundle's configuration.
    ///
    /// Pure and parameterised so it can be tested without a real bundle — the
    /// checks are the valuable part, and a test that needs a signed app to run
    /// is a test nobody runs.
    static func problems(
        bundleIdentifier: String?,
        firebaseBundleIdentifier: String?,
        permittedBackgroundIdentifiers: [String],
        backgroundModes: [String],
        backgroundTaskIdentifier: String = HealthBackgroundRefresh.taskIdentifier
    ) -> [Problem] {
        var problems: [Problem] = []

        if let firebaseBundleIdentifier, let bundleIdentifier,
           firebaseBundleIdentifier != bundleIdentifier {
            problems.append(Problem(
                summary: "Firebase is configured for \(firebaseBundleIdentifier) but this build is \(bundleIdentifier).",
                fix: "Set PRODUCT_BUNDLE_IDENTIFIER to \(firebaseBundleIdentifier), or download a GoogleService-Info.plist for the identifier you meant."
            ))
        }

        if !permittedBackgroundIdentifiers.contains(backgroundTaskIdentifier) {
            problems.append(Problem(
                summary: "\(backgroundTaskIdentifier) isn't in BGTaskSchedulerPermittedIdentifiers.",
                fix: "Add it to Life/Info.plist, and check the target's INFOPLIST_FILE actually points at that file."
            ))
        }

        // `fetch` is what a BGAppRefreshTask runs under; without it the task is
        // registered and then never scheduled.
        if !backgroundModes.contains("fetch") {
            problems.append(Problem(
                summary: "UIBackgroundModes doesn't include \"fetch\".",
                fix: "Add it to Life/Info.plist — BGAppRefreshTask needs it, and health data stops arriving in the background without it."
            ))
        }

        return problems
    }

    /// Runs the checks against the real bundle.
    ///
    /// In a debug build a problem is a trap: these are all mistakes in project
    /// configuration, they are all found in the first second of running, and
    /// every one of them costs more to diagnose later than it does to fix now.
    /// A release build logs instead — shipping a crash to a user over a plist
    /// key would be a worse outcome than the degraded feature.
    static func validate(bundle: Bundle = .main) {
        let found = problems(
            bundleIdentifier: bundle.bundleIdentifier,
            firebaseBundleIdentifier: firebaseBundleIdentifier(in: bundle),
            permittedBackgroundIdentifiers: bundle.object(
                forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers"
            ) as? [String] ?? [],
            backgroundModes: bundle.object(
                forInfoDictionaryKey: "UIBackgroundModes"
            ) as? [String] ?? []
        )

        guard !found.isEmpty else { return }

        for problem in found {
            print("[AppConfiguration] \(problem)")
        }

        #if DEBUG
        assertionFailure(
            "App configuration is wrong:\n" + found.map { "• \($0)" }.joined(separator: "\n")
        )
        #endif
    }

    /// The bundle ID Firebase was configured for, or nil when there is no
    /// plist — which is a supported way to run this app, so it is not a
    /// problem in itself. See `FirebaseBootstrap`.
    private static func firebaseBundleIdentifier(in bundle: Bundle) -> String? {
        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path) else { return nil }
        return plist["BUNDLE_ID"] as? String
    }
}
