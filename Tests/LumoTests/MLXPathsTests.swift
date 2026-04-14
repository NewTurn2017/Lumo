import XCTest
@testable import Lumo

final class MLXPathsTests: XCTestCase {
    func test_venvPath_isUnderLocalShareLumo() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let venv = MLXPaths.venvRoot(home: home)
        XCTAssertEqual(venv.path, "/Users/tester/.local/share/Lumo/mlx-venv")
    }

    func test_serverExecutable_pointsAtVenvBin() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let exe = MLXPaths.serverExecutable(home: home)
        XCTAssertEqual(exe.path, "/Users/tester/.local/share/Lumo/mlx-venv/bin/mlx_lm.server")
    }

    func test_hfHubRoot_usesDefaultCache() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let hub = MLXPaths.hfHubRoot(home: home)
        XCTAssertEqual(hub.path, "/Users/tester/.cache/huggingface/hub")
    }

    func test_hfFolderName_encodesModelID() {
        XCTAssertEqual(
            MLXPaths.hfFolderName(modelID: "mlx-community/gemma-4-e4b-it-4bit"),
            "models--mlx-community--gemma-4-e4b-it-4bit"
        )
    }

    func test_hfFolderName_handlesMultipleSlashes() {
        XCTAssertEqual(
            MLXPaths.hfFolderName(modelID: "org/family/variant"),
            "models--org--family--variant"
        )
    }

    func test_hfFolderName_handlesNoOrg() {
        XCTAssertEqual(
            MLXPaths.hfFolderName(modelID: "solo"),
            "models--solo"
        )
    }
}
