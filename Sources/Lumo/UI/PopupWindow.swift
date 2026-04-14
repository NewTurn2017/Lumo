import AppKit
import Combine
import SwiftUI

/// Borderless panel that can still become key — required so the popup gains
/// focus and can receive Escape via a local `NSEvent` monitor.
private final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PopupWindow: PopupPresenting {
    private var window: NSWindow?
    private let model = PopupModel()
    private var fadeTask: Task<Void, Never>?
    private var fadeTimer: FadeTimer?
    private var escapeMonitor: Any?
    private var hoverCancellable: AnyCancellable?

    private struct FadeTimer {
        var totalDuration: TimeInterval
        var startedAt: Date
        var elapsedBeforePause: TimeInterval = 0
        var isPaused: Bool = false
    }

    init() {
        model.onClose = { [weak self] in self?.close() }
        model.onCopy = { [weak self] in
            guard let self, !self.model.text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.model.text, forType: .string)
        }
    }

    var onRestore: (() -> Void)? {
        get { model.onRestore }
        set { model.onRestore = newValue }
    }

    /// Fired on every close path (X button, fade). Safe to call
    /// on a completed translation — `Task.cancel()` on a finished task is a no-op.
    var onCancel: (() -> Void)?

    func showLoading() {
        fadeTask?.cancel()
        fadeTimer = nil
        model.phase = .loading
        model.text = ""
        model.errorMessage = ""
        let rawPt = UserDefaults.standard.object(forKey: SettingsKey.popupFontSize) as? Int ?? 18
        let clampedPt = min(max(rawPt, 12), 28)
        model.fontSize = CGFloat(clampedPt)
        ensureWindow()
        applyPopupSize()
        centerOnActiveScreen()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installEscapeMonitor()
        hoverCancellable = model.$isHovered
            .removeDuplicates()
            .sink { [weak self] hovered in
                guard let self else { return }
                if hovered { self.pauseFade() } else { self.resumeFade() }
            }
    }

    /// Re-reads the user-selected popup size and resizes the panel before
    /// it is centered. The internal SwiftUI view fills the window via
    /// `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
    private func applyPopupSize() {
        guard let w = window else { return }
        let raw = UserDefaults.standard.string(forKey: SettingsKey.popupSize)
        let dims = PopupSize.resolve(raw).dimensions
        var frame = w.frame
        frame.size = NSSize(width: dims.width, height: dims.height)
        w.setFrame(frame, display: false)
    }

    func append(_ chunk: String) {
        if model.phase == .loading { model.phase = .streaming }
        model.text += chunk
    }

    func showDone(finalText: String) {
        model.phase = .done
        model.text = finalText
        let secs = UserDefaults.standard.object(forKey: SettingsKey.popupDismissAfterSec) as? Int ?? 15
        if secs >= 0 {
            startFade(duration: TimeInterval(secs))
        }
    }

    func showError(_ message: String) {
        model.phase = .error
        model.errorMessage = message
        startFade(duration: 5)
    }

    func close() {
        fadeTask?.cancel()
        fadeTimer = nil
        removeEscapeMonitor()
        hoverCancellable = nil
        onCancel?()
        window?.orderOut(nil)
    }

    private func startFade(duration: TimeInterval) {
        fadeTask?.cancel()
        fadeTimer = FadeTimer(totalDuration: duration, startedAt: Date())
        armFadeTask(remaining: duration)
        if model.isHovered { pauseFade() }
    }

    private func pauseFade() {
        guard var t = fadeTimer, !t.isPaused else { return }
        fadeTask?.cancel()
        t.elapsedBeforePause += Date().timeIntervalSince(t.startedAt)
        t.isPaused = true
        fadeTimer = t
    }

    private func resumeFade() {
        guard var t = fadeTimer, t.isPaused else { return }
        let remaining = max(0, t.totalDuration - t.elapsedBeforePause)
        guard remaining > 0 else { close(); return }
        t.startedAt = Date()
        t.isPaused = false
        fadeTimer = t
        armFadeTask(remaining: remaining)
    }

    private func armFadeTask(remaining: TimeInterval) {
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.close() }
        }
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 53 == kVK_Escape
            guard event.keyCode == 53,
                  self?.window?.isKeyWindow == true else { return event }
            Task { @MainActor in self?.close() }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let m = escapeMonitor {
            NSEvent.removeMonitor(m)
            escapeMonitor = nil
        }
    }

    private func ensureWindow() {
        if window != nil { return }
        let initial = PopupSize.medium.dimensions
        let w = FocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: initial.width, height: initial.height),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.isFloatingPanel = true
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.hidesOnDeactivate = false
        w.isMovableByWindowBackground = true
        w.contentView = NSHostingView(rootView: PopupView(model: model))
        window = w
    }

    private func centerOnActiveScreen() {
        guard let w = window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = w.frame.size
        let origin = CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        w.setFrameOrigin(origin)
    }
}
