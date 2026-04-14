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

enum TranslationError: Error, Equatable, LocalizedError {
    case serverUnreachable
    case modelNotFound(name: String)
    case httpStatus(code: Int, body: String)
    case malformedResponse(detail: String)
    case firstTokenTimeout
    case idleTimeout
    case hardTimeout
    case cancelled
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .serverUnreachable:
            return "서버에 연결할 수 없음"
        case .modelNotFound(let name):
            return "모델을 찾을 수 없음: \(name)"
        case .httpStatus(let code, let body):
            let trimmed = body.prefix(200)
            return "HTTP \(code): \(trimmed)"
        case .malformedResponse(let detail):
            return "응답 형식 오류: \(detail)"
        case .firstTokenTimeout:
            return "응답 시작 시간 초과"
        case .idleTimeout:
            return "스트림 중단 (idle timeout)"
        case .hardTimeout:
            return "총 시간 초과"
        case .cancelled:
            return "취소됨"
        case .emptyOutput:
            return "(텍스트 없음)"
        }
    }
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
