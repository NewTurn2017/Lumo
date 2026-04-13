import AppKit
import SwiftUI

/// Borderless panel that can still become key — required so the popup gains focus
/// and we can observe `didResignKey` to dismiss on outside clicks.
private final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PopupWindow: PopupPresenting {
    private var window: NSWindow?
    private let model = PopupModel()
    private var fadeTask: Task<Void, Never>?
    private var resignObserver: NSObjectProtocol?

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

    /// Fired on every close path (X button, click outside, fade). Safe to call
    /// on a completed translation — `Task.cancel()` on a finished task is a no-op.
    var onCancel: (() -> Void)?

    func showLoading() {
        fadeTask?.cancel()
        model.phase = .loading
        model.text = ""
        model.errorMessage = ""
        ensureWindow()
        centerOnActiveScreen()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        observeResignKey()
    }

    func append(_ chunk: String) {
        if model.phase == .loading { model.phase = .streaming }
        model.text += chunk
    }

    func showDone(finalText: String) {
        model.phase = .done
        model.text = finalText
        scheduleFade()
    }

    func showError(_ message: String) {
        model.phase = .error
        model.errorMessage = message
        scheduleFade()
    }

    func close() {
        fadeTask?.cancel()
        removeResignObserver()
        onCancel?()
        window?.orderOut(nil)
    }

    private func scheduleFade() {
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.close() }
        }
    }

    private func ensureWindow() {
        if window != nil { return }
        let w = FocusablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
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

    private func observeResignKey() {
        guard resignObserver == nil, let window else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeResignObserver() {
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
    }
}
