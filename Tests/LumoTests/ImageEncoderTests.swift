import XCTest
@testable import Lumo
import CoreGraphics

final class ImageEncoderTests: XCTestCase {
    func test_downscalesWhenLongEdgeExceedsLimit() throws {
        let img = solidImage(width: 4000, height: 2000)
        let base64 = try ImageEncoder.jpegBase64(img, longEdge: 1280)
        let data = Data(base64Encoded: base64)!
        let decoded = try XCTUnwrap(decode(data))
        XCTAssertEqual(max(decoded.width, decoded.height), 1280)
    }

    func test_preservesWhenAlreadySmaller() throws {
        let img = solidImage(width: 800, height: 400)
        let base64 = try ImageEncoder.jpegBase64(img, longEdge: 1280)
        let data = Data(base64Encoded: base64)!
        let decoded = try XCTUnwrap(decode(data))
        XCTAssertEqual(decoded.width, 800)
        XCTAssertEqual(decoded.height, 400)
    }

    private func solidImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill([CGRect(x: 0, y: 0, width: width, height: height)])
        return ctx.makeImage()!
    }

    private func decode(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
