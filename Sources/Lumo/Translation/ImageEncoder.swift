import Foundation
import CoreGraphics

enum ImageEncoder {
    static func jpegBase64(_ image: CGImage, longEdge: Int) throws -> String {
        // Temporary: replaced in Task 12 with downscaling implementation.
        throw TranslationError.malformedResponse(detail: "ImageEncoder not yet implemented")
    }
}
