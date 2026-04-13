import XCTest
@testable import Lumo

final class LoggerTests: XCTestCase {
    func test_latencySample_accumulates_inOrder() {
        let store = LatencyStore(capacity: 3)
        store.record(LatencySample(capture: 10, encode: 20, firstToken: 30, total: 40))
        store.record(LatencySample(capture: 11, encode: 21, firstToken: 31, total: 41))
        store.record(LatencySample(capture: 12, encode: 22, firstToken: 32, total: 42))
        store.record(LatencySample(capture: 13, encode: 23, firstToken: 33, total: 43))
        XCTAssertEqual(store.recent.count, 3)
        XCTAssertEqual(store.recent.map { $0.capture }, [11, 12, 13])
    }
}
