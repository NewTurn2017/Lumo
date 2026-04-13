import XCTest
@testable import Lumo

final class HistoryStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "lumo.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func test_appendThenRead() {
        let d = makeDefaults()
        let store = HistoryStore(defaults: d)
        store.append(HistoryEntry(timestamp: Date(timeIntervalSince1970: 1), preview: "안녕", full: "안녕 세상", source: .text))
        XCTAssertEqual(store.recent.count, 1)
        XCTAssertEqual(store.recent.first?.full, "안녕 세상")
    }

    func test_trimsToTen() {
        let d = makeDefaults()
        let store = HistoryStore(defaults: d)
        for i in 0..<15 {
            store.append(HistoryEntry(
                timestamp: Date(timeIntervalSince1970: TimeInterval(i)),
                preview: "p\(i)", full: "f\(i)", source: .text
            ))
        }
        XCTAssertEqual(store.recent.count, 10)
        XCTAssertEqual(store.recent.first?.full, "f5")
        XCTAssertEqual(store.recent.last?.full, "f14")
    }

    func test_persistsAcrossInstances() {
        let d = makeDefaults()
        do {
            let a = HistoryStore(defaults: d)
            a.append(HistoryEntry(timestamp: Date(timeIntervalSince1970: 1), preview: "p", full: "f", source: .image))
        }
        let b = HistoryStore(defaults: d)
        XCTAssertEqual(b.recent.count, 1)
        XCTAssertEqual(b.recent.first?.source, .image)
    }
}
