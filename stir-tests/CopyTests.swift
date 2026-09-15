import XCTest
@testable import stir

// stir.md decision 30: every word stir shows is lowercase, except the names of
// things that belong to somebody else.
final class CopyTests: XCTestCase {

    func testSoundImportErrorsAreLowercase() {
        for error in [CustomSoundError.accessDenied, .directoryNotFound, .copyFailed] {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty)
            XCTAssertEqual(message, message.lowercased(), "\(error) is capitalized")
        }
    }
}
