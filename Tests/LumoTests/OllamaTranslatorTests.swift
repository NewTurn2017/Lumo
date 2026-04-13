import CoreGraphics
import XCTest
@testable import Lumo

final class OllamaTranslatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
        StubURLProtocol.capturedBody = nil
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    func test_textTranslation_streamsTokensInOrder() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(
                statusCode: 200,
                chunks: [
                    #"{"message":{"content":"안"},"done":false}"# + "\n",
                    #"{"message":{"content":"녕"},"done":false}"# + "\n",
                    #"{"message":{"content":""},"done":true}"# + "\n"
                ],
                chunkDelayMs: 0,
                error: nil
            )
        }
        let t = OllamaTranslator(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "gemma4:e4b",
            temperature: 0.2,
            keepAlive: "30m",
            session: makeSession()
        )
        var out: [String] = []
        for try await chunk in t.translate(source: .text("Hello"), target: .korean) {
            out.append(chunk)
        }
        XCTAssertEqual(out.joined(), "안녕")
    }

    func test_http404_throwsModelNotFound() async {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(
                statusCode: 404,
                chunks: [#"{"error":"model 'gemma4:e4b' not found"}"# + "\n"],
                chunkDelayMs: 0,
                error: nil
            )
        }
        let t = OllamaTranslator(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "gemma4:e4b",
            temperature: 0.2,
            keepAlive: "30m",
            session: makeSession()
        )
        do {
            for try await _ in t.translate(source: .text("Hello"), target: .korean) {}
            XCTFail("expected error")
        } catch TranslationError.modelNotFound(let name) {
            XCTAssertEqual(name, "gemma4:e4b")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_connectionRefused_throwsServerUnreachable() async {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(
                statusCode: 0, chunks: [], chunkDelayMs: 0,
                error: URLError(.cannotConnectToHost)
            )
        }
        let t = OllamaTranslator(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "gemma4:e4b",
            temperature: 0.2,
            keepAlive: "30m",
            session: makeSession()
        )
        do {
            for try await _ in t.translate(source: .text("Hello"), target: .korean) {}
            XCTFail("expected error")
        } catch TranslationError.serverUnreachable {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_imageTranslation_includesBase64AndStreams() async throws {
        StubURLProtocol.capturedBody = nil
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Response(
                statusCode: 200,
                chunks: [
                    #"{"message":{"content":"안녕"},"done":false}"# + "\n",
                    #"{"message":{"content":""},"done":true}"# + "\n"
                ],
                chunkDelayMs: 0,
                error: nil
            )
        }
        let cg = makeImage()
        let t = OllamaTranslator(
            baseURL: URL(string: "http://localhost:11434")!,
            model: "gemma4:e4b",
            temperature: 0.2,
            keepAlive: "30m",
            session: makeSession()
        )
        var out = ""
        for try await chunk in t.translate(source: .image(cg), target: .korean) {
            out += chunk
        }
        XCTAssertEqual(out, "안녕")
        let body = try XCTUnwrap(StubURLProtocol.capturedBody)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages.count, 2)
        let user = messages[1]
        let images = user["images"] as! [String]
        XCTAssertFalse(images[0].isEmpty)
    }

    private func makeImage() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 10, height: 10,
            bitsPerComponent: 8, bytesPerRow: 40,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
