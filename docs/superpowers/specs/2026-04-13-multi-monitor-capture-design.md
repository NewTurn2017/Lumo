# Multi-Monitor Capture Bug Fix — Design

**Date:** 2026-04-13
**Status:** Design approved, ready for implementation plan
**Scope:** Region capture flow (`RegionSelector`, `CaptureService`)

## Problem

With multiple displays connected, `⌘⇧1` (region capture) is broken:

1. **Overlay only on main display.** The dark-tinted selection overlay appears only on the primary monitor. Dragging on a secondary monitor has no effect — the overlay is not visible there.
2. **Overlay stacking.** Pressing `⌘⇧1` repeatedly creates additional overlays without dismissing the previous one. The user must click (cancel) each stacked overlay individually to clear them.
3. **Latent coordinate bug.** Even on the primary display, the captured region is computed with mixed coordinate systems: `RegionSelector` produces a rect in AppKit global coordinates (origin bottom-left, Y up), while `CaptureService` passes that rect to `SCStreamConfiguration.sourceRect` and matches against `SCDisplay.frame`, both of which expect CoreGraphics display-local coordinates (origin top-left, Y down). Happens to be tolerable on a single primary display with certain regions; produces wrong output on multi-display setups.

All three must be fixed together — (1) and (2) are the observable bugs, (3) is guaranteed to surface once (1) is fixed and the user drags on a secondary monitor.

## Root Causes

### Bug 1 — overlay only on main display

`RegionSelector.OverlayController.show()` creates one `NSWindow` per `NSScreen.screens`, calls `makeKeyAndOrderFront(nil)` on each, then calls `NSApp.activate(ignoringOtherApps:)` **after** the loop. In an `LSUIElement` (accessory) app, windows created before activation on inactive screens are not reliably rendered — the primary screen tends to show its overlay because the mouse happens to be over it or because the app's prior focus was there, but secondary monitors silently get nothing.

### Bug 2 — overlay stacking

`TranslationOrchestrator.runCapture` calls `cancelCurrent()` before each new `_runCapture`, which cancels the previous `Task` — but `RegionSelector.presentAndSelect` uses `withCheckedThrowingContinuation` without a cancellation handler, so `Task.cancel()` never reaches the overlay. The old `OverlayController` holds itself alive via `keepAlive = self` until explicit cleanup, so its windows remain on screen indefinitely.

### Bug 3 — coordinate system mismatch

`RegionSelector.finish` produces a rect in global AppKit coordinates:

```swift
let global = CGRect(
    x: rect.origin.x + screen.frame.origin.x,
    y: rect.origin.y + screen.frame.origin.y,
    ...
)
```

`CaptureService.captureRegion` then uses that rect in two places that expect CoreGraphics display-local coordinates:

```swift
guard let display = content.displays.first(where: { NSRect($0.frame).contains(rect.origin) }) ...
...
config.sourceRect = rect
config.width  = Int(rect.width)
config.height = Int(rect.height)
```

`SCDisplay.frame` is in the CoreGraphics global display space (top-left origin, Y down). `SCStreamConfiguration.sourceRect` is in points relative to the `SCContentFilter`'s display content (top-left origin, Y down). The Y axis and origin are wrong for the primary display and wrong in different ways for secondary displays.

Additionally, `config.width`/`config.height` are in pixels, not points — no `backingScaleFactor` multiplication, so Retina capture output is half the native resolution, hurting OCR quality.

## Goals

- Region capture works on every connected display.
- Pressing `⌘⇧1` repeatedly never produces more than one live overlay.
- Captured region matches what the user dragged, pixel-for-pixel, at the display's native resolution.
- No regression on single-display setups.
- No API change to the `CaptureService` protocol — `TranslationOrchestrator` remains untouched.

## Non-Goals

- Changing the visual design of the overlay (tint, cursor, hint text).
- Dragging across display boundaries into a second display (users select within one display).
- Capture from mirrored displays (SCDisplay picks one; acceptable for now).
- Ollama connection health / menu-bar visibility — tracked in a separate spec.

## Design

### New type: `SelectedRegion`

```swift
struct SelectedRegion {
    let rect: CGRect         // view-local, bottom-left origin, points
    let screen: NSScreen     // the screen the rect was drawn on
}
```

`RegionSelector.presentAndSelect` returns `SelectedRegion` instead of `CGRect`. This removes the global-coordinate intermediate step — `CaptureService` receives both the rect and the screen it came from, so display matching is direct.

### New utility: `CaptureCoordinates`

New file `Sources/Lumo/Capture/CaptureCoordinates.swift`:

```swift
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

Pure, deterministic, easy to unit test. All coordinate-system knowledge is concentrated here.

### `RegionSelector` changes

**Panel type.** Replace the `NSWindow` per screen with an `OverlayPanel` subclass of `NSPanel`:

```swift
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

Style mask: `[.borderless, .nonactivatingPanel]`. `canBecomeKey` must be overridden because borderless panels are otherwise key-ineligible, which would block the ESC keyDown handler in `SelectionView`.

**Presentation order.** Call `NSApp.activate(ignoringOtherApps: true)` **before** the per-screen loop, and use `orderFrontRegardless()` instead of `makeKeyAndOrderFront(nil)` on each panel. This combination reliably displays overlays on every connected screen for an `LSUIElement` app.

Add `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]` to each panel so the overlay works across full-screen Spaces and Mission Control.

**Single active controller (fixes Bug 2).**

```swift
enum RegionSelector {
    @MainActor private static weak var current: OverlayController?

    @MainActor
    static func presentAndSelect() async throws -> SelectedRegion {
        current?.dismiss(with: CancellationError())
        return try await withCheckedThrowingContinuation { cont in
            let controller = OverlayController { result in cont.resume(with: result) }
            current = controller
            controller.show()
        }
    }
}
```

`weak` so a completed controller is auto-released. `dismiss(with:)` is a new public method on `OverlayController` that runs cleanup and resumes the continuation with the given error.

**Cleanup unification and completion guard.** Three completion paths — `onFinish`, `onCancel`, `dismiss(with:)` — now share a single cleanup helper. A `hasCompleted: Bool` flag guards against double-resume (which would crash `withCheckedThrowingContinuation`).

**Return value change.** `finish` now passes `SelectedRegion(rect: viewRect, screen: screen)` — no more global-coordinate arithmetic. The caller's `withCheckedThrowingContinuation` resumes with `.success(SelectedRegion)`.

### `CaptureService` changes

```swift
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

Key points:

- `NSScreen.deviceDescription[NSScreenNumber]` → `CGDirectDisplayID` is the standard idiom for mapping `NSScreen` to `SCDisplay`.
- `sourceRect` is in **points**; `width`/`height` are in **pixels**. Multiplying by `backingScaleFactor` preserves native resolution on Retina displays, which matters for OCR quality.
- The previous `NSRect($0.frame).contains(rect.origin)` global-coordinate match is gone — display identification is now by stable ID.

## Error Handling & Edge Cases

| Situation | Behavior |
|---|---|
| Drag region < 4pt | `SelectionView.mouseUp` calls `onCancel` → `CancellationError` (unchanged) |
| ESC pressed | `keyDown` → `onCancel` → `CancellationError` (unchanged) |
| `NSScreenNumber` extraction fails | Fall back to `CGMainDisplayID()` |
| No `SCDisplay` matches displayID (e.g., monitor unplugged mid-flow) | Fall back to `content.displays.first`, else throw `malformedResponse` |
| Repeated `⌘⇧1` while overlay is up | `RegionSelector.current?.dismiss(with: CancellationError())` clears the old overlay; old continuation resumes with `CancellationError`; first `Task` exits via `catch is CancellationError { return }` in `_runCapture` |
| Drag attempted across screen boundary | Not possible — each `SelectionView` is scoped to one screen's window; drag clamps naturally to that screen's bounds |
| Double completion | `hasCompleted` flag prevents second `cont.resume` → no crash |

## Testing Strategy

### Unit tests (new file)

`Tests/LumoTests/CaptureCoordinatesTests.swift` — covers `CaptureCoordinates.displayLocalRect` with three cases:

1. **Bottom region.** 1080pt-high screen, viewRect `(100, 100, 200, 50)` → expected CG rect `(100, 930, 200, 50)`.
2. **Top region.** 1080pt-high screen, viewRect `(0, 1030, 100, 50)` → expected CG rect `(0, 0, 100, 50)`.
3. **Symmetric center.** 1000pt-square screen, viewRect `(250, 250, 500, 500)` → expected CG rect `(250, 250, 500, 500)` (self-dual).

These cover Y-flip correctness plus the symmetric edge case. Pure-function, no AppKit dependency.

### Orchestrator test impact

`MockCaptureService` implements `captureRegion() async throws -> CGImage`. The protocol signature is unchanged, so `TranslationOrchestratorTests` should pass unmodified. Verify.

### Manual verification checklist

`RegionSelector`'s panel/singleton logic is deeply coupled to `NSPanel`, `NSScreen`, and live input events — unit testing it headlessly is unreliable. Use this checklist on the target hardware before merging:

- [ ] Single monitor: `⌘⇧1` works (regression guard).
- [ ] Secondary monitor (alone): overlay appears, drag produces correct capture.
- [ ] Primary + secondary: drag on primary captures correct region; drag on secondary captures correct region.
- [ ] Mixed resolutions / Retina + non-Retina: output resolution matches native on each display.
- [ ] Press `⌘⇧1` three times quickly: exactly one overlay visible at any moment.
- [ ] Mid-drag `⌘⇧1`: old overlay vanishes, new overlay replaces it; first drag does not produce a capture.
- [ ] ESC on secondary monitor: all overlays dismissed, no popup appears.

## File-Level Change Summary

| File | Change |
|---|---|
| `Sources/Lumo/Capture/RegionSelector.swift` | Rewrite: `OverlayPanel`, presentation order, singleton cleanup, `SelectedRegion` return, completion guard |
| `Sources/Lumo/Capture/CaptureCoordinates.swift` | New: pure coordinate conversion helper |
| `Sources/Lumo/Capture/CaptureService.swift` | Update `captureRegion` to match by displayID and use `CaptureCoordinates` + `backingScaleFactor` |
| `Tests/LumoTests/CaptureCoordinatesTests.swift` | New: three unit tests for Y-flip math |

No changes to `TranslationOrchestrator`, `PopupWindow`, `MenuBarController`, `Warmup`, or any translation code.
