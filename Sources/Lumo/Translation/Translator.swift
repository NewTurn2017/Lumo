import Foundation
import CoreGraphics

enum TargetLanguage: String, Equatable {
    case korean
    case english
}

enum TranslationSource: Equatable {
    case image(CGImage)
    case text(String)

    static func == (lhs: TranslationSource, rhs: TranslationSource) -> Bool {
        switch (lhs, rhs) {
        case let (.text(a), .text(b)): return a == b
        case (.image, .image): return true   // CGImage identity not needed for tests
        default: return false
        }
    }
}

enum TranslationError: Error, Equatable {
    case serverUnreachable
    case modelNotFound(name: String)
    case httpStatus(code: Int, body: String)
    case malformedResponse(detail: String)
    case firstTokenTimeout
    case idleTimeout
    case hardTimeout
    case cancelled
    case emptyOutput
}

struct BuiltMessages: Equatable {
    var system: String
    var userContent: String
    var images: [String]?
}

protocol Translator {
    func translate(source: TranslationSource, target: TargetLanguage)
        -> AsyncThrowingStream<String, Error>
}
