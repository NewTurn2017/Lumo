import CoreGraphics

protocol CaptureService {
    /// Presents an interactive region picker and returns the captured region as a CGImage.
    /// Throws `CancellationError` if the user pressed ESC or dismissed the picker.
    func captureRegion() async throws -> CGImage
}
