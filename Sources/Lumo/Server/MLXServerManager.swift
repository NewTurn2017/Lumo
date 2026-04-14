import Foundation
import Combine
import os

private let log = Logger(subsystem: "app.lumo.Lumo", category: "mlx-server")

// MARK: - Collaborator protocols (enable injection in tests)

protocol MLXInstalling: Sendable {
    func installIfNeeded() async throws
}

protocol MLXDetecting {
    func hasModel(modelID: String) -> Bool
}

@MainActor
protocol MLXRunning: AnyObject, Sendable {
    func start(modelID: String) throws
    func waitForReady() async -> Bool
    func stop()       // interactive — short grace (0.5s)
    func shutdown()   // app termination — long grace (3s)
    /// Called (on MainActor) when the process exits unexpectedly.
    /// Only fires for unintentional exits — intentional stop/shutdown sets this to nil first.
    var onUnexpectedDeath: (@MainActor @Sendable () -> Void)? { get set }
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
        log.info("enable() entered, status=\(String(describing: self.status), privacy: .public)")
        // Re-entrancy guard: reject if already in-flight or already running.
        // Only .stopped or .error can legitimately re-enter enable().
        switch status {
        case .stopped, .error:
            break
        case .installing, .starting, .running:
            log.info("enable() rejected by re-entrancy guard")
            return
        }
        status = .installing
        log.info("calling installer.installIfNeeded")
        do {
            try await installer.installIfNeeded()
        } catch {
            log.error("installer threw: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
            return
        }
        log.info("installer ok, calling detector.hasModel")
        guard detector.hasModel(modelID: modelID) else {
            log.error("detector says model missing")
            status = .error("모델 없음 — GitHub 설치 가이드를 확인하세요")
            return
        }
        log.info("detector ok, calling runner.start")
        status = .starting
        do {
            try runner.start(modelID: modelID)
        } catch {
            log.error("runner.start threw: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
            return
        }
        log.info("runner.start ok, waiting for ready")
        if await runner.waitForReady() {
            log.info("ready → .running")
            status = .running
            // Monitor for unexpected process death (OOM kill, crash, etc.).
            // Fires only while intentionally running; cleared on disable/shutdown.
            // Auto-restarts immediately so the server is ready before the next
            // translation attempt (model loading takes ~30-60 s).
            runner.onUnexpectedDeath = { [weak self] in
                guard let self else { return }
                log.error("MLX server exited unexpectedly — auto-restarting")
                self.status = .stopped
                Task { [weak self] in await self?.enable() }
            }
        } else {
            log.error("waitForReady timed out")
            runner.stop()
            status = .error("서버 시작 시간 초과")
        }
    }

    func disable() {
        runner.onUnexpectedDeath = nil   // prevent spurious callback during intentional stop
        runner.stop()
        status = .stopped
    }

    /// Synchronous force-stop for `applicationWillTerminate`.
    /// Uses the long-grace (3s) path — acceptable during app quit but
    /// not during interactive disable, which calls `runner.stop()`.
    func shutdown() {
        runner.onUnexpectedDeath = nil   // prevent spurious callback during intentional shutdown
        runner.shutdown()
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
    func hasModel(modelID: String) -> Bool {
        MLXPaths.detectModel(modelID: modelID, home: home) != nil
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
    var onUnexpectedDeath: (@MainActor @Sendable () -> Void)?

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        baseURL: URL = URL(string: "http://127.0.0.1:18080")!,
        session: URLSession = .shared
    ) {
        self.home = home
        self.baseURL = baseURL
        self.session = session
    }

    func start(modelID: String) throws {
        log.info("SubprocessMLXRunner.start enter, modelID=\(modelID, privacy: .public)")
        stop()  // idempotent: kill any lingering handle from a prior cycle
        // Reap any orphan mlx_lm.server occupying the port from a previous
        // crash / kill -9 / Xcode rebuild. Without this the new spawn would
        // hit EADDRINUSE, exit immediately, and waitForReady would silently
        // adopt the orphan — the manager would think it's running but its
        // handle would point at a dead child, so disable() couldn't kill
        // the actual server.
        Self.reapOrphanOnPort(baseURL.port ?? 8080)
        log.info("reap done, building LaunchOptions")
        let opts = MLXServerProcess.LaunchOptions(
            executable: MLXPaths.serverExecutable(home: home),
            modelID: modelID,
            logURL: Self.logURL()
        )
        log.info("calling MLXServerProcess.start")
        let h = try MLXServerProcess.start(opts)
        log.info("Process spawned pid=\(h.process.processIdentifier)")
        // Defensive: if mlx_lm.server died immediately (bad args, bind failure,
        // missing model), `process.isRunning` flips false within ~200ms. Detect
        // and surface as an error instead of stashing a dead handle.
        Thread.sleep(forTimeInterval: 0.25)
        guard h.process.isRunning else {
            log.info("Process died within 250ms — see \(h.logURL.path, privacy: .public)")
            throw NSError(
                domain: "SubprocessMLXRunner",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey:
                    "mlx_lm.server 가 시작 직후 종료되었습니다. 로그를 확인하세요: \(h.logURL.path)"]
            )
        }
        log.info("Process alive after 250ms, storing handle")
        // Detect unexpected process exits (OOM kill, crash, etc.).
        // Guard: if handle is nil when the handler fires, it was an intentional stop
        // (stop()/shutdown() clear handle BEFORE terminating the process).
        h.process.terminationHandler = { [weak self] (_: Process) in
            Task { @MainActor [weak self] in
                guard let self, self.handle != nil else { return }
                self.handle = nil
                self.onUnexpectedDeath?()
            }
        }
        handle = h
    }

    private static func reapOrphanOnPort(_ port: Int) {
        // lsof -ti tcp:<port> -sTCP:LISTEN → newline-separated PIDs
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", "tcp:\(port)", "-sTCP:LISTEN"]
        let outPipe = Pipe()
        lsof.standardOutput = outPipe
        lsof.standardError = FileHandle.nullDevice
        do { try lsof.run() } catch { return }
        lsof.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return }
        let pids = text.split(whereSeparator: { $0.isNewline }).compactMap { Int32($0) }
        guard !pids.isEmpty else { return }
        log.info("reaping \(pids.count) orphan PID(s) on port \(port)")
        for pid in pids { kill(pid, SIGTERM) }
        // Wait up to ~1s for graceful exit before SIGKILL
        for _ in 0..<20 {
            Thread.sleep(forTimeInterval: 0.05)
            if !Self.isPortInUse(port) { return }
        }
        for pid in pids { kill(pid, SIGKILL) }
        // Brief settle so the kernel releases the socket
        Thread.sleep(forTimeInterval: 0.1)
    }

    private static func isPortInUse(_ port: Int) -> Bool {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", "tcp:\(port)", "-sTCP:LISTEN"]
        lsof.standardOutput = FileHandle.nullDevice
        lsof.standardError = FileHandle.nullDevice
        do { try lsof.run() } catch { return false }
        lsof.waitUntilExit()
        return lsof.terminationStatus == 0
    }

    func waitForReady() async -> Bool {
        await MLXServerProcess.waitForReady(baseURL: baseURL, session: session)
    }

    func stop() {
        guard let h = handle else { return }
        handle = nil
        MLXServerProcess.stop(h, graceSeconds: 0.5)  // fast, for UI toggle
    }

    func shutdown() {
        guard let h = handle else { return }
        handle = nil
        MLXServerProcess.stop(h, graceSeconds: 3.0)  // patient, for app quit
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
