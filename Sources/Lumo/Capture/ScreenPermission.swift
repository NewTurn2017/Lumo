import Foundation
import CoreGraphics
import AppKit

enum ScreenPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
