import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoder {
    static func jpegBase64(_ image: CGImage, longEdge: Int) throws -> String {
        let scaled = try downscale(image, longEdge: longEdge)
        let data = try jpeg(scaled, quality: 0.85)
        return data.base64EncodedString()
    }

    static func downscale(_ image: CGImage, longEdge: Int) throws -> CGImage {
        let srcLong = max(image.width, image.height)
        guard srcLong > longEdge else { return image }
        let scale = Double(longEdge) / Double(srcLong)
        let newW = max(1, Int(Double(image.width) * scale))
        let newH = max(1, Int(Double(image.height) * scale))
        // JPEG output is alpha-less and sRGB; normalise here so wide-gamut or
        // CMYK sources (which would fail the 8bpc context init below) are
        // resampled into a space the encoder can actually handle.
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: newW,
            height: newH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: bitmapInfo
        ) else {
            throw TranslationError.malformedResponse(detail: "CGContext creation failed")
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        guard let out = ctx.makeImage() else {
            throw TranslationError.malformedResponse(detail: "downscale makeImage failed")
        }
        return out
    }

    static func jpeg(_ image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw TranslationError.malformedResponse(detail: "CGImageDestination failed")
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dst, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dst) else {
            throw TranslationError.malformedResponse(detail: "JPEG finalize failed")
        }
        return data as Data
    }
}
