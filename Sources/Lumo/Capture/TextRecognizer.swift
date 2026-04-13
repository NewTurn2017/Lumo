import CoreGraphics
import Foundation
import Vision

protocol TextRecognizing {
    func recognize(_ image: CGImage) async throws -> String
}

/// On-device OCR using Vision. Runs on the Neural Engine on Apple Silicon and
/// returns in milliseconds — dramatically faster than sending an image to a
/// multimodal LLM for text extraction.
struct VisionTextRecognizer: TextRecognizing {
    func recognize(_ image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.recognitionLanguages = [
                        "ko-KR", "en-US", "ja-JP", "zh-Hans", "zh-Hant"
                    ]
                    let handler = VNImageRequestHandler(cgImage: image, options: [:])
                    try handler.perform([request])
                    let observations = request.results ?? []
                    let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                    cont.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
