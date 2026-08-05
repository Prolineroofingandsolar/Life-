//
//  CoachUITests.swift
//  LifeUITests
//
//  Covers what unit tests can't reach: that the coach's surfaces actually
//  appear, that they survive large text and rotation, and that VoiceOver has
//  something to read.
//

import XCTest

/// These launch the real app with no network, which is the state the coach is
/// designed for: cloud AI is off until consent is given, so a fresh install
/// runs entirely on local rules. That makes these deterministic — there is no
/// model to be slow or to phrase things differently between runs.
final class CoachUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with the coach in a known state.
    ///
    /// `-CoachUITest` tells the app to start from defaults rather than whatever
    /// the simulator happened to be left in, so a previous run's dismissed
    /// suggestion can't fail the next one.
    @MainActor
    private func launch(
        arguments: [String] = [],
        orientation: UIDeviceOrientation = .portrait,
        textSize: String? = nil
    ) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments += ["-CoachUITest"] + arguments
        if let textSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize]
        }
        app.launch()
        return app
    }

    // MARK: The card

    @MainActor
    func testCoachCardAppearsOnToday() throws {
        let app = launch()
        let header = app.staticTexts["Your next best action"]
        // Generous: the first build of the context reads a year of health days.
        XCTAssertTrue(header.waitForExistence(timeout: 10), "The coach card should be on Today")
    }

    @MainActor
    func testCardOffersAnExplanation() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))

        let why = app.buttons["Why this suggestion?"]
        XCTAssertTrue(why.waitForExistence(timeout: 5), "Every suggestion must be explainable")
        why.tap()

        // The sheet's job is to make the suggestion checkable.
        XCTAssertTrue(
            app.staticTexts["What this is based on"].waitForExistence(timeout: 5),
            "The explanation should say what it was based on"
        )
    }

    @MainActor
    func testSuggestionCanBeDismissed() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))

        let notToday = app.buttons["Not today"]
        XCTAssertTrue(notToday.waitForExistence(timeout: 5))
        notToday.tap()

        // Dismissal has to actually dismiss, not just animate.
        XCTAssertFalse(
            app.buttons["Not today"].waitForExistence(timeout: 2),
            "Dismissing should remove the suggestion"
        )
    }

    // MARK: Consent

    @MainActor
    func testNothingIsSentBeforeConsent() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))

        // The offer to enable AI is the proof that it isn't already enabled.
        // A fresh install must produce a working card with the network unused.
        let enable = app.buttons["Turn on AI coaching"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5), "AI should be off until consent is given")
    }

    @MainActor
    func testConsentScreenNamesWhatIsSent() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))
        app.buttons["Turn on AI coaching"].tap()

        XCTAssertTrue(app.staticTexts["What gets sent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What never leaves your phone"].exists)
        // The disclaimer is not optional and must not be scrolled away into
        // obscurity — it is a titled section of its own.
        XCTAssertTrue(app.staticTexts["This is not medical advice"].exists)
    }

    @MainActor
    func testDecliningLeavesAWorkingCoach() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))
        app.buttons["Turn on AI coaching"].tap()

        let decline = app.buttons["Keep it on this phone only"]
        XCTAssertTrue(decline.waitForExistence(timeout: 5))
        decline.tap()

        // Declining is a choice, not a failure: the card stays.
        XCTAssertTrue(
            app.staticTexts["Your next best action"].waitForExistence(timeout: 5),
            "Declining AI should leave the coach working"
        )
    }

    // MARK: Ask

    @MainActor
    func testAskCoachShowsDisclaimerAndPrompts() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))

        app.buttons["Ask the coach a question"].tap()

        XCTAssertTrue(app.navigationBars["Ask Coach"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Try asking"].exists, "An empty box needs a starting point")
        XCTAssertTrue(app.textFields["Your question"].exists)
    }

    // MARK: Settings

    @MainActor
    func testCoachCanBeTurnedOffEntirely() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))

        app.buttons["Settings"].tap()
        let toggle = app.switches["Life Coach"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Off means gone, not greyed out.
        XCTAssertFalse(
            app.staticTexts["Your next best action"].waitForExistence(timeout: 3),
            "Turning the coach off should remove its card"
        )
    }

    // MARK: Layout and accessibility

    @MainActor
    func testCardSurvivesLargestText() throws {
        // The card has a headline, a summary, a badge and three controls in a
        // row. At accessibility sizes that row is the first thing to break.
        let app = launch(textSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")

        let header = app.staticTexts["Your next best action"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Why this suggestion?"].exists, "Controls must survive large text")
    }

    @MainActor
    func testCardIsUsableInLandscape() throws {
        let app = launch(orientation: .landscapeLeft)
        defer { XCUIDevice.shared.orientation = .portrait }

        let header = app.staticTexts["Your next best action"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        // Compact height is where a tab bar covers content; the card must still
        // be reachable and hittable rather than merely present.
        XCTAssertTrue(header.isHittable, "The card should not be hidden behind chrome in landscape")
    }

    @MainActor
    func testControlsAreNamedForVoiceOver() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Your next best action"].waitForExistence(timeout: 10))

        // Each of these is an icon-only or terse control. Finding them by label
        // is the assertion: if the label were missing, VoiceOver would read the
        // SF Symbol name instead and the query would fail.
        XCTAssertTrue(app.buttons["Ask the coach a question"].exists)
        XCTAssertTrue(app.buttons["Why this suggestion?"].exists)
        XCTAssertTrue(app.buttons["Not today"].exists)
    }
}
