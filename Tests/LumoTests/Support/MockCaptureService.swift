import CoreGraphics
@testable import Lumo

final class MockCaptureService: CaptureService {
    var imageToReturn: CGImage?
    var errorToThrow: Error?
    var callCount = 0

    func captureRegion() async throws -> CGImage {
        callCount += 1
        if let e = errorToThrow { throw e }
        if let i = imageToReturn { return i }
        // default 1x1
        let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
