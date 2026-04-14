import XCTest
@testable import Lumo

final class WarmupTests: XCTestCase {
    func test_success_reportsHealthy() async {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(
                statusCode: 200,
                chunks: [#"{"done":true}"# + "\n"],
                chunkDelayMs: 0,
                error: nil
            )
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let result = await Warmup.run(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "gemma4:e4b",
            keepAlive: "30m",
            session: session
        )
        XCTAssertEqual(result, .healthy)
    }

    func test_modelNotFound_reportsWarning() async {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(
                statusCode: 404,
                chunks: [#"{"error":"model 'gemma4:e4b' not found"}"# + "\n"],
                chunkDelayMs: 0,
                error: nil
            )
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let result = await Warmup.run(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "gemma4:e4b",
            keepAlive: "30m",
            session: session
        )
        XCTAssertEqual(result, .warning("model `gemma4:e4b` not pulled"))
    }

    func test_connectionRefused_reportsWarning() async {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(
                statusCode: 0, chunks: [], chunkDelayMs: 0,
                error: URLError(.cannotConnectToHost)
            )
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let result = await Warmup.run(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "gemma4:e4b",
            keepAlive: "30m",
            session: session
        )
        XCTAssertEqual(result, .warning("서버에 연결할 수 없음"))
    }
}
