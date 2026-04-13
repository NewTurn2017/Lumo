import AppKit

struct SelectedRegion {
    let rect: CGRect
    let screen: NSScreen
}

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

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class OverlayController: NSObject {
    typealias Completion = (Result<SelectedRegion, Error>) -> Void
    private var windows: [NSWindow] = []
    private let completion: Completion
    /// Retains self until cleanup() — prevents deallocation before continuation resumes.
    private var keepAlive: OverlayController?
    private var hasCompleted = false

    init(completion: @escaping Completion) { self.completion = completion }

    func dismiss(with error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cleanup()
        completion(.failure(error))
    }

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
