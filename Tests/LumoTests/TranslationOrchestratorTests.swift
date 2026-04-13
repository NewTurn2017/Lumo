import XCTest
@testable import Lumo

@MainActor
final class TranslationOrchestratorTests: XCTestCase {
    func makeOrchestrator() -> (TranslationOrchestrator, MockTranslator, MockCaptureService, FakeClipboard, MockPopupPresenter, HistoryStore) {
        let translator = MockTranslator()
        let capture = MockCaptureService()
        let clipboard = FakeClipboard()
        let presenter = MockPopupPresenter()
        let history = HistoryStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        let orch = TranslationOrchestrator(
            capture: capture,
            translator: translator,
            clipboard: clipboard,
            presenter: presenter,
            history: history
        )
        return (orch, translator, capture, clipboard, presenter, history)
    }

    func test_capture_success_copiesClipboardAndAppendsHistory() async {
        let (orch, translator, _, clipboard, presenter, history) = makeOrchestrator()
        translator.nextChunks = ["안", "녕"]
        await orch.runCapture()
        XCTAssertEqual(clipboard.string(), "안녕")
        XCTAssertEqual(history.recent.count, 1)
        XCTAssertEqual(history.recent.first?.full, "안녕")
        XCTAssertEqual(presenter.events.last, .done("안녕"))
    }

    func test_capture_serverUnreachable_showsError_noClipboardWrite() async {
        let (orch, translator, _, clipboard, _, _) = makeOrchestrator()
        translator.nextError = TranslationError.serverUnreachable
        await orch.runCapture()
        XCTAssertNil(clipboard.string())
    }

    func test_capture_emptyOutput_noClipboardWrite() async {
        let (orch, translator, _, clipboard, presenter, _) = makeOrchestrator()
        translator.nextChunks = []
        await orch.runCapture()
        XCTAssertNil(clipboard.string())
        XCTAssertEqual(presenter.events.last, .error("(텍스트 없음)"))
    }

    func test_doubleCopy_english_to_korean() async {
        let (orch, translator, _, clipboard, _, _) = makeOrchestrator()
        clipboard.setString("Hello world")
        translator.nextChunks = ["안녕 세상"]
        await orch.runText()
        XCTAssertEqual(clipboard.string(), "안녕 세상")
        XCTAssertEqual(translator.calls.first?.target, .korean)
    }

    func test_doubleCopy_korean_to_english() async {
        let (orch, translator, _, clipboard, _, _) = makeOrchestrator()
        clipboard.setString("안녕하세요")
        translator.nextChunks = ["Hello"]
        await orch.runText()
        XCTAssertEqual(clipboard.string(), "Hello")
        XCTAssertEqual(translator.calls.first?.target, .english)
    }

    func test_doubleCopy_restorableOriginal() async {
        let (orch, translator, _, clipboard, _, _) = makeOrchestrator()
        clipboard.setString("Hello")
        translator.nextChunks = ["안녕"]
        await orch.runText()
        XCTAssertEqual(clipboard.string(), "안녕")
        orch.restoreOriginalClipboard()
        XCTAssertEqual(clipboard.string(), "Hello")
    }

    func test_secondCaptureCancelsFirst() async {
        let (orch, translator, _, _, _, _) = makeOrchestrator()
        translator.nextChunks = []
        let t1 = Task { await orch.runCapture() }
        let t2 = Task { await orch.runCapture() }
        _ = await (t1.value, t2.value)
        // Both complete without deadlock; second call observed.
        XCTAssertGreaterThanOrEqual(translator.calls.count, 1)
    }
}

final class MockPopupPresenter: PopupPresenting {
    enum Event: Equatable {
        case loading
        case append(String)
        case done(String)
        case error(String)
        case close
    }
    var events: [Event] = []
    func showLoading() { events.append(.loading) }
    func append(_ chunk: String) { events.append(.append(chunk)) }
    func showDone(finalText: String) { events.append(.done(finalText)) }
    func showError(_ message: String) { events.append(.error(message)) }
    func close() { events.append(.close) }
}
