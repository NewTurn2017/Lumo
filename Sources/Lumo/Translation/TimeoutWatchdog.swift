import Foundation

enum Watchdog {
    static func wrap(
        _ upstream: AsyncThrowingStream<String, Error>,
        firstToken: Duration,
        idle: Duration,
        hard: Duration
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let state = WatchdogState()
            let forwarder = Task {
                do {
                    for try await token in upstream {
                        await state.noteToken()
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let ticker = Task {
                let start = ContinuousClock.now
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    let now = ContinuousClock.now
                    let snap = await state.snapshot()
                    if !snap.sawFirstToken, now - start > firstToken {
                        forwarder.cancel()
                        continuation.finish(throwing: TranslationError.firstTokenTimeout)
                        return
                    }
                    if let last = snap.lastTokenAt, now - last > idle {
                        forwarder.cancel()
                        continuation.finish(throwing: TranslationError.idleTimeout)
                        return
                    }
                    if now - start > hard {
                        forwarder.cancel()
                        continuation.finish(throwing: TranslationError.hardTimeout)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                forwarder.cancel()
                ticker.cancel()
            }
        }
    }
}

private actor WatchdogState {
    private var sawFirstToken = false
    private var lastTokenAt: ContinuousClock.Instant?

    struct Snapshot {
        var sawFirstToken: Bool
        var lastTokenAt: ContinuousClock.Instant?
    }

    func noteToken() {
        sawFirstToken = true
        lastTokenAt = ContinuousClock.now
    }

    func snapshot() -> Snapshot {
        Snapshot(sawFirstToken: sawFirstToken, lastTokenAt: lastTokenAt)
    }
}
