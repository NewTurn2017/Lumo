import XCTest
@testable import Lumo

final class MenuBarStateTests: XCTestCase {
    func test_idleToBusyToDone() {
        var state: MenuBarState = .idle
        state = state.reduce(.beganTranslation)
        XCTAssertEqual(state, .busy)
        state = state.reduce(.finishedSuccessfully)
        XCTAssertEqual(state, .idle)
    }
    func test_errorThenSuccessClearsError() {
        var state: MenuBarState = .idle
        state = state.reduce(.beganTranslation)
        state = state.reduce(.failed("oops"))
        XCTAssertEqual(state, .error("oops"))
        state = state.reduce(.beganTranslation)
        XCTAssertEqual(state, .busy)
        state = state.reduce(.finishedSuccessfully)
        XCTAssertEqual(state, .idle)
    }
    func test_warningPersistsAcrossIdleSuccess() {
        var state: MenuBarState = .warning("server off")
        state = state.reduce(.beganTranslation)
        XCTAssertEqual(state, .busy)
        state = state.reduce(.finishedSuccessfully)
        XCTAssertEqual(state, .idle)
    }
}
