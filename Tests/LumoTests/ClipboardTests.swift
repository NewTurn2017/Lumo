import XCTest
@testable import Lumo

final class ClipboardTests: XCTestCase {
    func test_fakeClipboard_roundTrip() {
        let c = FakeClipboard()
        XCTAssertNil(c.string())
        c.setString("hello")
        XCTAssertEqual(c.string(), "hello")
        let before = c.changeCount
        c.setString("world")
        XCTAssertGreaterThan(c.changeCount, before)
    }
}
