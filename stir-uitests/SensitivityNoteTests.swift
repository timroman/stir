import XCTest

// Sensitivity is hard to choose without knowing what each setting is for, so
// the note under the picker changes with the choice (stir.md decision 59).
final class SensitivityNoteTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testEachSensitivityShowsItsOwnNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", "setup"]
        app.launch()

        let settings = app.buttons["setup.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15), "setup screen never appeared")
        settings.tap()

        let wake = app.buttons["wake"]
        XCTAssertTrue(wake.waitForExistence(timeout: 5), "settings never opened")
        wake.tap()

        // The alarm's settings only exist when the alarm does, and the
        // simulator carries whatever state the last run left behind
        let alarmToggle = app.switches["gentle alarm"]
        XCTAssertTrue(alarmToggle.waitForExistence(timeout: 5), "wake settings never opened")
        if alarmToggle.value as? String == "0" {
            alarmToggle.tap()
        }

        let picker = app.segmentedControls["wake.sensitivity"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "sensitivity picker missing")
        let note = app.staticTexts["wake.sensitivityNote"]

        XCTAssertEqual(picker.buttons.count, 3, "the picker should offer low, medium and high")

        var notes: [String: String] = [:]
        for choice in ["low", "medium", "high"] {
            picker.buttons[choice].tap()
            XCTAssertTrue(note.waitForExistence(timeout: 5), "no note under the picker")
            XCTAssertFalse(note.label.isEmpty, "\(choice) has an empty note")
            notes[choice] = note.label
        }
        XCTAssertEqual(Set(notes.values).count, 3, "sensitivity choices share a note: \(notes)")
    }
}
