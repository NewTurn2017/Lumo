import Foundation
import Combine

// MARK: - Collaborator protocols (enable injection in tests)

protocol MLXInstalling {
    func installIfNeeded() throws
}

protocol MLXDetecting {
    func detect(modelID: String) -> URL?
}

protocol MLXRunning {
    func start(modelPath: URL) throws
    func waitForReady() async -> Bool
    func stop()
}

// MARK: - Manager

@MainActor
final class MLXServerManager: ObservableObject {
    enum Status: Equatable {
        case stopped
        case installing
        case starting
        case running
        case error(String)
    }

    @Published private(set) var status: Status = .stopped

    let modelID: String
    private let installer: MLXInstalling
    private let detector: MLXDetecting
    private let runner: MLXRunning

    init(
        modelID: String,
        installer: MLXInstalling,
        detector: MLXDetecting,
        runner: MLXRunning
    ) {
        self.modelID = modelID
        self.installer = installer
        self.detector = detector
        self.runner = runner
    }

    func enable() async {
        // Re-entrancy guard: reject if already in-flight or already running.
        // Only .stopped or .error can legitimately re-enter enable().
        switch status {
        case .stopped, .error:
            break
        case .installing, .starting, .running:
            return
        }
        status = .installing
        do {
            try installer.installIfNeeded()
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        guard let modelPath = detector.detect(modelID: modelID) else {
            status = .error("모델 없음 — GitHub 설치 가이드를 확인하세요")
            return
        }
        status = .starting
        do {
            try runner.start(modelPath: modelPath)
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        if await runner.waitForReady() {
            status = .running
        } else {
            runner.stop()
            status = .error("서버 시작 시간 초과")
        }
    }

    func disable() {
        runner.stop()
        status = .stopped
    }

    /// Synchronous force-stop for `applicationWillTerminate`.
    /// Delegates to the runner; the real runner implementation in Task 7
    /// is responsible for SIGTERM → grace → SIGKILL.
    func shutdown() {
        runner.stop()
        status = .stopped
    }
}
