import XCTest
@testable import Lumo

final class TimeoutWatchdogTests: XCTestCase {
    func test_happyPath_forwardsAllTokens() async throws {
        let upstream = AsyncThrowingStream<String, Error> { c in
            Task {
                c.yield("안")
                c.yield("녕")
                c.finish()
            }
        }
        let wrapped = Watchdog.wrap(upstream, firstToken: .seconds(5), idle: .seconds(5), hard: .seconds(10))
        var out: [String] = []
        for try await t in wrapped { out.append(t) }
        XCTAssertEqual(out, ["안", "녕"])
    }

    func test_firstTokenTimeout_firesWhenNoInitialToken() async {
        let upstream = AsyncThrowingStream<String, Error> { _ in
            // never yield
        }
        let wrapped = Watchdog.wrap(
            upstream,
            firstToken: .milliseconds(100),
            idle: .seconds(10),
            hard: .seconds(10)
        )
        do {
            for try await _ in wrapped { XCTFail("unexpected token") }
            XCTFail("expected throw")
        } catch TranslationError.firstTokenTimeout {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_idleTimeout_firesAfterFirstTokenStall() async {
        let upstream = AsyncThrowingStream<String, Error> { c in
            Task {
                c.yield("안")
                // never finish, never yield again
            }
        }
        let wrapped = Watchdog.wrap(
            upstream,
            firstToken: .seconds(10),
            idle: .milliseconds(150),
            hard: .seconds(10)
        )
        var received: [String] = []
        do {
            for try await t in wrapped { received.append(t) }
            XCTFail("expected throw")
        } catch TranslationError.idleTimeout {
            XCTAssertEqual(received, ["안"])
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func test_hardTimeout_firesEvenWithOngoingTokens() async {
        let upstream = AsyncThrowingStream<String, Error> { c in
            Task {
                for _ in 0..<1000 {
                    try? await Task.sleep(for: .milliseconds(50))
                    c.yield("x")
                }
            }
        }
        let wrapped = Watchdog.wrap(
            upstream,
            firstToken: .seconds(5),
            idle: .seconds(5),
            hard: .milliseconds(300)
        )
        do {
            for try await _ in wrapped {}
            XCTFail("expected throw")
        } catch TranslationError.hardTimeout {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
