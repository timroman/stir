import XCTest

// Sensitivity is hard to choose without knowing what each setting is for, so
// its screen describes all three at once (stir.md decision 59).
final class SensitivityNoteTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// A list only builds what it shows, so anything below the fold has to be
    /// scrolled to before it exists at all — same as it would be for a person.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 5) -> Bool {
        if element.waitForExistence(timeout: 5) { return true }
        for _ in 0..<swipes {
            app.swipeUp()
            if element.exists { return true }
        }
        return false
    }

    func testEachSensitivityShowsItsOwnNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "setup"]
        app.launch()

        let settings = app.buttons["setup.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "setup screen never appeared")
        settings.tap()

        // The alarm's settings only exist when the alarm does, and the
        // simulator carries whatever state the last run left behind
        let alarmToggle = app.switches["alarm"]
        XCTAssertTrue(scrollTo(alarmToggle, in: app), "settings never opened")
        if alarmToggle.value as? String == "0" {
            alarmToggle.tap()
        }

        let sensitivity = app.buttons["wake.sensitivity"]
        XCTAssertTrue(scrollTo(sensitivity, in: app), "no way into sensitivity")
        sensitivity.tap()

        var notes: [String: String] = [:]
        for choice in ["low", "medium", "high"] {
            let note = app.staticTexts["sensitivity.note.\(choice)"]
            XCTAssertTrue(note.waitForExistence(timeout: 5), "\(choice) has no note")
            XCTAssertFalse(note.label.isEmpty, "\(choice) has an empty note")
            notes[choice] = note.label
        }
        XCTAssertEqual(Set(notes.values).count, 3, "sensitivity choices share a note: \(notes)")

        // Choosing one is what the screen is for
        app.buttons["sensitivity.low"].tap()
        XCTAssertTrue(app.images["checkmark.circle.fill"].waitForExistence(timeout: 5),
                      "choosing a sensitivity showed no mark")
    }
}
