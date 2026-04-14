import XCTest
@testable import Lumo

@MainActor
final class MLXServerManagerStateTests: XCTestCase {
    func test_enable_happyPath_reachesRunning() async {
        let installer = FakeInstaller(outcome: .success)
        let detector = FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model"))
        let runner = FakeRunner(readiness: true)
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: installer,
            detector: detector,
            runner: runner
        )

        await sut.enable()

        XCTAssertEqual(sut.status, .running)
        XCTAssertTrue(installer.didInstall)
        XCTAssertTrue(runner.didStart)
        XCTAssertEqual(runner.startedWithModelID, "mlx-community/gemma-4-e4b-it-4bit")
    }

    func test_enable_modelMissing_reachesErrorWithGuide() async {
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: FakeInstaller(outcome: .success),
            detector: FakeDetector(modelPath: nil),
            runner: FakeRunner(readiness: true)
        )

        await sut.enable()

        guard case .error(let msg) = sut.status else {
            return XCTFail("expected .error, got \(sut.status)")
        }
        XCTAssertTrue(msg.contains("모델"))
    }

    func test_enable_installFails_reachesError() async {
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: FakeInstaller(outcome: .failure("pip boom")),
            detector: FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model")),
            runner: FakeRunner(readiness: true)
        )
        await sut.enable()
        guard case .error(let msg) = sut.status else {
            return XCTFail("expected .error, got \(sut.status)")
        }
        XCTAssertTrue(msg.contains("pip boom"))
    }

    func test_enable_serverNotReady_reachesError() async {
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: FakeInstaller(outcome: .success),
            detector: FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model")),
            runner: FakeRunner(readiness: false)
        )
        await sut.enable()
        guard case .error = sut.status else {
            return XCTFail("expected .error, got \(sut.status)")
        }
    }

    func test_enable_secondCallWhileRunning_isNoOp() async {
        let installer = FakeInstaller(outcome: .success)
        let detector = FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model"))
        let runner = FakeRunner(readiness: true)
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: installer,
            detector: detector,
            runner: runner
        )

        await sut.enable()
        XCTAssertEqual(sut.status, .running)
        installer.didInstall = false
        runner.didStart = false

        // Second call: should be a no-op since we're already running.
        await sut.enable()

        XCTAssertEqual(sut.status, .running)
        XCTAssertFalse(installer.didInstall, "installer must not re-run while manager is running")
        XCTAssertFalse(runner.didStart, "runner must not re-start while manager is running")
    }

    func test_disable_transitionsFromRunningToStopped() async {
        let runner = FakeRunner(readiness: true)
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: FakeInstaller(outcome: .success),
            detector: FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model")),
            runner: runner
        )
        await sut.enable()
        XCTAssertEqual(sut.status, .running)

        sut.disable()

        XCTAssertEqual(sut.status, .stopped)
        XCTAssertTrue(runner.didStop)
    }
}

// MARK: - Fakes

private final class FakeInstaller: MLXInstalling, @unchecked Sendable {
    enum Outcome { case success; case failure(String) }
    let outcome: Outcome
    var didInstall = false
    init(outcome: Outcome) { self.outcome = outcome }
    func installIfNeeded() async throws {
        didInstall = true
        if case .failure(let msg) = outcome {
            throw NSError(
                domain: "test",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }
}

private final class FakeDetector: MLXDetecting {
    let result: URL?
    init(modelPath: URL?) { self.result = modelPath }
    func detect(modelID: String) -> URL? { result }
}

@MainActor
private final class FakeRunner: MLXRunning {
    let readiness: Bool
    var didStart = false
    var didStop = false
    var startedWithModelID: String?
    init(readiness: Bool) { self.readiness = readiness }
    func start(modelID: String) throws {
        didStart = true
        startedWithModelID = modelID
    }
    func waitForReady() async -> Bool { readiness }
    func stop() { didStop = true }
}
