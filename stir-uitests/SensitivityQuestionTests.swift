import XCTest

// Auto sensitivity asks "was that too sensitive?" on the alarm screen, only
// once the alarm is stopped, and only when it cannot decide on its own
// (stir.md decision 67).
final class SensitivityQuestionTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchIntoAlarm(asking: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "alarm"] + (asking ? ["-askSensitivity"] : [])
        app.launch()
        return app
    }

    func testStoppingShowsTheQuestionAndNoLandsOnSetup() {
        let app = launchIntoAlarm(asking: true)

        let stop = app.buttons["alarm.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "alarm screen never appeared")
        XCTAssertFalse(app.staticTexts["alarm.sensitivityQuestion"].exists, "asked before the alarm was stopped")
        stop.tap()

        XCTAssertTrue(app.staticTexts["alarm.sensitivityQuestion"].waitForExistence(timeout: 5),
                      "stopping did not ask the question")
        XCTAssertTrue(app.buttons["alarm.yes"].exists)
        app.buttons["alarm.no"].tap()

        XCTAssertTrue(app.buttons["setup.start"].waitForExistence(timeout: 5), "answering did not land on setup")
    }

    func testWithoutAQuestionStoppingLandsOnSetup() {
        let app = launchIntoAlarm(asking: false)

        let stop = app.buttons["alarm.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 15), "alarm screen never appeared")
        stop.tap()

        XCTAssertTrue(app.buttons["setup.start"].waitForExistence(timeout: 5), "stopping did not land on setup")
        XCTAssertFalse(app.staticTexts["alarm.sensitivityQuestion"].exists)
    }
}
