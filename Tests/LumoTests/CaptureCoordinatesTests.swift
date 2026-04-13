import XCTest
@testable import Lumo

final class CaptureCoordinatesTests: XCTestCase {
    func test_bottomRegion_flipsToBottomInCG() {
        let result = CaptureCoordinates.displayLocalRect(
            viewRect: CGRect(x: 100, y: 100, width: 200, height: 50),
            screenHeight: 1080
        )
        XCTAssertEqual(result, CGRect(x: 100, y: 930, width: 200, height: 50))
    }

    func test_topRegion_flipsToTopInCG() {
        let result = CaptureCoordinates.displayLocalRect(
            viewRect: CGRect(x: 0, y: 1030, width: 100, height: 50),
            screenHeight: 1080
        )
        XCTAssertEqual(result, CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func test_symmetricCenter_isSelfDual() {
        let result = CaptureCoordinates.displayLocalRect(
            viewRect: CGRect(x: 250, y: 250, width: 500, height: 500),
            screenHeight: 1000
        )
        XCTAssertEqual(result, CGRect(x: 250, y: 250, width: 500, height: 500))
    }
}
