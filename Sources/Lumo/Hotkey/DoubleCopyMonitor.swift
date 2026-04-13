import Foundation
import AppKit
import CoreGraphics

/// Pure state machine for double-⌘C detection. Unit-tested.
struct DoubleCopyDetector {
    let thresholdMs: Int
    private var lastMs: Int?
    private var lastChangeCount: Int?

    init(thresholdMs: Int) { self.thresholdMs = thresholdMs }

    /// Returns true if this observation should fire a translation.
    mutating func observeCopy(atMs nowMs: Int, changeCount: Int) -> Bool {
        guard let prevMs = lastMs, let prevCount = lastChangeCount else {
            lastMs = nowMs
            lastChangeCount = changeCount
            return false
        }
        let delta = nowMs - prevMs
        let increased = changeCount > prevCount
        let withinThreshold = delta <= thresholdMs
        if withinThreshold && increased {
            // Reset so three-in-a-row only fires once.
            lastMs = nil
            lastChangeCount = nil
            return true
        }
        lastMs = nowMs
        lastChangeCount = changeCount
        return false
    }
}

/// Real-event wrapper. Installs a passive CGEventTap and forwards detector hits to a callback.
@MainActor
final class DoubleCopyMonitor {
    private let detectorBox = DetectorBox()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onFire: () -> Void
    private let clipboard: Clipboard

    init(thresholdMs: Int, clipboard: Clipboard, onFire: @escaping () -> Void) {
        self.detectorBox.detector = DoubleCopyDetector(thresholdMs: thresholdMs)
        self.clipboard = clipboard
        self.onFire = onFire
    }

    func start() {
        guard AXIsProcessTrusted() else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let box = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, cg, refcon in
            guard type == .keyDown, let refcon = refcon else { return Unmanaged.passUnretained(cg) }
            let this = Unmanaged<DoubleCopyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            this.handle(cg)
            return Unmanaged.passUnretained(cg)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: box
        ) else { return }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        eventTap = nil
        runLoopSource = nil
    }

    private nonisolated func handle(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        guard keyCode == 8 /* C */, flags.contains(.maskCommand) else { return }
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        Task { @MainActor in
            // Give the source app ~20ms to finish writing the pasteboard
            try? await Task.sleep(for: .milliseconds(20))
            let fire = self.detectorBox.observe(atMs: nowMs, changeCount: self.clipboard.changeCount)
            if fire { self.onFire() }
        }
    }
}

private final class DetectorBox {
    var detector = DoubleCopyDetector(thresholdMs: 300)
    func observe(atMs: Int, changeCount: Int) -> Bool {
        detector.observeCopy(atMs: atMs, changeCount: changeCount)
    }
}
