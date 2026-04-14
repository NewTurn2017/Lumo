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

    func test_detectModel_returnsNilWhenCacheMissing() throws {
        let tmp = try makeTmpHome()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let found = MLXPaths.detectModel(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            home: tmp
        )
        XCTAssertNil(found)
    }

    func test_detectModel_returnsNilWhenFolderMissing() throws {
        let tmp = try makeTmpHome()
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(
            at: MLXPaths.hfHubRoot(home: tmp),
            withIntermediateDirectories: true
        )
        let found = MLXPaths.detectModel(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            home: tmp
        )
        XCTAssertNil(found)
    }

    func test_detectModel_returnsFolderWhenPresent() throws {
        let tmp = try makeTmpHome()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hub = MLXPaths.hfHubRoot(home: tmp)
        let modelDir = hub.appendingPathComponent(
            "models--mlx-community--gemma-4-e4b-it-4bit",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: modelDir,
            withIntermediateDirectories: true
        )

        let found = MLXPaths.detectModel(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            home: tmp
        )
        XCTAssertEqual(found?.path, modelDir.path)
    }

    private func makeTmpHome() throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumo-mlxpaths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }
}
