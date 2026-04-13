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
