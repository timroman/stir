import XCTest

// A user on an iPhone 15 reported that the night screen's stop control "doesn't
// work", while it worked for others. Screenshots and logs can't settle that —
// it needs taps. These drive the real control on a real simulator.
//
// The original two-tap confirm failed two ways: a 30x33pt hit target that a tap
// aimed in the dark could miss entirely, and a 5-second arming window that a
// deliberate slow tapper fell outside of every time, so the night never ended.
// It is now a hold.
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

    private func stopControl(_ app: XCUIApplication) -> XCUIElement {
        let stop = app.buttons["night.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "night screen never appeared")
        return stop
    }

    // Apple's minimum comfortable hit target is 44x44pt.
    func testStopControlMeetsMinimumHitTarget() {
        let stop = stopControl(launchIntoNight())
        let frame = stop.frame
        print("STOP_CONTROL_FRAME width=\(frame.width) height=\(frame.height)")
        XCTAssertGreaterThanOrEqual(frame.width, 44, "hit target is narrower than 44pt")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "hit target is shorter than 44pt")
    }

    // The control states its own gesture, so this is the whole interaction.
    func testHoldEndsTheNight() {
        let app = launchIntoNight()
        let stop = stopControl(app)
        XCTAssertEqual(stop.label.lowercased(), "hold to end", "control does not state its gesture")

        stop.press(forDuration: 2.0)
        XCTAssertTrue(app.buttons["setup.start"].waitForExistence(timeout: 5),
                      "holding did not end the night")
    }

    // The reason the control isn't a plain button: a phone brushed on a
    // nightstand must not end the night, because that also cancels the backstop.
    func testTapsDoNotEndTheNight() {
        let app = launchIntoNight()
        let stop = stopControl(app)

        for _ in 1...3 {
            stop.tap()
        }
        XCTAssertFalse(app.buttons["setup.start"].waitForExistence(timeout: 3),
                       "taps ended the night — a brushed screen would too")
    }

    // A hold shorter than the threshold is still an accident.
    func testBriefHoldDoesNotEndTheNight() {
        let app = launchIntoNight()
        let stop = stopControl(app)

        stop.press(forDuration: 0.4)
        XCTAssertFalse(app.buttons["setup.start"].waitForExistence(timeout: 3),
                       "a 0.4s touch ended the night")
    }
}
