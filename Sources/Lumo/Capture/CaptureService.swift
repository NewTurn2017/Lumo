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
        let rect = try await RegionSelector.presentAndSelect()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { NSRect($0.frame).contains(rect.origin) })
                              ?? content.displays.first
        else {
            throw TranslationError.malformedResponse(detail: "no display")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(rect.width)
        config.height = Int(rect.height)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return image
    }
}

private extension NSRect {
    init(_ r: CGRect) { self.init(origin: r.origin, size: r.size) }
}
