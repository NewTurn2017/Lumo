# MLX Server Lifecycle Management — Design Spec

**Date:** 2026-04-14  
**Status:** Approved

---

## Overview

Lumo currently assumes the user has an external MLX or Ollama server already running. This spec covers automatic MLX server lifecycle management: installing `mlx-lm` into an isolated venv, starting/stopping the server tied to the app lifecycle, and surfacing server status in Settings.

**Scope:** MLX backend only. Ollama remains unchanged (user-managed).

**Default model:** `mlx-community/gemma-4-e4b-it-4bit` — official Google Gemma-4 E4B, 4-bit MLX build (~3GB). Selected after benchmarking against SuperGemma4-26B-4bit: comparable quality for translation workloads with ~5× smaller memory footprint and slightly faster throughput (75 tok/s vs 65 tok/s on Apple Silicon).

**Thinking MUST be disabled.** Gemma-4's chat template defaults to `enable_thinking: true`, which generates long reasoning blocks before content and makes translation 5-10× slower (first-content latency jumps from ~200ms to ~3500ms). MLXServerManager MUST start `mlx_lm.server` with `--chat-template-args '{"enable_thinking": false}'`. This is non-negotiable — without it, the app is unusable for real-time translation.

---

## Architecture

### New File

```
Sources/Lumo/Server/MLXServerManager.swift
```

### Modified Files

- `Sources/Lumo/App/AppDelegate.swift` — connect server lifecycle to app start/quit
- `Sources/Lumo/UI/SettingsView.swift` — server status dot + toggle in General tab
- `Sources/Lumo/Core/Settings.swift` — add `mlxServerEnabled` key

### MLXServerManager

```swift
@MainActor
final class MLXServerManager: ObservableObject {
    enum Status {
        case stopped
        case installing   // pip install in progress
        case starting     // process launched, polling /v1/models
        case running
        case error(String)
    }

    @Published private(set) var status: Status = .stopped

    func enable()    // venv check → install → start server
    func disable()   // SIGTERM server process
    func shutdown()  // called from applicationWillTerminate, force-kills
}
```

`MLXServerManager` is instantiated in `AppDelegate` and passed to `SettingsView` via the environment.

---

## Data Flow

```
AppDelegate.applicationDidFinishLaunching
    └→ if settings.mlxServerEnabled && backend == "mlx" → manager.enable()

AppDelegate.applicationWillTerminate
    └→ manager.shutdown()

SettingsView (MLX section)
    └→ Toggle → manager.enable() / manager.disable()
    └→ StatusDot ← manager.$status (ObservableObject binding)
```

---

## Installation & Server Start Flow

**venv path:** `~/.local/share/Lumo/mlx-venv/`

```
enable() invoked
    │
    ├─ venv exists?
    │   NO  → status = .installing
    │         python3 -m venv ~/.local/share/Lumo/mlx-venv/
    │         pip install mlx-lm
    │         on failure → status = .error("mlx-lm 설치 실패")
    │
    ├─ model detection
    │   search ~/.cache/huggingface/hub/ for folder matching Settings.modelName
    │   NOT FOUND → status = .error("모델 없음")
    │               show GitHub guide button in SettingsView
    │   FOUND → continue
    │
    └─ start server
        status = .starting
        Process: ~/.local/share/Lumo/mlx-venv/bin/mlx_lm.server
                 --host 127.0.0.1
                 --port 8080
                 --model <detected path>
                 --chat-template-args '{"enable_thinking": false}'   ← REQUIRED
                 --prompt-cache-size 32768
                 --max-tokens 2048
        poll GET /v1/models every 2s, timeout 60s
        success → status = .running
        timeout → status = .error("서버 시작 시간 초과")
```

**disable() / shutdown():**
- Send SIGTERM to the server process
- `shutdown()` additionally waits up to 3s then SIGKILL if still alive

---

## Error Cases

| Condition | Status | UI |
|-----------|--------|----|
| Python 3 not found | `.error` | "Python 3이 필요합니다" |
| pip install fails | `.error` | "mlx-lm 설치 실패" |
| Model not in HF cache | `.error` | "모델 없음" + GitHub 버튼 |
| Server 60s no response | `.error` | "서버 시작 시간 초과" |

---

## Settings UI

MLX 백엔드 선택 시 General 탭에 서버 섹션 표시. Ollama 선택 시 숨김.

```
── MLX Server ────────────────────
  ● Running        [●────] Enabled
  Server URL: [http://localhost:8080]

  [→ 설치 가이드 열기]    ← 모델 없을 때만 표시
```

**Status dot colors:**

| Status | Color |
|--------|-------|
| `.running` | Green |
| `.starting` / `.installing` | Yellow (pulse animation) |
| `.stopped` | Gray |
| `.error` | Red |

**Settings.swift additions:**

```swift
// SettingsKey
static let mlxServerEnabled = "mlxServerEnabled"

// SettingsSnapshot
var mlxServerEnabled: Bool   // default: true
```

---

## Out of Scope

- Ollama server management (unchanged)
- Auto-download of model files (GitHub guide instead)
- launchd / LaunchAgent registration
- Multiple concurrent model instances
