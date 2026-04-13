import XCTest
@testable import Lumo

final class DoubleCopyDetectorTests: XCTestCase {
    func test_twoCopiesWithinThreshold_triggers() {
        var detector = DoubleCopyDetector(thresholdMs: 300)
        XCTAssertFalse(detector.observeCopy(atMs: 0, changeCount: 1))
        XCTAssertTrue(detector.observeCopy(atMs: 250, changeCount: 2))
    }

    func test_twoCopiesOutsideThreshold_doesNotTrigger() {
        var detector = DoubleCopyDetector(thresholdMs: 300)
        _ = detector.observeCopy(atMs: 0, changeCount: 1)
        XCTAssertFalse(detector.observeCopy(atMs: 400, changeCount: 2))
    }

    func test_changeCountNotIncreased_doesNotTrigger() {
        var detector = DoubleCopyDetector(thresholdMs: 300)
        _ = detector.observeCopy(atMs: 0, changeCount: 5)
        XCTAssertFalse(detector.observeCopy(atMs: 250, changeCount: 5))
    }

    func test_threeRapidCopies_firesOnceThenResets() {
        var detector = DoubleCopyDetector(thresholdMs: 300)
        _ = detector.observeCopy(atMs: 0, changeCount: 1)
        XCTAssertTrue(detector.observeCopy(atMs: 200, changeCount: 2))
        XCTAssertFalse(detector.observeCopy(atMs: 350, changeCount: 3))
    }
}
