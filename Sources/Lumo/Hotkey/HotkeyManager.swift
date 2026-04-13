import Foundation
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let captureAndTranslate = Self(
        "captureAndTranslate",
        default: .init(.one, modifiers: [.command, .shift])
    )
}

@MainActor
final class HotkeyManager {
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func start() {
        KeyboardShortcuts.onKeyDown(for: .captureAndTranslate) { [weak self] in
            self?.onTrigger()
        }
    }

    func stop() {
        KeyboardShortcuts.disable(.captureAndTranslate)
    }
}
