import XCTest
@testable import Lumo

final class SettingsTests: XCTestCase {
    func test_defaults_matchSpec() {
        let s = SettingsSnapshot.defaults
        XCTAssertEqual(s.ollamaURL, "http://localhost:11434")
        XCTAssertEqual(s.model, "gemma4:e4b")
        XCTAssertEqual(s.keepAlive, "30m")
        XCTAssertEqual(s.maxImageLongEdge, 1280)
        XCTAssertEqual(s.temperature, 0.2, accuracy: 0.0001)
        XCTAssertTrue(s.doubleCopyEnabled)
        XCTAssertEqual(s.doubleCopyThresholdMs, 300)
        XCTAssertTrue(s.overwriteClipboardOnDoubleCopy)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertEqual(s.firstTokenTimeoutSec, 20)
        XCTAssertEqual(s.idleTimeoutSec, 8)
        XCTAssertEqual(s.hardTimeoutSec, 120)
    }
}
