import Foundation
@testable import Lumo

final class MockTranslator: Translator {
    struct Call: Equatable {
        var source: TranslationSource
        var target: TargetLanguage
    }
    var calls: [Call] = []
    var nextChunks: [String] = []
    var nextError: Error?

    func translate(source: TranslationSource, target: TargetLanguage)
        -> AsyncThrowingStream<String, Error>
    {
        calls.append(Call(source: source, target: target))
        let chunks = nextChunks
        let err = nextError
        return AsyncThrowingStream { c in
            Task {
                if let err = err {
                    c.finish(throwing: err); return
                }
                for chunk in chunks { c.yield(chunk) }
                c.finish()
            }
        }
    }
}
