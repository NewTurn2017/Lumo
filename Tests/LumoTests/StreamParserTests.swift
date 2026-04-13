import XCTest
@testable import Lumo

final class StreamParserTests: XCTestCase {
    func test_singleCompleteLine_emitsContent() throws {
        var parser = StreamParser()
        let emitted = try parser.feed(#"{"message":{"content":"안녕"},"done":false}"# + "\n")
        XCTAssertEqual(emitted, ["안녕"])
    }

    func test_chunkSplitAcrossLines_buffersUntilNewline() throws {
        var parser = StreamParser()
        var all: [String] = []
        all += try parser.feed(#"{"message":{"content":"안"},"done":false}"# + "\n")
        all += try parser.feed(#"{"message":{"cont"#)
        all += try parser.feed(#"ent":"녕"},"done":false}"# + "\n")
        XCTAssertEqual(all, ["안", "녕"])
    }

    func test_thinkBlock_filteredOut() throws {
        var parser = StreamParser()
        var all: [String] = []
        all += try parser.feed(#"{"message":{"content":"<think>"},"done":false}"# + "\n")
        all += try parser.feed(#"{"message":{"content":"reasoning..."},"done":false}"# + "\n")
        all += try parser.feed(#"{"message":{"content":"</think>"},"done":false}"# + "\n")
        all += try parser.feed(#"{"message":{"content":"안녕"},"done":false}"# + "\n")
        XCTAssertEqual(all, ["안녕"])
    }

    func test_thinkBlockSplitAcrossChunks_stillFiltered() throws {
        var parser = StreamParser()
        var all: [String] = []
        all += try parser.feed(#"{"message":{"content":"<thi"},"done":false}"# + "\n")
        all += try parser.feed(#"{"message":{"content":"nk>hidden</thi"},"done":false}"# + "\n")
        all += try parser.feed(#"{"message":{"content":"nk>안녕"},"done":false}"# + "\n")
        XCTAssertEqual(all.joined(), "안녕")
    }

    func test_doneLine_signalsCompletion() throws {
        var parser = StreamParser()
        _ = try parser.feed(#"{"message":{"content":"안녕"},"done":false}"# + "\n")
        _ = try parser.feed(#"{"message":{"content":""},"done":true}"# + "\n")
        XCTAssertTrue(parser.isDone)
    }

    func test_malformedLine_throws() {
        var parser = StreamParser()
        XCTAssertThrowsError(try parser.feed("not json\n"))
    }

    func test_emptyContent_isDropped() throws {
        var parser = StreamParser()
        let emitted = try parser.feed(#"{"message":{"content":""},"done":false}"# + "\n")
        XCTAssertEqual(emitted, [])
    }
}
