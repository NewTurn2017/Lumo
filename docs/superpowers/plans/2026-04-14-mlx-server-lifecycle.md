# MLX Server Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Lumo first-class control of the MLX server: auto-install `mlx-lm` into an isolated venv, auto-start the server on app launch, shut it down on quit, and expose a status indicator + manual toggle in Settings.

**Architecture:** A new `MLXServerManager` (ObservableObject) owns the Python subprocess. Its public API is `enable() / disable() / shutdown()`; internal helpers split into `MLXPaths` (pure path logic) and `MLXServerProcess` (subprocess spawn + SIGTERM). AppDelegate wires lifecycle into `applicationDidFinishLaunching` / `applicationWillTerminate`. SettingsView adds an MLX-only section with a colored status dot and toggle.

**Tech Stack:** Swift 5.9 / SwiftUI / AppKit / Foundation `Process` / URLSession / XCTest / XcodeGen.

**Spec:** `docs/superpowers/specs/2026-04-14-mlx-server-lifecycle-design.md`

---

## File Structure

**New files (Sources/Lumo/Server/):**

| File | Responsibility |
|---|---|
| `MLXPaths.swift` | Pure path helpers: venv path, HuggingFace cache directory, model folder name encoding |
| `MLXServerProcess.swift` | Low-level `Process` management: spawn, SIGTERM/SIGKILL, readiness polling |
| `MLXServerManager.swift` | Public `@MainActor ObservableObject`, `Status` enum, orchestrates installer → detector → process, drives `@Published` status |

**Modified files:**

| File | Reason |
|---|---|
| `Sources/Lumo/Core/Settings.swift` | Add `mlxServerEnabled` key + field |
| `Sources/Lumo/App/AppDelegate.swift` | Instantiate `MLXServerManager`, call `enable()` on launch, `shutdown()` on terminate; pass manager down to Settings via `MenuBarController` |
| `Sources/Lumo/UI/SettingsView.swift` | Add MLX Server section (status dot + toggle + GitHub guide button) |
| `Sources/Lumo/UI/MenuBarController.swift` | Hold `MLXServerManager` reference so the Settings window picks it up via `.environmentObject` |
| `Tests/LumoTests/SettingsTests.swift` | Fix stale default assertions (URL/model already migrated to MLX) and add `mlxServerEnabled` assertion |

**New test files (Tests/LumoTests/):**

| File | What it tests |
|---|---|
| `MLXPathsTests.swift` | Pure path helpers — deterministic, no filesystem side effects outside tmp |
| `MLXServerProcessReadinessTests.swift` | Readiness polling via `StubURLProtocol` — success, retry, timeout |
| `MLXServerManagerStateTests.swift` | State-machine transitions using injected fakes |

---

## Shared Conventions

- **Venv path:** `~/.local/share/Lumo/mlx-venv` (expanded from `FileManager.default.homeDirectoryForCurrentUser`)
- **HuggingFace hub path:** `~/.cache/huggingface/hub`
- **Model folder encoding:** HF stores `mlx-community/gemma-4-e4b-it-4bit` as `models--mlx-community--gemma-4-e4b-it-4bit` (slash → `--`, prefix `models--`)
- **Default port:** `8080` (localhost-only)
- **GitHub install guide URL:** `https://github.com/newTurn2017/Lumo#mlx-setup` (placeholder — replace with real URL when docs section exists)

---

## Build/Test Commands

The project uses XcodeGen. Before touching code, run:

```bash
cd /Users/genie/dev/side/Lumo
xcodegen generate
```

Build + test:

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' build test | xcpretty
```

Single test:

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXPathsTests | xcpretty
```

Commit cadence: commit after each task that reaches a passing state.

---

## Task 1: Update Settings + Fix Stale Test

**Files:**
- Modify: `Sources/Lumo/Core/Settings.swift`
- Modify: `Tests/LumoTests/SettingsTests.swift`

The existing `SettingsTests.test_defaults_matchSpec` asserts the legacy Ollama defaults (`http://localhost:11434`, `gemma4:e4b`), which conflict with the uncommitted MLX migration. This task aligns the test with the new defaults and adds the new `mlxServerEnabled` field.

- [ ] **Step 1.1: Write the failing test**

Replace the body of `Tests/LumoTests/SettingsTests.swift` with:

```swift
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
    }

    func test_load_readsMlxServerEnabledOverride() {
        let suite = UserDefaults(suiteName: "SettingsTests.load")!
        suite.removePersistentDomain(forName: "SettingsTests.load")
        suite.set(false, forKey: SettingsKey.mlxServerEnabled)
        let s = SettingsSnapshot.load(from: suite)
        XCTAssertFalse(s.mlxServerEnabled)
    }
}
```

- [ ] **Step 1.2: Run test to verify it fails**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/SettingsTests | xcpretty
```

Expected: FAIL. Compilation error: `mlxServerEnabled` not defined on `SettingsSnapshot`; `SettingsKey.mlxServerEnabled` not defined.

- [ ] **Step 1.3: Add the key + field + load logic**

Edit `Sources/Lumo/Core/Settings.swift`:

In `enum SettingsKey`, add:

```swift
    static let mlxServerEnabled             = "lumo.mlxServerEnabled"
```

In `struct SettingsSnapshot`, add a new stored property (place after `hardTimeoutSec`):

```swift
    var mlxServerEnabled: Bool
```

Update `static let defaults = SettingsSnapshot(...)` to include `mlxServerEnabled: true` as the last argument.

In `static func load(from:)`, add after the `hardTimeoutSec` load block:

```swift
        if defaults.object(forKey: SettingsKey.mlxServerEnabled) != nil {
            s.mlxServerEnabled = defaults.bool(forKey: SettingsKey.mlxServerEnabled)
        }
```

- [ ] **Step 1.4: Run test to verify it passes**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/SettingsTests | xcpretty
```

Expected: PASS for both `test_defaults_matchSpec` and `test_load_readsMlxServerEnabledOverride`.

- [ ] **Step 1.5: Commit**

```bash
git add Sources/Lumo/Core/Settings.swift Tests/LumoTests/SettingsTests.swift
git commit -m "feat(settings): add mlxServerEnabled flag (default on)"
```

---

## Task 2: MLXPaths — Pure Path Helpers

**Files:**
- Create: `Sources/Lumo/Server/MLXPaths.swift`
- Create: `Tests/LumoTests/MLXPathsTests.swift`

This struct centralizes the three path computations used everywhere else: venv root, HuggingFace cache root, and the folder name HF uses for a given model ID. Keeping them here lets the rest of the module stay filesystem-agnostic and makes these the only unit under direct test.

- [ ] **Step 2.1: Write the failing test**

Create `Tests/LumoTests/MLXPathsTests.swift`:

```swift
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
```

- [ ] **Step 2.2: Run test to verify it fails**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXPathsTests | xcpretty
```

Expected: FAIL. `MLXPaths` type is undefined.

- [ ] **Step 2.3: Implement MLXPaths**

Create `Sources/Lumo/Server/MLXPaths.swift`:

```swift
import Foundation

/// Pure path helpers for the MLX server install + model cache layout.
/// No filesystem side effects. `home` defaults to the current user's home,
/// but is overridable for tests.
enum MLXPaths {
    static func venvRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("Lumo", isDirectory: true)
            .appendingPathComponent("mlx-venv", isDirectory: true)
    }

    static func serverExecutable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        venvRoot(home: home)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("mlx_lm.server")
    }

    static func pipExecutable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        venvRoot(home: home)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("pip")
    }

    static func hfHubRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    /// HF cache encodes `org/name` as `models--org--name`. Multiple slashes
    /// become additional `--` separators.
    static func hfFolderName(modelID: String) -> String {
        "models--" + modelID.split(separator: "/").joined(separator: "--")
    }
}
```

- [ ] **Step 2.4: Run test to verify it passes**

```bash
xcodegen generate && \
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXPathsTests | xcpretty
```

Expected: all six tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add Sources/Lumo/Server/MLXPaths.swift Tests/LumoTests/MLXPathsTests.swift project.yml
git commit -m "feat(server): add MLXPaths pure path helpers"
```

(If `project.yml` wasn't touched, omit it. XcodeGen picks up new files under `Sources/Lumo` automatically since the target uses `path: Sources/Lumo`, but you still need `xcodegen generate` before builds.)

---

## Task 3: Model Cache Detection

**Files:**
- Modify: `Sources/Lumo/Server/MLXPaths.swift`
- Modify: `Tests/LumoTests/MLXPathsTests.swift`

Adds a filesystem-reading function that returns the absolute path of a model's cache directory if present, or `nil` if missing. Uses a `FileManager` argument for test injection against a fake tmp tree.

- [ ] **Step 3.1: Write the failing test**

Append to `Tests/LumoTests/MLXPathsTests.swift`:

```swift
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
```

- [ ] **Step 3.2: Run test to verify it fails**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXPathsTests | xcpretty
```

Expected: FAIL. `detectModel` is undefined.

- [ ] **Step 3.3: Implement detectModel**

Append to `Sources/Lumo/Server/MLXPaths.swift` inside `enum MLXPaths`:

```swift
    /// Returns the absolute path of the HF cache directory for `modelID`
    /// if it exists on disk, otherwise nil.
    static func detectModel(
        modelID: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL? {
        let folder = hfHubRoot(home: home)
            .appendingPathComponent(hfFolderName(modelID: modelID), isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            return nil
        }
        return folder
    }
```

- [ ] **Step 3.4: Run test to verify it passes**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXPathsTests | xcpretty
```

Expected: all nine `MLXPathsTests` methods pass.

- [ ] **Step 3.5: Commit**

```bash
git add Sources/Lumo/Server/MLXPaths.swift Tests/LumoTests/MLXPathsTests.swift
git commit -m "feat(server): detect HF-cached model directories"
```

---

## Task 4: MLXServerProcess — Readiness Polling

**Files:**
- Create: `Sources/Lumo/Server/MLXServerProcess.swift`
- Create: `Tests/LumoTests/MLXServerProcessReadinessTests.swift`

Before we spawn a real Python process, we implement the *easier* half: the readiness probe. It takes a `URLSession` and a base URL, polls `GET /v1/models`, returns `true` on the first HTTP 200 or `false` on timeout. This half is 100% unit-testable via the existing `StubURLProtocol` (see `Tests/LumoTests/Support/StubURLProtocol.swift`).

- [ ] **Step 4.1: Write the failing test**

Create `Tests/LumoTests/MLXServerProcessReadinessTests.swift`:

```swift
import XCTest
@testable import Lumo

final class MLXServerProcessReadinessTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }
    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func stubbedSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    func test_waitForReady_returnsTrue_onFirst200() async {
        StubURLProtocol.stub(url: "http://127.0.0.1:8080/v1/models", status: 200, body: "{}")
        let ready = await MLXServerProcess.waitForReady(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            session: stubbedSession(),
            pollInterval: .milliseconds(10),
            timeout: .seconds(1)
        )
        XCTAssertTrue(ready)
    }

    func test_waitForReady_returnsFalse_onTimeout() async {
        StubURLProtocol.stub(url: "http://127.0.0.1:8080/v1/models", status: 503, body: "")
        let ready = await MLXServerProcess.waitForReady(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            session: stubbedSession(),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(100)
        )
        XCTAssertFalse(ready)
    }

    func test_waitForReady_retriesUntilSuccess() async {
        StubURLProtocol.stubSequence(
            url: "http://127.0.0.1:8080/v1/models",
            responses: [
                (status: 503, body: ""),
                (status: 503, body: ""),
                (status: 200, body: "{}"),
            ]
        )
        let ready = await MLXServerProcess.waitForReady(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            session: stubbedSession(),
            pollInterval: .milliseconds(10),
            timeout: .seconds(1)
        )
        XCTAssertTrue(ready)
    }
}
```

This test depends on `StubURLProtocol.stubSequence(url:responses:)` which may not yet exist. Step 4.2 adds it if missing.

- [ ] **Step 4.2: Add stubSequence to StubURLProtocol if missing**

First inspect `Tests/LumoTests/Support/StubURLProtocol.swift`. If it already has a `stubSequence` helper, skip this step. Otherwise, append:

```swift
extension StubURLProtocol {
    /// Stubs an ordered sequence of responses for the same URL. Each call consumes
    /// one entry; the last entry repeats for any additional requests.
    static func stubSequence(url: String, responses: [(status: Int, body: String)]) {
        let queue = responses
        var index = 0
        stubHandler(url: url) { _ in
            let r = queue[min(index, queue.count - 1)]
            index += 1
            let http = HTTPURLResponse(
                url: URL(string: url)!,
                statusCode: r.status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (http, Data(r.body.utf8))
        }
    }
}
```

Before writing, `Read` the existing file to confirm the base `stub(url:status:body:)` and any `stubHandler(url:_:)` helper so this compiles against the real API. If the existing helper has a different name, adjust the extension.

- [ ] **Step 4.3: Run test to verify it fails**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXServerProcessReadinessTests | xcpretty
```

Expected: FAIL. `MLXServerProcess` type undefined.

- [ ] **Step 4.4: Implement MLXServerProcess.waitForReady**

Create `Sources/Lumo/Server/MLXServerProcess.swift`:

```swift
import Foundation

/// Low-level subprocess + readiness-probe helpers for the MLX server.
/// Stateless — all functions take every dependency they need.
enum MLXServerProcess {
    /// Polls `GET <baseURL>/v1/models` until a 200 is returned or `timeout` elapses.
    /// Returns true on success, false on timeout or any non-200 every poll.
    static func waitForReady(
        baseURL: URL,
        session: URLSession = .shared,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(60)
    ) async -> Bool {
        let probe = baseURL.appendingPathComponent("v1").appendingPathComponent("models")
        let deadline = ContinuousClock.now + timeout
        var attempt = 0
        while ContinuousClock.now < deadline {
            attempt += 1
            if await probeOnce(url: probe, session: session) {
                return true
            }
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero { break }
            try? await Task.sleep(for: min(pollInterval, remaining))
        }
        return false
    }

    private static func probeOnce(url: URL, session: URLSession) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        do {
            let (_, response) = try await session.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 4.5: Run test to verify it passes**

```bash
xcodegen generate && \
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXServerProcessReadinessTests | xcpretty
```

Expected: all three readiness tests pass.

- [ ] **Step 4.6: Commit**

```bash
git add Sources/Lumo/Server/MLXServerProcess.swift \
        Tests/LumoTests/MLXServerProcessReadinessTests.swift \
        Tests/LumoTests/Support/StubURLProtocol.swift
git commit -m "feat(server): add MLXServerProcess readiness polling"
```

---

## Task 5: MLXServerProcess — Spawn + Stop

**Files:**
- Modify: `Sources/Lumo/Server/MLXServerProcess.swift`

Adds the actual subprocess spawn for `mlx_lm.server` and a graceful stop (SIGTERM → 3s grace → SIGKILL). This part interacts with real processes so unit-testing is impractical; we rely on manual verification in Task 9. The function signatures are narrow enough that integration risk is contained.

- [ ] **Step 5.1: Add Spawn type and start/stop helpers**

Append to `Sources/Lumo/Server/MLXServerProcess.swift`:

```swift
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
```

- [ ] **Step 5.2: Compile-check**

```bash
xcodegen generate && \
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' build | xcpretty
```

Expected: BUILD SUCCEEDED. No tests run in this step — start/stop is exercised later in Task 9.

- [ ] **Step 5.3: Commit**

```bash
git add Sources/Lumo/Server/MLXServerProcess.swift
git commit -m "feat(server): spawn/stop mlx_lm.server subprocess"
```

---

## Task 6: MLXServerManager — Public API + State Machine

**Files:**
- Create: `Sources/Lumo/Server/MLXServerManager.swift`
- Create: `Tests/LumoTests/MLXServerManagerStateTests.swift`

The public entrypoint. Holds `@Published var status`, exposes `enable() / disable() / shutdown()`. Delegates installation, model detection, spawn, and readiness to the previous pieces. Tests cover the *state machine* by injecting three fakes (installer, detector, runner) so we can assert transitions without touching the filesystem.

- [ ] **Step 6.1: Write the failing test**

Create `Tests/LumoTests/MLXServerManagerStateTests.swift`:

```swift
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

private final class FakeInstaller: MLXInstalling {
    enum Outcome { case success; case failure(String) }
    let outcome: Outcome
    var didInstall = false
    init(outcome: Outcome) { self.outcome = outcome }
    func installIfNeeded() throws {
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

private final class FakeRunner: MLXRunning {
    let readiness: Bool
    var didStart = false
    var didStop = false
    init(readiness: Bool) { self.readiness = readiness }
    func start(modelPath: URL) throws {
        didStart = true
    }
    func waitForReady() async -> Bool { readiness }
    func stop() { didStop = true }
}
```

- [ ] **Step 6.2: Run test to verify it fails**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXServerManagerStateTests | xcpretty
```

Expected: FAIL. Types `MLXServerManager`, `MLXInstalling`, `MLXDetecting`, `MLXRunning` are undefined.

- [ ] **Step 6.3: Implement MLXServerManager**

Create `Sources/Lumo/Server/MLXServerManager.swift`:

```swift
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
```

- [ ] **Step 6.4: Run test to verify it passes**

```bash
xcodegen generate && \
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test \
  -only-testing:LumoTests/MLXServerManagerStateTests | xcpretty
```

Expected: all five state-machine tests pass.

- [ ] **Step 6.5: Commit**

```bash
git add Sources/Lumo/Server/MLXServerManager.swift \
        Tests/LumoTests/MLXServerManagerStateTests.swift
git commit -m "feat(server): MLXServerManager state machine"
```

---

## Task 7: Real Installer + Runner Adapters

**Files:**
- Modify: `Sources/Lumo/Server/MLXServerManager.swift` (add real adapters)

Connect the protocol-based manager to real implementations:

- `SystemMLXInstaller` — creates venv via `python3 -m venv` and installs `mlx-lm` via pip. Uses a helper to run `Process` synchronously and capture stderr.
- `FileSystemMLXDetector` — thin wrapper over `MLXPaths.detectModel`.
- `SubprocessMLXRunner` — wraps `MLXServerProcess.start/waitForReady/stop` and owns the `Handle` lifetime.

Also adds a convenience `MLXServerManager.live()` factory that composes the real adapters. No unit tests for the real adapters (they shell out and hit the filesystem); manual verification in Task 9.

- [ ] **Step 7.1: Add adapters**

Append to `Sources/Lumo/Server/MLXServerManager.swift`:

```swift
// MARK: - Real adapters

enum ShellRunner {
    /// Runs a command to completion and returns (exitCode, stderr). stdout is
    /// captured but discarded. Used by the installer for one-shot commands.
    static func run(_ executable: URL, _ args: [String]) throws -> (Int32, String) {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = args
        let errPipe = Pipe()
        let outPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = outPipe
        try proc.run()
        proc.waitUntilExit()
        let err = String(
            data: errPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (proc.terminationStatus, err)
    }
}

struct SystemMLXInstaller: MLXInstalling {
    let home: URL
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func installIfNeeded() throws {
        let venv = MLXPaths.venvRoot(home: home)
        let fm = FileManager.default

        if fm.fileExists(atPath: MLXPaths.serverExecutable(home: home).path) {
            return
        }

        // Ensure parent exists
        try fm.createDirectory(
            at: venv.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 1) python3 -m venv <venv>
        guard let python3 = Self.findPython3() else {
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

        // 2) pip install mlx-lm
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
        // Probe common locations; the app is unsandboxed so these are reachable.
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

    func start(modelPath: URL) throws {
        // If a previous handle is still alive (rare: manual toggle spam), stop it.
        stop()
        let opts = MLXServerProcess.LaunchOptions(
            executable: MLXPaths.serverExecutable(home: home),
            modelPath: modelPath,
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
```

- [ ] **Step 7.2: Compile-check**

```bash
xcodegen generate && \
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' build | xcpretty
```

Expected: BUILD SUCCEEDED. Existing state-machine tests still pass — they use the fakes.

- [ ] **Step 7.3: Commit**

```bash
git add Sources/Lumo/Server/MLXServerManager.swift
git commit -m "feat(server): real installer/detector/runner adapters"
```

---

## Task 8: Wire into AppDelegate + SettingsView

**Files:**
- Modify: `Sources/Lumo/App/AppDelegate.swift`
- Modify: `Sources/Lumo/UI/SettingsView.swift`
- Modify: `Sources/Lumo/UI/MenuBarController.swift`

Connects the manager to the app lifecycle and presents it in Settings. The server starts automatically on launch when `backendType == "mlx"` and `mlxServerEnabled`, and stops on `applicationWillTerminate`.

- [ ] **Step 8.1: Add manager property + lifecycle hooks to AppDelegate**

Edit `Sources/Lumo/App/AppDelegate.swift`:

At the top of the `AppDelegate` class body (alongside `private var menu: ...`), add:

```swift
    private var mlxServerManager: MLXServerManager!
```

In `applicationDidFinishLaunching(_:)`, immediately after `let settings = SettingsSnapshot.load()`, insert:

```swift
        mlxServerManager = MLXServerManager.live(modelID: settings.model)
        if settings.backendType == "mlx" && settings.mlxServerEnabled {
            Task { await mlxServerManager.enable() }
        }
```

At the bottom of the class (before the closing `}`), add:

```swift
    func applicationWillTerminate(_ notification: Notification) {
        mlxServerManager?.shutdown()
    }
```

Then pass `mlxServerManager` into `MenuBarController.init` — see Step 8.2 for the signature.

Update the MenuBarController instantiation line:

```swift
        menu = MenuBarController(mlxServerManager: mlxServerManager)
```

- [ ] **Step 8.2: Thread manager through MenuBarController to SettingsView**

Open `Sources/Lumo/UI/MenuBarController.swift`. Add a stored property and init argument:

```swift
    private let mlxServerManager: MLXServerManager

    init(mlxServerManager: MLXServerManager) {
        self.mlxServerManager = mlxServerManager
        // ...existing init body...
    }
```

(If the class currently has no explicit init, convert the implicit one into an explicit `init(mlxServerManager:)` that sets up the status item the way the existing code does.)

Wherever `SettingsView()` is instantiated inside `MenuBarController` (likely in a "Settings…" menu action that opens a `NSHostingController`/`NSWindow`), wrap it:

```swift
        let hosting = NSHostingController(
            rootView: SettingsView()
                .environmentObject(mlxServerManager)
        )
```

If the existing pattern already uses a hosting controller, only the `.environmentObject` call is new.

- [ ] **Step 8.3: Add MLX Server section to SettingsView**

Edit `Sources/Lumo/UI/SettingsView.swift`.

Add the environment object property near the top of the struct:

```swift
    @EnvironmentObject private var mlxServerManager: MLXServerManager
```

Inside the first `Form { ... }` (the General tab), after the existing hotkey recorder, add:

```swift
                if backendType == "mlx" {
                    Divider()
                    MLXServerSection()
                }
```

At the bottom of the file, add a new private view:

```swift
private struct MLXServerSection: View {
    @EnvironmentObject private var manager: MLXServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                Text(statusLabel)
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isUserEnabled },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: SettingsKey.mlxServerEnabled)
                        if newValue {
                            Task { await manager.enable() }
                        } else {
                            manager.disable()
                        }
                    }
                ))
                .labelsHidden()
            }
            if case .error(let msg) = manager.status {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if msg.contains("모델") {
                    Button("설치 가이드 열기") {
                        NSWorkspace.shared.open(
                            URL(string: "https://github.com/newTurn2017/Lumo#mlx-setup")!
                        )
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var isUserEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.mlxServerEnabled) as? Bool ?? true
    }

    private var statusLabel: String {
        switch manager.status {
        case .stopped: return "Stopped"
        case .installing: return "Installing…"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .error: return "Error"
        }
    }

    private var dotColor: Color {
        switch manager.status {
        case .running: return .green
        case .starting, .installing: return .yellow
        case .stopped: return .gray
        case .error: return .red
        }
    }
}
```

Add `import AppKit` at the top of the file if not already present (needed for `NSWorkspace`).

- [ ] **Step 8.4: Build**

```bash
xcodegen generate && \
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' build | xcpretty
```

Expected: BUILD SUCCEEDED. If there are compile errors in `MenuBarController` because of a missing init, update call sites accordingly before continuing.

- [ ] **Step 8.5: Run full test suite**

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo \
  -destination 'platform=macOS' test | xcpretty
```

Expected: all existing tests + the new `MLXPathsTests`, `MLXServerProcessReadinessTests`, `MLXServerManagerStateTests`, `SettingsTests` pass.

- [ ] **Step 8.6: Commit**

```bash
git add Sources/Lumo/App/AppDelegate.swift \
        Sources/Lumo/UI/SettingsView.swift \
        Sources/Lumo/UI/MenuBarController.swift
git commit -m "feat(server): wire MLXServerManager into app lifecycle + Settings"
```

---

## Task 9: End-to-End Smoke Test

**Files:** none (manual verification)

Run the real app and verify the five key behaviors. For each, note the result in the checklist. If anything fails, stop and file a diagnosis note before proceeding to cleanup.

**Preparation:** make sure nothing else is holding port 8080.

```bash
lsof -iTCP:8080 -sTCP:LISTEN
```

If anything is listening, kill it first or skip that test.

- [ ] **Step 9.1: Fresh install path**

1. Delete any existing venv: `rm -rf ~/.local/share/Lumo/mlx-venv`
2. Build and launch Lumo: `xcodegen generate && xcodebuild -project Lumo.xcodeproj -scheme Lumo build && open build/Build/Products/Debug/Lumo.app` (adjust path if derived-data redirects it).
3. Open Settings → General. Observe: status dot should go **yellow "Installing…"** for ~1–2 min, then **yellow "Starting…"**, then **green "Running"**.
4. Tail the log: `tail -f ~/Library/Logs/Lumo/mlx-server.log` — should show `mlx-lm` loading the model.
5. Verify: `curl -sf http://127.0.0.1:8080/v1/models` returns 200 with the model list.

- [ ] **Step 9.2: Existing install path (cold launch)**

1. Quit Lumo (⌘Q).
2. Confirm port 8080 is free: `lsof -iTCP:8080 -sTCP:LISTEN` → empty.
3. Launch Lumo again.
4. Observe: skip `.installing` entirely. Goes **yellow "Starting…"** → **green "Running"** within ~10 s (cached model load).

- [ ] **Step 9.3: Manual toggle**

1. Open Settings. Turn the MLX Server toggle **off**.
2. Observe: dot turns gray, status "Stopped". `lsof -iTCP:8080` returns empty.
3. Turn the toggle **on** again.
4. Observe: goes back through `.starting` → `.running`.

- [ ] **Step 9.4: Model missing**

1. Quit Lumo.
2. Temporarily move the model folder:
   ```bash
   mv ~/.cache/huggingface/hub/models--mlx-community--gemma-4-e4b-it-4bit{,.bak}
   ```
3. Launch Lumo, open Settings.
4. Observe: dot red, message "모델 없음 …", **설치 가이드 열기** button visible. Clicking it opens the GitHub URL.
5. Restore:
   ```bash
   mv ~/.cache/huggingface/hub/models--mlx-community--gemma-4-e4b-it-4bit{.bak,}
   ```

- [ ] **Step 9.5: Clean shutdown**

1. While status is "Running", quit Lumo (⌘Q).
2. Observe: port 8080 releases within ~3 s.
3. `ps aux | grep mlx_lm.server | grep -v grep` → empty (no orphan subprocess).

- [ ] **Step 9.6: Translation still works**

1. Launch Lumo, wait for running.
2. Trigger a translation via the hotkey against any text on screen.
3. Observe: popup shows translated output, latency is sub-second per response chunk.

- [ ] **Step 9.7: Final commit (if any minor fixes surfaced)**

Only needed if Step 9.x uncovered a bug that required a code change. Otherwise skip.

```bash
git add -u
git commit -m "fix(server): <specific issue>"
```

---

## Self-Review Checklist

- [x] **Spec coverage**
  - Architecture section → Tasks 2–7
  - `MLXServerManager` class shape → Task 6
  - Data flow (app lifecycle → manager) → Task 8
  - Installation & server start flow → Tasks 2, 3, 5, 7
  - Error cases (Python missing / install fail / model missing / timeout) → Task 6 state tests + Task 7 installer + Task 8 UI message
  - Settings UI (status dot + toggle + GitHub link) → Task 8
  - `Settings.mlxServerEnabled` addition → Task 1
  - Thinking OFF requirement → baked into `LaunchOptions` in Task 5

- [x] **No placeholders** — every code block is complete. The only string intentionally kept generic is the GitHub URL (clearly noted as "placeholder — replace with real URL"); replace before shipping.

- [x] **Type consistency** — `MLXInstalling`, `MLXDetecting`, `MLXRunning` protocols are defined in Task 6 and used (via fakes) in the same task; `SystemMLXInstaller`, `FileSystemMLXDetector`, `SubprocessMLXRunner` in Task 7 conform to them. `MLXServerProcess.Handle`, `LaunchOptions`, `waitForReady`, `start`, `stop` signatures match between Task 4/5 (definition) and Task 7 (consumption).

- [x] **File boundaries** — Three small files in `Sources/Lumo/Server/` (`MLXPaths.swift`, `MLXServerProcess.swift`, `MLXServerManager.swift`) each with a single responsibility. No file exceeds ~250 lines after all tasks.

- [x] **TDD cadence** — Tasks 1, 2, 3, 4, 6 follow strict red-green-commit. Task 5 and 7 are subprocess-heavy and relied on via integration in Task 9; this tradeoff is explicit.
