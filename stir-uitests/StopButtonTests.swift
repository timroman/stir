import XCTest

// A user on an iPhone 15 reported that the night screen's stop button "doesn't
// work", while it works for others. Screenshots and logs can't settle that —
// it needs taps. These drive the real control on a real simulator.
final class StopButtonTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// A night session with "up by" far enough out that nothing fades or fires
    /// mid-test.
    private func launchIntoNight() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "monitoring", "-upByMinutes", "480", "-noBackstop"]
        app.launch()
        return app
    }

    private func armedExpectation(_ stop: XCUIElement) -> XCTNSPredicateExpectation {
        XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS[c] 'tap again'"),
            object: stop
        )
    }

    // Apple's minimum comfortable hit target is 44x44pt. The control is a
    // chevron plus one line of subheadline text with no explicit frame, so its
    // tappable area is only as large as that content.
    func testStopButtonMeetsMinimumHitTarget() {
        let app = launchIntoNight()
        let stop = app.buttons["night.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "night screen never appeared")

        let frame = stop.frame
        print("STOP_BUTTON_FRAME width=\(frame.width) height=\(frame.height)")
        XCTAssertGreaterThanOrEqual(frame.width, 44, "hit target is narrower than 44pt")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "hit target is shorter than 44pt")
    }

    // The intended path: two taps close together end the night.
    func testTwoTapsInQuickSuccessionEndTheNight() {
        let app = launchIntoNight()
        let stop = app.buttons["night.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "night screen never appeared")

        stop.tap()
        XCTAssertEqual(XCTWaiter().wait(for: [armedExpectation(stop)], timeout: 3), .completed,
                       "first tap did not arm the control")

        stop.tap()
        XCTAssertTrue(app.buttons["setup.start"].waitForExistence(timeout: 5),
                      "second tap did not end the night")
    }

    // The suspected report: taps spaced further apart than the 5s arming window.
    // Each tap re-arms, so the session never ends however many times you tap.
    func testTapsSpacedBeyondTheArmingWindowNeverEndTheNight() {
        let app = launchIntoNight()
        let stop = app.buttons["night.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "night screen never appeared")

        for attempt in 1...3 {
            stop.tap()
            Thread.sleep(forTimeInterval: 6)  // arming window is 5s
            print("STOP_ATTEMPT \(attempt) label=\(stop.label)")
        }

        let ended = app.buttons["setup.start"].waitForExistence(timeout: 3)
        XCTAssertTrue(ended, "three taps never ended the night — the arming window expires between them")
    }
}
