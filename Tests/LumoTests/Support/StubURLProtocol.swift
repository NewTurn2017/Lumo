import Foundation

/// A URLProtocol stub that lets tests script NDJSON responses chunk-by-chunk.
/// Install via URLSessionConfiguration.protocolClasses before constructing the session.
///
/// Concurrency notes:
/// - `handler` is shared mutable state protected only by the convention that tests
///   set it before kicking off a request and reset it in `setUp`/`tearDown`.
/// - Each loading Task is owned by its protocol instance and cancelled in
///   `stopLoading()`, so cancelled requests never race against a freed client.
/// - `capturedBody` is a convenience slot for tests that need to inspect the
///   request body written by a streaming upload. Reset it in `setUp`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var statusCode: Int
        var chunks: [String]          // string chunks sent sequentially
        var chunkDelayMs: Int         // delay between chunks
        var error: Error?             // if non-nil, overrides chunks
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Response)?
    nonisolated(unsafe) static var capturedBody: Data?

    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.capturedBody = request.httpBody ?? Self.readBodyStream(request)

        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let response = handler(request)
        if let err = response.error {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/x-ndjson"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        loadingTask = Task { [weak self] in
            for chunk in response.chunks {
                if Task.isCancelled { return }
                if response.chunkDelayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(response.chunkDelayMs))
                }
                guard let self, !Task.isCancelled else { return }
                self.client?.urlProtocol(self, didLoad: Data(chunk.utf8))
            }
            guard let self, !Task.isCancelled else { return }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    /// Drain the streaming upload body that URLSession may synthesize from a
    /// `Data` payload. Used by tests that need to inspect the exact bytes
    /// posted by the translator.
    static func readBodyStream(_ req: URLRequest) -> Data? {
        guard let stream = req.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: 4096)
            if n > 0 { data.append(buf, count: n) } else { break }
        }
        return data
    }
}
