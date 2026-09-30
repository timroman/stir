import XCTest
@testable import stir

final class NightStartCheckTests: XCTestCase {

    private func warnings(alarm: Bool = true, whiteNoise: Bool = true, volume: Float? = 0.8,
                          battery: Float? = 0.9, charging: Bool = false) -> NightStartCheck.Warnings {
        NightStartCheck.warnings(alarmEnabled: alarm, whiteNoiseEnabled: whiteNoise,
                                 volume: volume, batteryLevel: battery, isCharging: charging)
    }

    // MARK: - volume (decision 20, amended 29 september)

    func testVolumeIsNotQueriedWhenWhiteNoiseWillPlay() {
        // The volume is set by ear once the white noise is playing, so the
        // number at start is not the one the alarm will use
        XCTAssertFalse(warnings(whiteNoise: true, volume: 0.05).contains(.lowVolume))
    }

    func testLowVolumeWarnsWhenNothingElseWillPlay() {
        XCTAssertTrue(warnings(whiteNoise: false, volume: 0.2).contains(.lowVolume))
    }

    func testAdequateVolumeDoesNotWarn() {
        XCTAssertFalse(warnings(whiteNoise: false, volume: 0.3).contains(.lowVolume))
    }

    func testNoAlarmNightDoesNotWarnAboutVolume() {
        XCTAssertFalse(warnings(alarm: false, whiteNoise: false, volume: 0.05).contains(.lowVolume))
    }

    func testUnknownVolumeIsNotGuessedAt() {
        XCTAssertFalse(warnings(whiteNoise: false, volume: nil).contains(.lowVolume))
    }

    // MARK: - battery (decision 76)

    func testLowBatteryUnpluggedWarns() {
        XCTAssertTrue(warnings(battery: 0.22, charging: false).contains(.lowBattery))
    }

    func testLowBatteryOnTheChargerDoesNotWarn() {
        XCTAssertFalse(warnings(battery: 0.04, charging: true).contains(.lowBattery))
    }

    func testBatteryWarnsOnANoAlarmNightToo() {
        // A phone that dies takes the white noise with it, and the backstop
        XCTAssertTrue(warnings(alarm: false, battery: 0.1, charging: false).contains(.lowBattery))
    }

    func testUnknownBatteryIsNotGuessedAt() {
        XCTAssertFalse(warnings(battery: nil).contains(.lowBattery))
        XCTAssertFalse(warnings(battery: -1).contains(.lowBattery), "iOS reports -1 when it will not say")
    }

    // MARK: - both at once

    func testBothProblemsAreReportedTogether() {
        let both = warnings(whiteNoise: false, volume: 0.1, battery: 0.1, charging: false)
        XCTAssertTrue(both.contains(.lowVolume))
        XCTAssertTrue(both.contains(.lowBattery))
    }

    func testAGoodNightWarnsAboutNothing() {
        XCTAssertTrue(warnings().isEmpty)
    }
}
