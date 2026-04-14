import Foundation

/// Low-level subprocess + readiness-probe helpers for the MLX server.
/// Stateless — all functions take every dependency they need.
enum MLXServerProcess {
    /// Polls `GET <baseURL>/v1/models` until a 200 is returned or `timeout` elapses.
    /// Returns true on success, false on timeout.
    /// At least one probe is always issued, even when `timeout` is `.zero`.
    static func waitForReady(
        baseURL: URL,
        session: URLSession = .shared,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(60)
    ) async -> Bool {
        let probe = baseURL.appendingPathComponent("v1").appendingPathComponent("models")
        let deadline = ContinuousClock.now + timeout
        let probeTimeout = min(Self.seconds(pollInterval), 3.0)
        repeat {
            if await probeOnce(url: probe, session: session, probeTimeout: probeTimeout) {
                return true
            }
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero { return false }
            // Clamp sleep so we don't overshoot the deadline. `remaining` is
            // guaranteed > .zero here.
            try? await Task.sleep(for: min(pollInterval, remaining))
        } while ContinuousClock.now < deadline
        return false
    }

    /// Converts a `Duration` to seconds as a `Double`.
    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private static func probeOnce(url: URL, session: URLSession, probeTimeout: TimeInterval) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = probeTimeout
        do {
            let (_, response) = try await session.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

extension MLXServerProcess {
    /// Handle to a running `mlx_lm.server` subprocess.
    final class Handle {
        let process: Process
        let logURL: URL
        init(process: Process, logURL: URL) {
            self.process = process
            self.logURL = logURL
        }
        var isRunning: Bool { process.isRunning }
    }

    struct LaunchOptions {
        var executable: URL          // .../mlx-venv/bin/mlx_lm.server
        var modelPath: URL           // absolute path to HF cache folder
        var host: String = "127.0.0.1"
        var port: Int = 8080
        var maxTokens: Int = 2048
        var promptCacheSize: Int = 32768
        var logURL: URL              // .../Library/Logs/Lumo/mlx-server.log
    }

    /// Starts `mlx_lm.server`. Returns the Handle immediately — use
    /// `waitForReady` on the HTTP endpoint to know when it's serving.
    /// Throws if the executable does not exist or the process fails to launch.
    static func start(_ opts: LaunchOptions) throws -> Handle {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: opts.executable.path) else {
            throw NSError(
                domain: "MLXServerProcess",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "mlx_lm.server executable not found at \(opts.executable.path)"]
            )
        }
        try fm.createDirectory(
            at: opts.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Truncate previous log.
        fm.createFile(atPath: opts.logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: opts.logURL)

        let proc = Process()
        proc.executableURL = opts.executable
        proc.arguments = [
            "--model", opts.modelPath.path,
            "--host", opts.host,
            "--port", String(opts.port),
            "--max-tokens", String(opts.maxTokens),
            "--prompt-cache-size", String(opts.promptCacheSize),
            "--chat-template-args", #"{"enable_thinking": false}"#,
        ]
        proc.standardOutput = logHandle
        proc.standardError = logHandle

        try proc.run()
        return Handle(process: proc, logURL: opts.logURL)
    }

    /// Graceful stop: SIGTERM, wait up to `graceSeconds`, then SIGKILL.
    /// Blocks the current thread — call off the main thread if grace > 0.
    static func stop(_ handle: Handle, graceSeconds: TimeInterval = 3) {
        guard handle.process.isRunning else { return }
        handle.process.terminate() // SIGTERM
        let deadline = Date().addingTimeInterval(graceSeconds)
        while handle.process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if handle.process.isRunning {
            kill(handle.process.processIdentifier, SIGKILL)
            handle.process.waitUntilExit()
        }
    }
}
