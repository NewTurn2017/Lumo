import XCTest
@testable import Lumo

final class SettingsTests: XCTestCase {
    func test_defaults_matchSpec() {
        let s = SettingsSnapshot.defaults
        XCTAssertEqual(s.backendType, "mlx")
        XCTAssertEqual(s.ollamaURL, "http://localhost:8080")
        XCTAssertEqual(s.model, "mlx-community/gemma-4-e4b-it-4bit")
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
        XCTAssertTrue(s.mlxServerEnabled)
        XCTAssertEqual(s.popupSize, "medium")
    }

    func test_load_readsMlxServerEnabledOverride() {
        let suite = UserDefaults(suiteName: "SettingsTests.load")!
        suite.removePersistentDomain(forName: "SettingsTests.load")
        suite.set(false, forKey: SettingsKey.mlxServerEnabled)
        let s = SettingsSnapshot.load(from: suite)
        XCTAssertFalse(s.mlxServerEnabled)
    }
}
