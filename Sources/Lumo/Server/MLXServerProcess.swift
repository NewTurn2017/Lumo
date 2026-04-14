import Foundation

/// Low-level subprocess + readiness-probe helpers for the MLX server.
/// Stateless — all functions take every dependency they need.
enum MLXServerProcess {
    /// Polls `GET <baseURL>/v1/models` until a 200 is returned or `timeout` elapses.
    /// Returns true on success, false on timeout.
    static func waitForReady(
        baseURL: URL,
        session: URLSession = .shared,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(60)
    ) async -> Bool {
        let probe = baseURL.appendingPathComponent("v1").appendingPathComponent("models")
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await probeOnce(url: probe, session: session) {
                return true
            }
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero { break }
            try? await Task.sleep(for: min(pollInterval, remaining))
        }
        return false
    }

    private static func probeOnce(url: URL, session: URLSession) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        do {
            let (_, response) = try await session.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
