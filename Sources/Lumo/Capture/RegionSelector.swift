import AppKit

enum RegionSelector {
    @MainActor
    static func presentAndSelect() async throws -> CGRect {
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
    typealias Completion = (Result<CGRect, Error>) -> Void
    private var windows: [NSWindow] = []
    private var selectionView: SelectionView?
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
            view.onFinish = { [weak self] rect in self?.finish(rect: rect, origin: screen.frame.origin) }
            view.onCancel = { [weak self] in self?.cancel() }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            if view.bounds.size == screen.frame.size {
                selectionView = view
            }
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(rect: NSRect, origin: CGPoint) {
        let global = CGRect(
            x: rect.origin.x + origin.x,
            y: rect.origin.y + origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
        cleanup()
        completion(.success(global))
    }

    private func cancel() {
        cleanup()
        completion(.failure(CancellationError()))
    }

    private func cleanup() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        keepAlive = nil  // Release self-retain; ARC reclaims after this scope exits
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
