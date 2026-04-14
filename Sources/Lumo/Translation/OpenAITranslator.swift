import Foundation
import CoreGraphics

/// Translator that speaks the OpenAI-compatible `/v1/chat/completions` SSE protocol.
/// Used with the MLX server (`mlx_lm.server`) instead of Ollama.
final class OpenAITranslator: Translator {
    private let baseURL: URL
    private let model: String
    private let temperature: Double
    private let session: URLSession
    private let maxImageLongEdge: Int

    init(
        baseURL: URL,
        model: String,
        temperature: Double,
        session: URLSession = .shared,
        maxImageLongEdge: Int = 1280
    ) {
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
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
                    let body = try buildBody(messages: messages, base64: base64)
                    var req = URLRequest(url: baseURL.appending(path: "v1/chat/completions"))
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
                    if http.statusCode >= 400 {
                        var bodyText = ""
                        for try await line in bytes.lines { bodyText += line }
                        throw TranslationError.httpStatus(code: http.statusCode, body: bodyText)
                    }

                    var filter = InlineThinkFilter()
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw TranslationError.cancelled }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = obj["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let content = delta["content"] as? String,
                              !content.isEmpty else { continue }
                        if let filtered = filter.feed(content), !filtered.isEmpty {
                            continuation.yield(filtered)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildBody(messages: BuiltMessages, base64: String?) throws -> Data {
        let userContent: Any
        if let b64 = base64 {
            userContent = [
                ["type": "text", "text": messages.userContent],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]]
            ]
        } else {
            userContent = messages.userContent
        }
        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": messages.system],
                ["role": "user", "content": userContent]
            ]
        ]
        do {
            return try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw TranslationError.malformedResponse(
                detail: "request body JSON encoding failed: \(error.localizedDescription)")
        }
    }

    private static func isUnreachable(_ err: URLError) -> Bool {
        switch err.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .notConnectedToInternet, .timedOut, .dnsLookupFailed, .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

/// Stateful `<think>...</think>` block filter for streaming text.
/// Mirrors the logic in `StreamParser` for use in non-NDJSON contexts.
private struct InlineThinkFilter {
    private var inThinkBlock = false
    private var buffer = ""

    mutating func feed(_ content: String) -> String? {
        buffer += content
        var out = ""
        var i = buffer.startIndex
        while i < buffer.endIndex {
            if inThinkBlock {
                if let end = buffer.range(of: "</think>", range: i..<buffer.endIndex) {
                    inThinkBlock = false
                    i = end.upperBound
                } else {
                    let tail = longestTagPrefixSuffix(of: "</think>", in: buffer[i..<buffer.endIndex])
                    buffer = String(tail)
                    return out.isEmpty ? nil : out
                }
            } else {
                if let start = buffer.range(of: "<think>", range: i..<buffer.endIndex) {
                    out.append(contentsOf: buffer[i..<start.lowerBound])
                    inThinkBlock = true
                    i = start.upperBound
                } else {
                    let remainder = buffer[i..<buffer.endIndex]
                    let tail = longestTagPrefixSuffix(of: "<think>", in: remainder)
                    let safeEnd = buffer.index(buffer.endIndex, offsetBy: -tail.count)
                    out.append(contentsOf: buffer[i..<safeEnd])
                    buffer = String(tail)
                    return out.isEmpty ? nil : out
                }
            }
        }
        buffer = ""
        return out.isEmpty ? nil : out
    }

    private func longestTagPrefixSuffix(of tag: String, in s: Substring) -> Substring {
        let maxK = min(s.count, tag.count - 1)
        if maxK <= 0 { return s.suffix(0) }
        for k in stride(from: maxK, through: 1, by: -1) {
            if s.suffix(k) == Substring(tag.prefix(k)) { return s.suffix(k) }
        }
        return s.suffix(0)
    }
}
