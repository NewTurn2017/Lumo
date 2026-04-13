import CoreGraphics
@testable import Lumo

final class MockTextRecognizer: TextRecognizing {
    var text: String = ""
    var error: Error?

    func recognize(_ image: CGImage) async throws -> String {
        if let error { throw error }
        return text
    }
}
