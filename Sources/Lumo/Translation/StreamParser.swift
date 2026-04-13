import Foundation

/// Stateful parser for Ollama's NDJSON chat stream.
/// - Buffers partial UTF-8 lines across `feed` calls.
/// - Drops `<think>...</think>` blocks even when the tag bytes are split across
///   multiple JSON `content` values.
/// - Exposes `isDone` when a line with `done: true` has been observed.
struct StreamParser {
    private(set) var isDone = false
    private var lineBuffer = ""
    private var inThinkBlock = false
    private var filterBuffer = ""

    mutating func feed(_ chunk: String) throws -> [String] {
        lineBuffer += chunk
        var results: [String] = []
        while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newlineIdx])
            lineBuffer.removeSubrange(...newlineIdx)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw TranslationError.malformedResponse(detail: line)
            }
            if let done = obj["done"] as? Bool, done {
                isDone = true
            }
            if let message = obj["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.isEmpty {
                if let filtered = filter(content), !filtered.isEmpty {
                    results.append(filtered)
                }
            }
        }
        return results
    }

    /// Remove `<think>...</think>` blocks including tag bytes split across calls.
    /// Maintains a single `filterBuffer` so a partial tag like `<thi` in one call
    /// is re-joined with `nk>...` in the next call before being detected.
    private mutating func filter(_ content: String) -> String? {
        filterBuffer += content
        var out = ""
        var i = filterBuffer.startIndex
        while i < filterBuffer.endIndex {
            if inThinkBlock {
                if let end = filterBuffer.range(of: "</think>", range: i..<filterBuffer.endIndex) {
                    inThinkBlock = false
                    i = end.upperBound
                } else {
                    // No complete `</think>` yet. Discard everything up to (but not
                    // including) a possible partial tail and wait for more input.
                    let tail = Self.longestTagPrefixSuffix(
                        of: "</think>",
                        in: filterBuffer[i..<filterBuffer.endIndex]
                    )
                    filterBuffer = String(tail)
                    return out.isEmpty ? nil : out
                }
            } else {
                if let start = filterBuffer.range(of: "<think>", range: i..<filterBuffer.endIndex) {
                    out.append(contentsOf: filterBuffer[i..<start.lowerBound])
                    inThinkBlock = true
                    i = start.upperBound
                } else {
                    // Emit everything except the longest suffix that could still be
                    // the opening of a `<think>` tag; keep that suffix in the buffer.
                    let remainder = filterBuffer[i..<filterBuffer.endIndex]
                    let tail = Self.longestTagPrefixSuffix(of: "<think>", in: remainder)
                    let safeEnd = filterBuffer.index(filterBuffer.endIndex, offsetBy: -tail.count)
                    out.append(contentsOf: filterBuffer[i..<safeEnd])
                    filterBuffer = String(tail)
                    return out.isEmpty ? nil : out
                }
            }
        }
        filterBuffer = ""
        return out.isEmpty ? nil : out
    }

    /// Longest suffix of `s` that equals a proper prefix of `tag` (length ≥ 1,
    /// strictly less than the tag itself). Returns an empty substring if none.
    private static func longestTagPrefixSuffix(of tag: String, in s: Substring) -> Substring {
        let maxK = min(s.count, tag.count - 1)
        if maxK <= 0 { return s.suffix(0) }
        for k in stride(from: maxK, through: 1, by: -1) {
            if s.suffix(k) == Substring(tag.prefix(k)) {
                return s.suffix(k)
            }
        }
        return s.suffix(0)
    }
}
