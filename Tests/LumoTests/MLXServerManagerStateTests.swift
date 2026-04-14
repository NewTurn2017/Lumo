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

    func test_unexpectedDeath_autorestartsServer() async throws {
        let runner = FakeRunner(readiness: true)
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: FakeInstaller(outcome: .success),
            detector: FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model")),
            runner: runner
        )
        await sut.enable()
        XCTAssertEqual(sut.status, .running)
        runner.didStart = false   // reset to detect the restart call

        runner.simulateUnexpectedDeath()

        // Immediate synchronous transition to .stopped (before auto-restart Task runs)
        XCTAssertEqual(sut.status, .stopped)

        // Allow the auto-restart Task to run; FakeRunner is synchronous so this is fast
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(sut.status, .running, "server must auto-restart after unexpected exit")
        XCTAssertTrue(runner.didStart, "start() must be called again during restart")
    }

    func test_disable_clears_onUnexpectedDeath_callback() async {
        let runner = FakeRunner(readiness: true)
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: FakeInstaller(outcome: .success),
            detector: FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model")),
            runner: runner
        )
        await sut.enable()
        XCTAssertNotNil(runner.onUnexpectedDeath, "callback must be set after enable")

        sut.disable()

        XCTAssertNil(runner.onUnexpectedDeath, "disable must clear callback to avoid spurious fires")
    }

    func test_managerShutdown_callsRunnerShutdownNotStop() async {
        let runner = FakeRunner(readiness: true)
        let sut = MLXServerManager(
            modelID: "mlx-community/gemma-4-e4b-it-4bit",
            installer: FakeInstaller(outcome: .success),
            detector: FakeDetector(modelPath: URL(fileURLWithPath: "/tmp/model")),
            runner: runner
        )
        await sut.enable()
        XCTAssertEqual(sut.status, .running)

        sut.shutdown()

        XCTAssertEqual(sut.status, .stopped)
        XCTAssertTrue(runner.didShutdown, "manager.shutdown must call runner.shutdown for the long grace path")
        XCTAssertFalse(runner.didStop, "manager.shutdown must NOT use the fast stop")
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
    let cached: Bool
    init(cached: Bool) { self.cached = cached }
    init(modelPath: URL?) { self.cached = (modelPath != nil) }  // back-compat for existing tests
    func hasModel(modelID: String) -> Bool { cached }
}

@MainActor
private final class FakeRunner: MLXRunning {
    let readiness: Bool
    var didStart = false
    var didStop = false
    var didShutdown = false
    var startedWithModelID: String?
    var onUnexpectedDeath: (@MainActor @Sendable () -> Void)?
    init(readiness: Bool) { self.readiness = readiness }
    func start(modelID: String) throws {
        didStart = true
        startedWithModelID = modelID
    }
    func waitForReady() async -> Bool { readiness }
    func stop() {
        onUnexpectedDeath = nil   // mirrors SubprocessMLXRunner behaviour
        didStop = true
    }
    func shutdown() {
        onUnexpectedDeath = nil
        didShutdown = true
    }
    /// Simulates an unexpected crash (e.g., OOM kill).
    func simulateUnexpectedDeath() { onUnexpectedDeath?() }
}
