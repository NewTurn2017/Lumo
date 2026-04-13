import AppKit
import SwiftUI

@MainActor
final class PopupWindow: PopupPresenting {
    private var window: NSWindow?
    private let model = PopupModel()
    private var fadeTask: Task<Void, Never>?

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

    func showLoading() {
        fadeTask?.cancel()
        model.phase = .loading
        model.text = ""
        model.errorMessage = ""
        ensureWindow()
        window?.orderFrontRegardless()
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
        window?.orderOut(nil)
    }

    private func scheduleFade() {
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.window?.orderOut(nil) }
        }
    }

    private func ensureWindow() {
        if window != nil { return }
        let w = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.isFloatingPanel = true
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.contentView = NSHostingView(rootView: PopupView(model: model))
        if let screen = NSScreen.main {
            let margin: CGFloat = 24
            let origin = CGPoint(
                x: screen.visibleFrame.maxX - 380 - margin,
                y: screen.visibleFrame.minY + margin
            )
            w.setFrameOrigin(origin)
        }
        window = w
    }
}
