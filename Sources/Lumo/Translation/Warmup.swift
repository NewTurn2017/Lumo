import Foundation

enum WarmupResult: Equatable {
    case healthy
    case warning(String)
}

enum Warmup {
    static func run(
        baseURL: URL,
        model: String,
        keepAlive: String,
        session: URLSession = .shared
    ) async -> WarmupResult {
        var req = URLRequest(url: baseURL.appendingPathComponent("/api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "keep_alive": keepAlive,
            "messages": [[String: String]]()
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .warning("잘못된 응답")
            }
            if http.statusCode == 200 { return .healthy }
            if http.statusCode == 404,
               let body = String(data: data, encoding: .utf8),
               body.contains("not found") {
                return .warning("model `\(model)` not pulled")
            }
            return .warning("HTTP \(http.statusCode)")
        } catch let err as URLError
            where err.code == .cannotConnectToHost
               || err.code == .cannotFindHost
               || err.code == .networkConnectionLost {
            return .warning("Ollama 서버에 연결할 수 없음")
        } catch {
            return .warning(error.localizedDescription)
        }
    }
}
