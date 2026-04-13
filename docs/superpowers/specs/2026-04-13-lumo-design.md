# Lumo — Design Document

**Date:** 2026-04-13
**Status:** Draft (awaiting user review)
**Target platform:** macOS 13+ (Apple Silicon recommended)

## 1. Overview

**Lumo** is a macOS menu-bar utility that captures any region of the screen (or selected text) and instantly translates it to Korean using a local Ollama server running `gemma4:e4b`. Results are streamed into a floating popup and copied to the clipboard automatically.

### Goals

1. **One-shot translation** — from keystroke to clipboard, no intermediate UI.
2. **Interpreter-quality output** — natural Korean reflecting intent and nuance, not literal word-for-word.
3. **Fast** — sub-second first token in the warm path; sub-3s total for short text.
4. **Optimized** — minimal payload, pipelined execution, warm model, no idle cost beyond what the user opts into.
5. **Offline-capable** — all inference runs locally through Ollama.

### Non-goals

- Cloud-based translation providers (no OpenAI / DeepL integration in v1).
- Text-to-speech, OCR-only mode, or document translation.
- Multi-target language UI — target is fixed (Korean, with an automatic flip to English when the source is already Korean).
- Managing the Ollama daemon itself (install, update, pull). User is responsible for keeping Ollama running with `gemma4:e4b` pulled.

## 2. User-facing behavior

### Trigger A — Region capture (`⌘⇧1`)

1. User presses `⌘⇧1`.
2. Screen dims with a full-screen overlay; crosshair cursor.
3. User drags a rectangle. `ESC` cancels.
4. Overlay dismisses immediately; a floating popup appears at the bottom-right with a loading spinner.
5. The captured region is sent to Ollama; the Korean translation streams into the popup token-by-token.
6. When the stream completes:
   - Final text is copied to the system clipboard.
   - Popup shows a check icon and "클립보드에 복사됨".
   - Popup fades out after 5 seconds unless the user hovers it.
7. The translation is added to an in-app History (last 10 entries).

Target language is **always Korean** for this path.

### Trigger B — Double `⌘C` (selected-text translation)

1. User selects text in any app and presses `⌘C` twice within **300 ms** (default; configurable 200/300/500).
2. The first `⌘C` performs a normal system copy; Lumo does not interfere.
3. On the second `⌘C`, Lumo reads the clipboard string.
4. Lumo runs a language heuristic: if **≥50% of characters fall in the Hangul Unicode blocks**, the source is considered Korean and the target flips to **English**. Otherwise the target is Korean.
5. The same streaming popup is shown; the translated text overwrites the clipboard on completion.
6. The popup offers a **"원문 복원"** button which restores the original clipboard contents.

If the clipboard is empty, not a string, or the string is only whitespace, Lumo shows a transient warning and does nothing.

If the clipboard `changeCount` did not increase between the two keystrokes, Lumo ignores the double-tap (the user did not actually copy anything new).

### Menu bar

A single `NSStatusItem` reflects app-wide state:

| State | Icon |
|---|---|
| Idle | monochrome lamp icon |
| Busy (capture or translation in flight) | animated spinner |
| Warning (Ollama unreachable, model missing, permission missing) | lamp with ⚠ badge |
| Error (last operation failed) | lamp with ✕ badge, cleared on next success |

Menu contents:
- **Capture & Translate** (`⌘⇧1`)
- **Recent** (submenu of last 10 translations; click to re-copy)
- **Settings…**
- **Quit**

### Settings

A SwiftUI settings window accessible from the menu:

- **Ollama URL** (default `http://localhost:11434`)
- **Model** (default `gemma4:e4b`)
- **Keep-alive duration** (default 30m; options: 5m, 30m, 1h, indefinite)
- **Max image long edge in px** (default 1280; options 960/1280/1920)
- **Generation temperature** (default 0.2)
- **Capture hotkey** (default `⌘⇧1`, rebindable)
- **Enable double `⌘C`** (default on)
- **Double-tap threshold** (200 / 300 / 500 ms)
- **Overwrite clipboard with translation on double `⌘C`** (default on)
- **Launch at login** (default off; uses `SMAppService.mainApp`)
- **Debug**:
  - Recent 10-call latency breakdown (`capture_ms`, `encode_ms`, `first_token_ms`, `total_ms`)
  - First-token timeout (default 20 s)
  - Idle timeout (default 8 s)
  - Hard timeout (default 120 s)

## 3. Architecture

### Process model

Single-process SwiftUI + AppKit app with `LSUIElement=true` (menu-bar only, no Dock icon). Ollama runs as an external user-managed daemon; Lumo is an HTTP client to `localhost:11434`.

### High-level flow

```
             ┌───────────────┐                ┌───────────────┐
 ⌘⇧1 ──────▶ │ HotkeyManager │                │ DoubleCopy    │ ◀─── ⌘C ⌘C
             └───────┬───────┘                │ Monitor       │
                     │                        └───────┬───────┘
                     ▼                                ▼
             ┌────────────────────────────────────────────────┐
             │           TranslationOrchestrator              │
             └─────┬──────────────────────────┬───────────────┘
                   │                          │
           TranslationSource.image     TranslationSource.text
                   │                          │
                   ▼                          │
           ┌────────────────┐                 │
           │ CaptureService │                 │
           │  + Region UI   │                 │
           └───────┬────────┘                 │
                   │                          │
                   └────────────┬─────────────┘
                                ▼
                       ┌──────────────────┐
                       │ OllamaTranslator │
                       │  (stream=true)   │
                       └────────┬─────────┘
                                │ AsyncThrowingStream<String>
                                ▼
                       ┌──────────────────┐
                       │  StreamParser    │  filter thinking/noise
                       └────────┬─────────┘
                                │
                  ┌─────────────┴─────────────┐
                  ▼                           ▼
          ┌───────────────┐           ┌───────────────┐
          │ PopupWindow   │           │ Clipboard     │
          │ (streaming)   │           │ Service       │
          └───────────────┘           └───────────────┘
                                             │
                                             ▼
                                       ┌───────────┐
                                       │ History   │
                                       └───────────┘
```

### Module layout

```
Lumo/
├── App/
│   ├── LumoApp.swift              // @main, LSUIElement entry
│   └── AppDelegate.swift          // lifecycle, permission checks, warm-up
│
├── Menu/
│   ├── MenuBarController.swift    // NSStatusItem, state → icon mapping
│   └── MenuBuilder.swift
│
├── Hotkey/
│   ├── HotkeyManager.swift        // ⌘⇧1 registration (KeyboardShortcuts pkg)
│   └── DoubleCopyMonitor.swift    // CGEventTap, 300ms double-tap detector
│
├── Capture/
│   ├── CaptureService.swift       // protocol + default impl
│   ├── RegionSelector.swift       // full-screen overlay NSWindow
│   └── ScreenPermission.swift     // CGPreflightScreenCaptureAccess
│
├── Translation/
│   ├── Translator.swift           // protocol
│   ├── OllamaTranslator.swift     // URLSession streaming
│   ├── StreamParser.swift         // NDJSON parser + thinking filter
│   ├── PromptBuilder.swift        // system + user prompts
│   └── LanguageDetector.swift     // Hangul ratio heuristic
│
├── UI/
│   ├── PopupWindow.swift          // borderless NSPanel bottom-right
│   ├── PopupView.swift            // streaming text, toggle original, copy, restore
│   └── SettingsView.swift
│
├── Clipboard/
│   └── ClipboardService.swift     // NSPasteboard wrapper, changeCount tracking
│
├── History/
│   └── HistoryStore.swift         // last 10 entries, JSON in UserDefaults
│
└── Core/
    ├── Settings.swift             // @AppStorage models
    ├── Logger.swift               // os.Logger wrapper with latency metrics
    └── TranslationOrchestrator.swift
```

### Key protocols

```swift
protocol Translator {
    func translate(source: TranslationSource, target: TargetLanguage)
        -> AsyncThrowingStream<String, Error>
}

enum TranslationSource {
    case image(CGImage)
    case text(String)
}

enum TargetLanguage { case korean, english }

protocol CaptureService {
    func captureRegion() async throws -> CGImage
}

protocol Clipboard {
    var changeCount: Int { get }
    func string() -> String?
    func setString(_ s: String)
}
```

All three protocols enable mock-based unit tests of `TranslationOrchestrator` and the UI layer without touching real hardware or network.

## 4. Data flow

### 4.1 Capture path (`⌘⇧1`)

1. `HotkeyManager` fires `orchestrator.runCapture()`.
2. `ScreenPermission.check()` — if denied, show alert with deep link to `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture` and abort.
3. `RegionSelector` presents a full-screen overlay. `ESC` → throws `CancellationError`. On drag completion → returns `CGRect`.
4. `CaptureService` grabs that rectangle via ScreenCaptureKit → `CGImage`.
5. Image is downscaled so the long edge ≤ user-configured max (default 1280 px) and encoded as JPEG quality 0.85 → `Data`.
6. Base64 encode → embedded in Ollama request.
7. `PopupWindow.show(state: .loading)` **before** awaiting the HTTP response — user sees UI within ~150 ms of the drag ending.
8. `OllamaTranslator.translate(source: .image(img), target: .korean)` returns an `AsyncThrowingStream<String, Error>`.
9. Orchestrator iterates the stream:
   - Each token is appended to both `PopupView` (live render) and a buffer (final result).
10. On stream completion:
    - `Clipboard.setString(buffer)`
    - `HistoryStore.append(HistoryEntry(timestamp, preview, full, source: .image))`
    - `PopupWindow.state = .done`
    - After 5 s (no hover) → fade out.

### 4.2 Double-copy path

1. `DoubleCopyMonitor` is a `CGEventTap` installed at `cgAnnotatedSessionEventTap` in **listenOnly** mode so it never consumes events.
2. For each key-down event with `keyCode == kVK_ANSI_C (8)` and `.maskCommand`, it records the timestamp.
3. If two such events arrive within the configured threshold **and** `pasteboard.changeCount` strictly increased between them:
   - Wait 20 ms (lets the source app finish writing to the pasteboard)
   - Read `pasteboard.string()`
   - If empty/nil → transient warning popup
   - Otherwise call `orchestrator.runText(selected)`
4. `orchestrator.runText`:
   - Saves the original clipboard string as `previousClipboard`
   - Runs `LanguageDetector.isKorean(text)` → picks `.english` or `.korean`
   - Opens the popup
   - Streams via `OllamaTranslator.translate(source: .text(selected), target: ...)`
   - On completion, overwrites clipboard with the translation if the user enabled that option
   - Popup exposes a **"원문 복원"** button that calls `Clipboard.setString(previousClipboard)`

### 4.3 Ollama request shape

```
POST http://localhost:11434/api/chat
Content-Type: application/json

{
  "model": "gemma4:e4b",
  "stream": true,
  "keep_alive": "30m",
  "options": { "temperature": 0.2 },
  "messages": [
    { "role": "system", "content": "<interpreter prompt, see §5>" },
    {
      "role": "user",
      "content": "이 이미지 속 텍스트를 한국어로 통역",
      "images": ["<base64 jpeg>"]
    }
  ]
}
```

The text path is identical except the user message carries the raw text and no `images` field:

```json
{ "role": "user", "content": "다음 텍스트를 한국어로 통역:\n\n<selected>" }
```

### 4.4 Stream parsing

Ollama streams NDJSON — one JSON object per line, each with a `message.content` delta. `StreamParser` buffers partial lines, parses each, and emits the content chunk. It additionally filters out thinking noise:

- `<think>...</think>` blocks (and partial opens across chunks)
- Leading/trailing whitespace-only chunks
- Lines where `done: true` — used to signal end of stream

If after filtering the total accumulated text is empty, the orchestrator treats this as an error and shows "(텍스트 없음)" without touching the clipboard.

## 5. Prompting

Single shared system prompt for both trigger paths:

```
당신은 숙련된 통역사다. 입력을 자연스러운 한국어로 의역하라.

원칙:
- 직역 금지. 원문의 의도와 뉘앙스를 한국어 독자가 자연스럽게 읽을 수 있게 전달.
- 문장 흐름, 존댓말/반말 톤, 맥락에 맞는 관용 표현 우선.
- 기술 용어/고유명사는 필요하면 원어를 괄호로 병기 (예: "추론(reasoning)").
- UI 문자열(버튼, 메뉴)은 한국어 UI 관례에 맞춘다 (예: "Save" → "저장").
- 의미가 불명확하면 가장 그럴듯한 해석으로 번역한다. 추측 표시 금지.

출력 규칙 (엄격):
- 번역문만 출력. 그 외 일체 금지.
- 설명, 목록, 헤더, 마크다운, 원문, 추론 과정 금지.
- 원문의 줄바꿈이 의미 있으면 유지, 단순 줄바꿈이면 합친다.
- 읽을 수 있는 텍스트가 없으면 정확히 출력: (텍스트 없음)
```

When the detected source is Korean and the target flips to English (double-copy path only), the orchestrator swaps `한국어` → `English` in the prompt and the user message becomes `Translate the following text into natural English:\n\n<text>`.

## 6. Error handling

| Failure | Detection | User-facing response |
|---|---|---|
| Screen Recording permission missing | `CGPreflightScreenCaptureAccess()` | Alert + system settings deep link; capture path disabled until granted |
| Accessibility permission missing (for double-copy) | `AXIsProcessTrustedWithOptions` | Alert; double-copy disabled, capture path unaffected |
| Region selection cancelled (`ESC`) | `CancellationError` in `RegionSelector` | Silent; menu-bar state returns to idle |
| Ollama server unreachable | `URLError(.cannotConnectToHost)` / connection refused | Popup error: "Ollama 서버에 연결할 수 없음. `ollama serve` 실행 중인지 확인" + "설정 열기" button |
| Model not present | HTTP 404 with `model not found` | Popup error with copyable command `ollama pull gemma4:e4b` |
| Stream idle timeout (no new token for N s) | Per-chunk timer, see §7.1 | Popup error with "재시도" button; cancel the URLSession task, set menu-bar to error state |
| Stream hard timeout (total elapsed > M s) | Total-elapsed timer, see §7.1 | Same as idle timeout; logged separately for diagnosis |
| Stream ends with empty buffer | Buffer check after stream completion | "(텍스트 없음)" in popup; clipboard untouched |
| Clipboard not text on double-copy | `pasteboard.string() == nil` | Transient warning toast; no API call |
| Clipboard unchanged on double-copy | `changeCount` did not increase | Silent; treated as false positive |

All errors are logged via `os.Logger` with a category per module so Console.app can filter by `subsystem: "app.lumo"`.

## 7. Performance plan

### 7.1 Stream idle timeout

A local Ollama stream can stall for two distinct reasons, and we treat them separately:

1. **Cold start / first-token delay.** A model that has not been used for a while may need to be loaded into memory (or VRAM). This is handled by the warm-up request in §7.2; when it fails we tolerate a longer wait for the *first* token.
2. **Mid-stream stall.** Once tokens start arriving, a gap of more than a few seconds almost always means the connection has died silently or the model has gone into a pathological state. Waiting indefinitely is worse than failing fast.

Two independent timers run for every translation request:

| Timer | Purpose | Default | Reset on |
|---|---|---|---|
| **First-token timeout** | Caps the cold path — abort if no token has arrived within this window after the request is dispatched | 20 s | (one-shot; does not reset) |
| **Idle timeout** | Caps mid-stream stalls — abort if the gap between two consecutive tokens exceeds this window | 8 s | each received token |
| **Hard timeout** | Safety net for runaway generation | 120 s | (total elapsed; does not reset) |

Implementation sketch:

```swift
func translateWithTimeouts(_ stream: AsyncThrowingStream<String, Error>)
    -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var sawFirstToken = false
            let start = ContinuousClock.now
            var lastTokenAt = start

            let watchdog = Task {
                while !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(250))
                    let now = ContinuousClock.now
                    if !sawFirstToken, now - start > .seconds(20) {
                        continuation.finish(throwing: TranslationError.firstTokenTimeout)
                        return
                    }
                    if sawFirstToken, now - lastTokenAt > .seconds(8) {
                        continuation.finish(throwing: TranslationError.idleTimeout)
                        return
                    }
                    if now - start > .seconds(120) {
                        continuation.finish(throwing: TranslationError.hardTimeout)
                        return
                    }
                }
            }

            do {
                for try await chunk in stream {
                    sawFirstToken = true
                    lastTokenAt = ContinuousClock.now
                    continuation.yield(chunk)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            watchdog.cancel()
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

When any of the three timers fires:

1. The underlying `URLSession` task is cancelled (releases the socket, lets Ollama know to stop generating).
2. The orchestrator marks the menu-bar state as `error` and updates the popup with the specific error variant so the user knows whether the model never started (first-token), stalled mid-stream (idle), or ran too long (hard).
3. No partial result is written to the clipboard, but whatever text was already buffered stays visible in the popup with a "(중단됨)" suffix and a "재시도" button.

All three timeouts are configurable in Settings under the Debug tab, with the defaults above. The idle timeout is the most likely one the user will tune — tight enough to surface real stalls quickly, loose enough not to false-positive on the slower `e4b` model during long paragraphs.

### Concurrency rule

At most **one translation is in flight at any time**. If a second trigger arrives (either `⌘⇧1` or a double-`⌘C`) while an earlier translation is still streaming, the orchestrator:

1. Cancels the in-flight task (cancels the `URLSession` stream; any text already buffered stays in the popup with a "(중단됨)" suffix).
2. Closes the current popup immediately.
3. Starts the new translation from scratch.

This matches the user's probable intent ("I want *this* now, forget the last one") and avoids a queue that could accumulate state and confuse the menu-bar status icon.

### 7.2 Warm-up (biggest single win)

On app launch, after permissions are verified, the orchestrator fires a background "warm" request:

```json
POST /api/chat
{ "model": "gemma4:e4b", "messages": [], "keep_alive": "30m" }
```

This forces Ollama to load the model into memory (or VRAM) so the first user-initiated translation hits a warm model. `keep_alive` is then echoed on every subsequent request to prevent unload.

If the warm-up request fails (server not running, model not pulled, network error), the failure is **non-fatal**: the menu-bar icon moves to the warning state with a tooltip explaining the cause, but all features remain enabled. The next user-initiated translation will attempt the real request and surface a richer error (with the copy-to-clipboard `ollama pull` command when appropriate). A background retry runs every 30 seconds while the app is in the warning state so that starting Ollama after launch transparently clears the warning.

### 7.3 Image path optimizations

- Downscale captured region so the long edge is ≤ 1280 px (configurable). Text OCR is unaffected; payload and model inference time both drop linearly.
- Encode as JPEG quality 0.85 rather than PNG (3–5× smaller on typical screen content).
- `async let` for encoding + HTTP request preparation so the two run in parallel where possible.

### 7.4 Pipelining

- Popup is shown in `.loading` state **before** awaiting the first token.
- Tokens are flushed to the popup view as they arrive — first-token latency determines perceived speed, not total generation time.

### 7.5 Network

- Dedicated `URLSession` with HTTP keep-alive.
- `httpMaximumConnectionsPerHost = 1` (one active stream at a time).
- `localhost` loopback means no real network latency; the bottleneck is JSON parsing, which happens incrementally.

### 7.6 Latency budgets (M-series Apple Silicon, warm model, 1280 px region)

| Stage | Target |
|---|---|
| Region selection → `CGImage` | ≤ 150 ms |
| Encode + base64 | ≤ 80 ms |
| HTTP request dispatch → first token | ≤ 800 ms |
| Short-text total (< 100 chars) | ≤ 3 s |
| Medium-text total (one paragraph) | ≤ 8 s |

The Debug tab in Settings surfaces the last 10 operations' `{capture_ms, encode_ms, first_token_ms, total_ms}` so regressions are diagnosable without attaching a debugger.

## 8. Permissions

Lumo requires **two** user-granted permissions:

1. **Screen Recording** — needed for `ScreenCaptureKit` to capture any region. Requested on first capture attempt. Denial disables the capture path but leaves the app functional for double-copy.
2. **Accessibility** — needed for `CGEventTap` to observe global key events for the double-`⌘C` feature. Requested on first launch. Denial disables only the double-copy path.

First launch shows a single onboarding window that explains both permissions and offers one button per permission that opens the relevant pane of System Settings.

## 9. Settings persistence

- Plain settings → `@AppStorage` / `UserDefaults.standard`.
- History → JSON-encoded array in `UserDefaults` under `lumo.history`.
- No secrets are stored. (Ollama is local and unauthenticated; nothing to protect with the keychain.)

## 10. Launch at login

Uses `SMAppService.mainApp.register()` / `.unregister()` (macOS 13+). Default is off; user opts in via Settings.

## 11. Testing strategy

### Unit tests (XCTest, no external dependencies)

- **`StreamParser`**: NDJSON fixture inputs (short, long, split mid-line, containing `<think>` blocks, ending with `done:true`) → expected token sequences and final accumulated string. Captured `ollama run` output is checked into `Tests/Fixtures/` for regression.
- **`PromptBuilder`**: given `(source, target)` pairs, asserts the returned system + user messages.
- **`LanguageDetector`**: Hangul ratio thresholds; boundary cases (exactly 50%, mixed Korean+English, pure punctuation, emoji only).
- **`HistoryStore`**: append, trim to 10, serialize round-trip.
- **`OllamaTranslator`**: `URLProtocol` stub returning canned NDJSON bodies → asserts the emitted stream, error propagation on 404/500/timeout, cancellation on `Task.cancel`.
- **Timeout watchdog**: injectable clock feeds `translateWithTimeouts` a scripted stream (never emits / emits then stalls / emits full response) and asserts that the three timeout variants fire with the right `TranslationError` case and within expected tolerance.
- **`TranslationOrchestrator`**: mocks for `CaptureService`, `Translator`, `Clipboard`, `HistoryStore` → asserts success path, each failure branch, cancellation, and that clipboard is restorable on double-copy.
- **`DoubleCopyMonitor`**: injectable clock; tests 200/300/301/500 ms intervals and the `changeCount` gating.

### Integration smoke tests (separate scheme, skipped on CI)

Three fixture images (English / Japanese / Chinese) and three text inputs translated against a real local Ollama. Assertions:

- Response arrives within a soft budget (10 s)
- Buffer is non-empty
- Output contains at least one Hangul character (for Korean target)
- Prompt regression: output contains no Markdown headers, bullets, `<think>` tags, or the string "번역"

### Manual release checklist

Permission, hotkey, and event-tap behaviors resist automation. A checked list runs before each release:

- First-launch Screen Recording prompt → grant → restart → capture works
- First-launch Accessibility prompt → deny → capture still works, double-copy disabled with clear UI indication
- `⌘⇧1` + `ESC` → silent cancel
- `⌘⇧1` + drag → popup, stream, clipboard set, fade after 5 s
- Ollama stopped → capture shows clear error + retry
- `gemma4:e4b` removed (`ollama rm`) → model-missing error with copyable command
- Single `⌘C` → normal copy, no interference
- Double `⌘C` on English → Korean translation, clipboard overwritten, restore button works
- Double `⌘C` on Korean → English translation
- Double `⌘C` with image on clipboard → warning, no API call
- Long streaming + hover → popup stays; unhover → fade after 5 s
- Menu-bar icon transitions: idle → busy → done/error
- Settings change reflected immediately (hotkey re-registration, keep_alive)
- Launch-at-login toggle verified via `SMAppService` status
- Debug tab latency targets met on representative hardware
- Kill Ollama mid-stream → idle timeout fires within ~8 s with a clear error
- Point settings at a bogus `localhost:11435` → first-token timeout fires within ~20 s

## 12. Open questions (for later iteration, not blocking v1)

These are intentionally out of scope for the first implementation but worth capturing:

- **Multi-monitor capture** — current plan grabs from the monitor containing the drag origin. Is that sufficient for DPI mixing edge cases?
- **Retina scaling** — capture native pixels or downscale to points? Affects OCR quality vs payload size.
- **Streaming cancellation UX** — should the popup's X button ask for confirmation if the stream is already 80% done? v1: no, just cancel.
- **History persistence across quit** — v1 stores in UserDefaults. A future version might move to a small SQLite/GRDB store with search.
- **Alternative translators** — `Translator` protocol leaves room for an `OllamaVisionlessTranslator` (Apple Vision OCR + Ollama text) or a cloud provider, but these are not built in v1.

## 13. Out of scope for v1

- Installing / updating / pulling the Ollama model from inside the app.
- Non-Korean target languages for the capture path.
- Document translation (PDF, rtf).
- TTS of the translation.
- Anything stored in iCloud or synced between devices.
