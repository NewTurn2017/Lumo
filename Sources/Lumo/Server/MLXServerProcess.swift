import Foundation

/// Low-level subprocess + readiness-probe helpers for the MLX server.
/// Stateless — all functions take every dependency they need.
enum MLXServerProcess {
    /// Polls `GET <baseURL>/v1/models` until a 200 is returned or `timeout` elapses.
    /// Returns true on success, false on timeout.
    /// At least one probe is always issued, even when `timeout` is `.zero`.
    static func waitForReady(
        baseURL: URL,
        session: URLSession = .shared,
        pollInterval: Duration = .seconds(2),
        timeout: Duration = .seconds(60)
    ) async -> Bool {
        let probe = baseURL.appendingPathComponent("v1").appendingPathComponent("models")
        let deadline = ContinuousClock.now + timeout
        let probeTimeout = min(Self.seconds(pollInterval), 3.0)
        repeat {
            if await probeOnce(url: probe, session: session, probeTimeout: probeTimeout) {
                return true
            }
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero { return false }
            // Clamp sleep so we don't overshoot the deadline. `remaining` is
            // guaranteed > .zero here.
            try? await Task.sleep(for: min(pollInterval, remaining))
        } while ContinuousClock.now < deadline
        return false
    }

    /// Converts a `Duration` to seconds as a `Double`.
    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private static func probeOnce(url: URL, session: URLSession, probeTimeout: TimeInterval) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = probeTimeout
        do {
            let (_, response) = try await session.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
