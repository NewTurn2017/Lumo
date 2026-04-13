# Multi-Monitor Capture Bug Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `⌘⇧1` region capture flow so it works on every connected display, dismisses stale overlays on repeated hotkey presses, and passes correct points/pixels coordinates to ScreenCaptureKit.

**Architecture:** Isolate the AppKit↔CoreGraphics coordinate conversion in a pure helper (`CaptureCoordinates`), return a screen-aware `SelectedRegion` value from `RegionSelector`, match the target `SCDisplay` by `CGDirectDisplayID`, and rewrite the overlay as a `.nonactivatingPanel` with a single-active-controller guard.

**Tech Stack:** Swift 5.9, AppKit (`NSScreen`, `NSPanel`), ScreenCaptureKit (macOS 14+), XCTest, xcodebuild.

**Spec:** `docs/superpowers/specs/2026-04-13-multi-monitor-capture-design.md`

---

## File Structure

| File | Role |
|---|---|
| `Sources/Lumo/Capture/CaptureCoordinates.swift` (new) | Pure function: convert AppKit view-local rect → display-local CG rect. |
| `Tests/LumoTests/CaptureCoordinatesTests.swift` (new) | Three unit tests exercising the Y-flip math (bottom, top, symmetric). |
| `Sources/Lumo/Capture/RegionSelector.swift` (modify) | Introduce `SelectedRegion`, switch to `OverlayPanel`, activate-before-show, single-controller guard, completion guard. |
| `Sources/Lumo/Capture/CaptureService.swift` (modify) | Match `SCDisplay` via `CGDirectDisplayID`, call `CaptureCoordinates`, apply `backingScaleFactor` to output pixel dimensions. |

No changes to `TranslationOrchestrator`, `PopupWindow`, `MenuBarController`, `Warmup`, or translation code. The `CaptureService` protocol signature (`captureRegion() async throws -> CGImage`) stays stable, so `MockCaptureService` and `TranslationOrchestratorTests` are unaffected.

---

## Task 1: `CaptureCoordinates` pure helper + unit tests

**Files:**
- Create: `Sources/Lumo/Capture/CaptureCoordinates.swift`
- Create: `Tests/LumoTests/CaptureCoordinatesTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/LumoTests/CaptureCoordinatesTests.swift`:

```swift
import XCTest
@testable import Lumo

final class CaptureCoordinatesTests: XCTestCase {
    func test_bottomRegion_flipsToBottomInCG() {
        let result = CaptureCoordinates.displayLocalRect(
            viewRect: CGRect(x: 100, y: 100, width: 200, height: 50),
            screenHeight: 1080
        )
        XCTAssertEqual(result, CGRect(x: 100, y: 930, width: 200, height: 50))
    }

    func test_topRegion_flipsToTopInCG() {
        let result = CaptureCoordinates.displayLocalRect(
            viewRect: CGRect(x: 0, y: 1030, width: 100, height: 50),
            screenHeight: 1080
        )
        XCTAssertEqual(result, CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func test_symmetricCenter_isSelfDual() {
        let result = CaptureCoordinates.displayLocalRect(
            viewRect: CGRect(x: 250, y: 250, width: 500, height: 500),
            screenHeight: 1000
        )
        XCTAssertEqual(result, CGRect(x: 250, y: 250, width: 500, height: 500))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:LumoTests/CaptureCoordinatesTests test 2>&1 | tail -20
```

Expected: FAIL — compile error `cannot find 'CaptureCoordinates' in scope`.

- [ ] **Step 3: Create the helper**

Create `Sources/Lumo/Capture/CaptureCoordinates.swift`:

```swift
import CoreGraphics

enum CaptureCoordinates {
    /// Converts a rect in AppKit view-local coordinates (bottom-left origin, Y up)
    /// into the target display's CoreGraphics-local coordinates (top-left origin, Y down).
    /// Both input and output are in points.
    static func displayLocalRect(viewRect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: viewRect.origin.x,
            y: screenHeight - viewRect.origin.y - viewRect.height,
            width: viewRect.width,
            height: viewRect.height
        )
    }
}
```

- [ ] **Step 4: Regenerate Xcode project and run tests**

Run:
```bash
xcodegen generate
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:LumoTests/CaptureCoordinatesTests test 2>&1 | tail -15
```

Expected: `** TEST SUCCEEDED **` — three tests pass.

- [ ] **Step 5: Run full test suite (regression guard)**

Run:
```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug \
  -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `Executed 56 tests, with 0 failures` (53 existing + 3 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/Lumo/Capture/CaptureCoordinates.swift \
        Tests/LumoTests/CaptureCoordinatesTests.swift
git commit -m "$(cat <<'EOF'
feat(capture): add CaptureCoordinates for AppKit→CG rect conversion

Pure helper that flips Y from AppKit view-local coordinates (origin
bottom-left, Y up) to display-local CoreGraphics coordinates (origin
top-left, Y down). Isolated so the coordinate logic has a single unit-
tested home.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Route selected screen through `CaptureService`

Introduce `SelectedRegion`, update `RegionSelector.presentAndSelect` to return it, and rewrite `CaptureService.captureRegion` to match the `SCDisplay` by `CGDirectDisplayID` and apply the coordinate + scale math. Overlay rendering stays on `NSWindow` in this task — that swap happens in Task 3.

**Files:**
- Modify: `Sources/Lumo/Capture/RegionSelector.swift`
- Modify: `Sources/Lumo/Capture/CaptureService.swift`

- [ ] **Step 1: Replace `RegionSelector.swift` with the screen-aware version**

Overwrite `Sources/Lumo/Capture/RegionSelector.swift` with:

```swift
import AppKit

struct SelectedRegion {
    let rect: CGRect
    let screen: NSScreen
}

enum RegionSelector {
    @MainActor
    static func presentAndSelect() async throws -> SelectedRegion {
        try await withCheckedThrowingContinuation { continuation in
            let controller = OverlayController { result in
                switch result {
                case .success(let r): continuation.resume(returning: r)
                case .failure(let e): continuation.resume(throwing: e)
                }
            }
            controller.show()
        }
    }
}

private final class OverlayController: NSObject {
    typealias Completion = (Result<SelectedRegion, Error>) -> Void
    private var windows: [NSWindow] = []
    private let completion: Completion
    /// Retains self until cleanup() — prevents deallocation before continuation resumes.
    private var keepAlive: OverlayController?

    init(completion: @escaping Completion) { self.completion = completion }

    func show() {
        keepAlive = self
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = NSColor.black.withAlphaComponent(0.2)
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in self?.finish(rect: rect, screen: screen) }
            view.onCancel = { [weak self] in self?.cancel() }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(rect: NSRect, screen: NSScreen) {
        cleanup()
        completion(.success(SelectedRegion(rect: rect, screen: screen)))
    }

    private func cancel() {
        cleanup()
        completion(.failure(CancellationError()))
    }

    private func cleanup() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        keepAlive = nil
    }
}

private final class SelectionView: NSView {
    var onFinish: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: NSPoint?
    private var currentRect: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 /* ESC */ { onCancel?() }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let cur = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, cur.x),
            y: min(start.y, cur.y),
            width: abs(cur.x - start.x),
            height: abs(cur.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 4, rect.height > 4 else {
            onCancel?()
            return
        }
        onFinish?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = currentRect else { return }
        NSColor(white: 1, alpha: 0.15).setFill()
        rect.fill()
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.stroke()
    }
}
```

Key deltas from the previous version:
- New `SelectedRegion` struct at file scope.
- `presentAndSelect` returns `SelectedRegion`.
- `finish` signature is `finish(rect:screen:)` — no more global-coordinate arithmetic, no more `origin: CGPoint` parameter.
- `onFinish` closure captures `screen` directly (`view.onFinish = { [weak self] rect in self?.finish(rect: rect, screen: screen) }`).
- The dead `selectionView: SelectionView?` property and its always-true assignment are removed.

- [ ] **Step 2: Replace `CaptureService.swift` with the displayID-matching version**

Overwrite `Sources/Lumo/Capture/CaptureService.swift` with:

```swift
import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit

protocol CaptureService {
    /// Presents the region-selection overlay and returns the captured region as a CGImage.
    /// Throws `CancellationError` if the user pressed ESC.
    func captureRegion() async throws -> CGImage
}

@available(macOS 14.0, *)
final class ScreenCaptureKitCapture: CaptureService {
    func captureRegion() async throws -> CGImage {
        let selection = try await RegionSelector.presentAndSelect()
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        let displayID = Self.displayID(of: selection.screen)
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID })
            ?? content.displays.first
        else {
            throw TranslationError.malformedResponse(detail: "no display")
        }

        let sourceRect = CaptureCoordinates.displayLocalRect(
            viewRect: selection.rect,
            screenHeight: selection.screen.frame.height
        )
        let scale = selection.screen.backingScaleFactor

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width  = Int((sourceRect.width  * scale).rounded())
        config.height = Int((sourceRect.height * scale).rounded())
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? CGMainDisplayID()
    }
}
```

Deletions vs. previous:
- Remove the `private extension NSRect { init(_ r: CGRect) ... }` helper — no longer used.
- Remove `NSRect($0.frame).contains(rect.origin)` display matching.

- [ ] **Step 3: Regenerate project and run full test suite**

Run:
```bash
xcodegen generate
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug \
  -destination 'platform=macOS' test 2>&1 | tail -15
```

Expected: `Executed 56 tests, with 0 failures`. `TranslationOrchestratorTests` must still pass because `MockCaptureService` stubs `captureRegion()` with a canned `CGImage`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Lumo/Capture/RegionSelector.swift \
        Sources/Lumo/Capture/CaptureService.swift
git commit -m "$(cat <<'EOF'
refactor(capture): route selected screen through CaptureService

RegionSelector now returns SelectedRegion(rect, screen) instead of a
global AppKit rect. CaptureService matches the SCDisplay by
CGDirectDisplayID, converts the rect with CaptureCoordinates, and scales
output width/height by backingScaleFactor so Retina captures preserve
native resolution for OCR quality.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `OverlayPanel` + activate-before-show (fixes Bug A)

Switch the per-screen windows from `NSWindow` to an `NSPanel` subclass with `.nonactivatingPanel`, activate the app before the loop, and use `orderFrontRegardless()` so overlays render on every connected display even though Lumo is an `LSUIElement` app.

**Files:**
- Modify: `Sources/Lumo/Capture/RegionSelector.swift`

- [ ] **Step 1: Add `OverlayPanel` subclass and rewrite `show()`**

In `Sources/Lumo/Capture/RegionSelector.swift`, add this class at file scope (alongside `OverlayController`):

```swift
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

Replace `OverlayController.show()` with:

```swift
func show() {
    keepAlive = self
    NSApp.activate(ignoringOtherApps: true)
    for screen in NSScreen.screens {
        let panel = OverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onFinish = { [weak self] rect in self?.finish(rect: rect, screen: screen) }
        view.onCancel = { [weak self] in self?.cancel() }
        panel.contentView = view
        panel.orderFrontRegardless()
        windows.append(panel)
    }
}
```

Key deltas:
- `NSWindow` → `OverlayPanel`.
- `styleMask: .borderless` → `[.borderless, .nonactivatingPanel]`.
- `NSApp.activate(...)` moved **before** the loop.
- `makeKeyAndOrderFront(nil)` → `orderFrontRegardless()`.
- New line: `panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.

`windows: [NSWindow]` continues to work because `NSPanel` is an `NSWindow` subclass.

- [ ] **Step 2: Build and run full test suite**

Run:
```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug \
  -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `Executed 56 tests, with 0 failures`. No test covers overlay presentation directly; this step is a regression guard that the code still compiles and the rest of the suite is green.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lumo/Capture/RegionSelector.swift
git commit -m "$(cat <<'EOF'
fix(capture): render overlay on every display via nonactivating panel

Replace the per-screen NSWindow with an OverlayPanel subclass of NSPanel
using [.borderless, .nonactivatingPanel] style, activate the app before
the presentation loop, and use orderFrontRegardless(). LSUIElement apps
need this combination to reliably show overlays on secondary displays;
otherwise only the primary monitor received one.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Single-active-controller guard + completion protection (fixes Bug B)

Dismiss any existing overlay when a new `presentAndSelect` begins, and protect the completion callback against double-resume (which would crash `withCheckedThrowingContinuation`).

**Files:**
- Modify: `Sources/Lumo/Capture/RegionSelector.swift`

- [ ] **Step 1: Add `current` tracker and `dismiss(with:)` plumbing**

Update the `RegionSelector` enum in `Sources/Lumo/Capture/RegionSelector.swift`:

```swift
enum RegionSelector {
    @MainActor fileprivate static weak var current: OverlayController?

    @MainActor
    static func presentAndSelect() async throws -> SelectedRegion {
        current?.dismiss(with: CancellationError())
        return try await withCheckedThrowingContinuation { continuation in
            let controller = OverlayController { result in
                switch result {
                case .success(let r): continuation.resume(returning: r)
                case .failure(let e): continuation.resume(throwing: e)
                }
            }
            current = controller
            controller.show()
        }
    }
}
```

Add `hasCompleted` state and `dismiss(with:)` to `OverlayController`. Replace the existing `finish`, `cancel`, and `cleanup` with the guarded versions below:

```swift
private final class OverlayController: NSObject {
    typealias Completion = (Result<SelectedRegion, Error>) -> Void
    private var windows: [NSWindow] = []
    private let completion: Completion
    private var keepAlive: OverlayController?
    private var hasCompleted = false

    init(completion: @escaping Completion) { self.completion = completion }

    func show() {
        // (body unchanged from Task 3)
    }

    func dismiss(with error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(.failure(error))
    }

    private func finish(rect: NSRect, screen: NSScreen) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(.success(SelectedRegion(rect: rect, screen: screen)))
    }

    private func cancel() {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(.failure(CancellationError()))
    }

    private func cleanup() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        keepAlive = nil
    }
}
```

Notes:
- `RegionSelector.current` uses `fileprivate` so it can reference the file-private `OverlayController` type.
- `weak var current` → zeroed automatically after `keepAlive = nil` + the controller going out of other strong references.
- The `hasCompleted` flag makes all three completion paths idempotent, so a `dismiss` race with a user drag finishing cannot double-resume the continuation.

- [ ] **Step 2: Build and run full test suite**

Run:
```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug \
  -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: `Executed 56 tests, with 0 failures`.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lumo/Capture/RegionSelector.swift
git commit -m "$(cat <<'EOF'
fix(capture): dismiss stale overlays on repeated hotkey presses

RegionSelector now tracks a single active OverlayController and calls
dismiss(with:) on it before starting a new presentation. OverlayController
uses a hasCompleted guard so finish/cancel/dismiss cannot double-resume
the continuation. Repeatedly pressing ⌘⇧1 no longer stacks overlays.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Final verification

**Files:** none (validation only).

- [ ] **Step 1: Clean build + full test suite**

Run:
```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug \
  -destination 'platform=macOS' clean test 2>&1 | tail -15
```

Expected: `** TEST SUCCEEDED **` and `Executed 56 tests, with 0 failures`.

- [ ] **Step 2: Launch the built app and walk the manual checklist**

Open the built `.app` from DerivedData or run via Xcode. With the target machine connected to at least two displays, verify each item. Report pass/fail per item.

- [ ] Single monitor: `⌘⇧1` works (regression guard).
- [ ] Secondary monitor (alone): overlay appears, drag produces correct capture translated by Lumo.
- [ ] Primary + secondary: drag on primary captures correct region; drag on secondary captures correct region.
- [ ] Mixed resolutions / Retina + non-Retina: output image resolution matches the source display's native pixels (inspect via popup result or Ollama input size logs).
- [ ] Press `⌘⇧1` three times quickly: exactly one overlay is visible at any moment.
- [ ] Mid-drag `⌘⇧1`: old overlay vanishes, new overlay replaces it; first drag does not produce a capture.
- [ ] ESC on secondary monitor: all overlays dismissed, no popup appears.

- [ ] **Step 3: Record results in the plan**

Tick each checkbox above as it passes. If any fail, stop and diagnose before marking the plan complete.

---

## Self-Review Notes

- **Spec coverage:** Every file in the spec's "File-Level Change Summary" has a task. All three root causes (Bugs 1, 2, 3) are addressed: Bug 1 in Task 3, Bug 2 in Task 4, Bug 3 in Tasks 1+2. Manual verification checklist mirrors the spec.
- **Placeholder scan:** No TBD/TODO. Every code step shows complete replacement code.
- **Type consistency:** `SelectedRegion { rect: CGRect; screen: NSScreen }` is introduced in Task 2 and referenced identically in Task 2's `CaptureService` rewrite, Task 3's unchanged `show()` body, and Task 4's `finish(rect:screen:)` signature. `CaptureCoordinates.displayLocalRect(viewRect:screenHeight:)` signature is the same in Task 1 (definition + tests) and Task 2 (call site). `OverlayController.dismiss(with:)` signature is consistent between `RegionSelector.presentAndSelect` (Task 4) and the class definition (Task 4).
- **Intermediate states compile:** After Task 2 the overlay bug still exists but coordinates are correct; after Task 3 secondary-monitor rendering works; after Task 4 stacking is fixed. Each state compiles and keeps the full test suite green because no change touches the `CaptureService` protocol or the `MockCaptureService` test stub.
