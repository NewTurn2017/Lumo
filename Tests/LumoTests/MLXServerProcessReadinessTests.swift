import XCTest
@testable import Lumo

final class MLXServerProcessReadinessTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.capturedBody = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.capturedBody = nil
        super.tearDown()
    }

    private func stubbedSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    // MARK: - Tests

    func test_waitForReady_returnsTrue_onFirst200() async {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(statusCode: 200, chunks: [""], chunkDelayMs: 0, error: nil)
        }
        let ready = await MLXServerProcess.waitForReady(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            session: stubbedSession(),
            pollInterval: .milliseconds(10),
            timeout: .seconds(1)
        )
        XCTAssertTrue(ready)
    }

    func test_waitForReady_returnsFalse_onTimeout() async {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(statusCode: 503, chunks: [""], chunkDelayMs: 0, error: nil)
        }
        let ready = await MLXServerProcess.waitForReady(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            session: stubbedSession(),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(100)
        )
        XCTAssertFalse(ready)
    }

    func test_waitForReady_retriesUntilSuccess() async {
        // Use a reference type so the closure can mutate shared state.
        final class Counter { var value = 0 }
        let counter = Counter()

        // Return 503 for the first two calls, then 200.
        StubURLProtocol.handler = { _ in
            let status: Int
            if counter.value < 2 {
                status = 503
            } else {
                status = 200
            }
            counter.value += 1
            return StubURLProtocol.Response(statusCode: status, chunks: [""], chunkDelayMs: 0, error: nil)
        }

        let ready = await MLXServerProcess.waitForReady(
            baseURL: URL(string: "http://127.0.0.1:8080")!,
            session: stubbedSession(),
            pollInterval: .milliseconds(10),
            timeout: .seconds(1)
        )
        XCTAssertTrue(ready)
        XCTAssertGreaterThanOrEqual(counter.value, 3, "Should have probed at least 3 times (2×503 + 1×200)")
    }
}
