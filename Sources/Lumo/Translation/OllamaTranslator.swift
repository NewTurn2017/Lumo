import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class OllamaTranslator: Translator {
    private let baseURL: URL
    private let model: String
    private let temperature: Double
    private let keepAlive: String
    private let session: URLSession
    private let maxImageLongEdge: Int

    init(
        baseURL: URL,
        model: String,
        temperature: Double,
        keepAlive: String,
        session: URLSession = .shared,
        maxImageLongEdge: Int = 1280
    ) {
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.keepAlive = keepAlive
        self.session = session
        self.maxImageLongEdge = maxImageLongEdge
    }

    func translate(source: TranslationSource, target: TargetLanguage)
        -> AsyncThrowingStream<String, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let base64: String?
                    switch source {
                    case .text:
                        base64 = nil
                    case .image(let cg):
                        base64 = try ImageEncoder.jpegBase64(cg, longEdge: maxImageLongEdge)
                    }
                    let messages = PromptBuilder.messages(source: source, target: target, base64: base64)
                    let body = try buildBody(messages: messages)
                    var req = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = body

                    let (bytes, response): (URLSession.AsyncBytes, URLResponse)
                    do {
                        (bytes, response) = try await session.bytes(for: req)
                    } catch let err as URLError where Self.isUnreachable(err) {
                        throw TranslationError.serverUnreachable
                    }
                    guard let http = response as? HTTPURLResponse else {
                        throw TranslationError.malformedResponse(detail: "no HTTPURLResponse")
                    }
                    if http.statusCode == 404 {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line }
                        if bodyText.contains("not found") {
                            throw TranslationError.modelNotFound(name: model)
                        }
                        throw TranslationError.httpStatus(code: 404, body: bodyText)
                    }
                    if http.statusCode >= 400 {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line }
                        throw TranslationError.httpStatus(code: http.statusCode, body: bodyText)
                    }

                    var parser = StreamParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw TranslationError.cancelled }
                        let tokens = try parser.feed(line + "\n")
                        for t in tokens { continuation.yield(t) }
                        if parser.isDone { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildBody(messages: BuiltMessages) throws -> Data {
        var user: [String: Any] = ["role": "user", "content": messages.userContent]
        if let images = messages.images { user["images"] = images }
        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "keep_alive": keepAlive,
            "options": ["temperature": temperature],
            "messages": [
                ["role": "system", "content": messages.system],
                user
            ]
        ]
        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw TranslationError.malformedResponse(detail: "request body JSON encoding failed: \(error.localizedDescription)")
        }
    }

    /// URL errors that mean "Ollama isn't reachable at `baseURL`." Any of these
    /// map to `TranslationError.serverUnreachable` so the UI can show the
    /// "start Ollama" hint instead of a generic network failure.
    private static func isUnreachable(_ err: URLError) -> Bool {
        switch err.code {
        case .cannotConnectToHost,
             .cannotFindHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .dnsLookupFailed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}
