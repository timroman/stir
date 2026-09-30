import XCTest
@testable import stir

// The backstop is the can't-oversleep net (stir.md decision 14). Cancelling it
// is asynchronous, and stir can die mid-cancel — so the next launch decides
// whether to finish the job. AlarmKit itself needs a real device; this is the
// rule that decides, which does not.
final class AlarmBackstopTests: XCTestCase {

    func testABackstopFromANightThatEndedIsCancelled() {
        // Build 7 crashed while stopping the alarm, and the system alarm fired
        // afterwards for a night that was already over.
        XCTAssertTrue(AlarmBackstop.shouldCancelAtLaunch(hasScheduledBackstop: true, nightEnded: true))
    }

    func testABackstopFromANightThatNeverEndedIsKept() {
        // stir died at 3am. Nothing else will wake anybody: the net must fire.
        XCTAssertFalse(AlarmBackstop.shouldCancelAtLaunch(hasScheduledBackstop: true, nightEnded: false))
    }

    func testNothingToDoWithoutABackstop() {
        XCTAssertFalse(AlarmBackstop.shouldCancelAtLaunch(hasScheduledBackstop: false, nightEnded: true))
        XCTAssertFalse(AlarmBackstop.shouldCancelAtLaunch(hasScheduledBackstop: false, nightEnded: false))
    }
}
