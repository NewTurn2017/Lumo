import Foundation
import Combine

// MARK: - Collaborator protocols (enable injection in tests)

protocol MLXInstalling: Sendable {
    func installIfNeeded() async throws
}

protocol MLXDetecting {
    func detect(modelID: String) -> URL?
}

@MainActor
protocol MLXRunning: Sendable {
    func start(modelID: String) throws
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
            try await installer.installIfNeeded()
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        guard detector.detect(modelID: modelID) != nil else {
            status = .error("모델 없음 — GitHub 설치 가이드를 확인하세요")
            return
        }
        status = .starting
        do {
            try runner.start(modelID: modelID)
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

// MARK: - Real adapters

/// Reference-typed byte buffer used to safely collect subprocess output
/// from a background drain. All writes happen on a single background
/// queue, then ShellRunner.run `.wait()`s before reading — so this is
/// safe to mark `@unchecked Sendable`.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum ShellRunner {
    /// Runs a command to completion and returns (exitCode, stderr). stdout is
    /// discarded (routed to /dev/null). Used by the installer for one-shot
    /// commands.
    static func run(_ executable: URL, _ args: [String]) throws -> (Int32, String) {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = args

        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = FileHandle.nullDevice  // discard stdout entirely

        try proc.run()

        // Drain stderr concurrently to avoid pipe-buffer deadlock during
        // waitUntilExit(). readDataToEndOfFile blocks until the write side
        // closes (which happens when the subprocess exits).
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        proc.waitUntilExit()
        group.wait()

        let err = String(data: errBox.data, encoding: .utf8) ?? ""
        return (proc.terminationStatus, err)
    }
}

struct SystemMLXInstaller: MLXInstalling {
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func installIfNeeded() async throws {
        // pip install is slow — run off the MainActor to avoid freezing UI.
        let home = self.home
        try await Task.detached(priority: .utility) {
            try Self.doInstallIfNeeded(home: home)
        }.value
    }

    private static func doInstallIfNeeded(home: URL) throws {
        let fm = FileManager.default
        let venv = MLXPaths.venvRoot(home: home)

        if fm.fileExists(atPath: MLXPaths.serverExecutable(home: home).path) {
            return
        }

        try fm.createDirectory(
            at: venv.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let python3 = findPython3() else {
            throw NSError(
                domain: "MLXInstaller", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Python 3이 필요합니다"]
            )
        }
        let (venvCode, venvErr) = try ShellRunner.run(python3, ["-m", "venv", venv.path])
        guard venvCode == 0 else {
            throw NSError(
                domain: "MLXInstaller", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "venv 생성 실패: \(venvErr)"]
            )
        }

        let pip = MLXPaths.pipExecutable(home: home)
        let (pipCode, pipErr) = try ShellRunner.run(pip, ["install", "--quiet", "mlx-lm"])
        guard pipCode == 0 else {
            throw NSError(
                domain: "MLXInstaller", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "mlx-lm 설치 실패: \(pipErr)"]
            )
        }
    }

    private static func findPython3() -> URL? {
        for p in [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ] {
            if FileManager.default.isExecutableFile(atPath: p) {
                return URL(fileURLWithPath: p)
            }
        }
        return nil
    }
}

struct FileSystemMLXDetector: MLXDetecting {
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }
    func detect(modelID: String) -> URL? {
        MLXPaths.detectModel(modelID: modelID, home: home)
    }
}

/// Real runner. Pinned to `@MainActor` for compile-time enforcement of
/// the "all mutations originate on MainActor" invariant. Production
/// construction goes through `MLXServerManager.live(modelID:)`, which
/// is itself MainActor-isolated.
@MainActor
final class SubprocessMLXRunner: MLXRunning {
    let home: URL
    let baseURL: URL
    let session: URLSession
    private var handle: MLXServerProcess.Handle?

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        session: URLSession = .shared
    ) {
        self.home = home
        self.baseURL = baseURL
        self.session = session
    }

    func start(modelID: String) throws {
        stop()  // idempotent: kill any lingering handle from a prior cycle
        let opts = MLXServerProcess.LaunchOptions(
            executable: MLXPaths.serverExecutable(home: home),
            modelID: modelID,
            logURL: Self.logURL()
        )
        handle = try MLXServerProcess.start(opts)
    }

    func waitForReady() async -> Bool {
        await MLXServerProcess.waitForReady(baseURL: baseURL, session: session)
    }

    func stop() {
        guard let h = handle else { return }
        MLXServerProcess.stop(h)
        handle = nil
    }

    private static func logURL() -> URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return lib
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Lumo", isDirectory: true)
            .appendingPathComponent("mlx-server.log")
    }
}

extension MLXServerManager {
    /// Factory wiring the real adapters for production use.
    static func live(modelID: String) -> MLXServerManager {
        MLXServerManager(
            modelID: modelID,
            installer: SystemMLXInstaller(),
            detector: FileSystemMLXDetector(),
            runner: SubprocessMLXRunner()
        )
    }
}
