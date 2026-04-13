import Foundation
import CoreGraphics
import AppKit

protocol PopupPresenting: AnyObject {
    func showLoading()
    func append(_ chunk: String)
    func showDone(finalText: String)
    func showError(_ message: String)
    func close()
}

@MainActor
final class TranslationOrchestrator {
    private let capture: CaptureService
    private let translator: Translator
    private let clipboard: Clipboard
    private let presenter: PopupPresenting
    private let history: HistoryStore

    private var currentTask: Task<Void, Never>?
    private var lastOriginalClipboard: String?

    init(
        capture: CaptureService,
        translator: Translator,
        clipboard: Clipboard,
        presenter: PopupPresenting,
        history: HistoryStore
    ) {
        self.capture = capture
        self.translator = translator
        self.clipboard = clipboard
        self.presenter = presenter
        self.history = history
    }

    func runCapture() async {
        cancelCurrent()
        let task = Task { await self._runCapture() }
        currentTask = task
        await task.value
    }

    func runText() async {
        cancelCurrent()
        let task = Task { await self._runText() }
        currentTask = task
        await task.value
    }

    func restoreOriginalClipboard() {
        if let s = lastOriginalClipboard { clipboard.setString(s) }
    }

    private func cancelCurrent() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func _runCapture() async {
        // showLoading is intentionally called AFTER captureRegion so the popup
        // window does not steal key-window status from the capture overlay.
        let image: CGImage
        do {
            image = try await capture.captureRegion()
        } catch is CancellationError {
            return  // User cancelled overlay — nothing to dismiss
        } catch {
            presenter.showError("캡처 실패: \(error.localizedDescription)")
            return
        }
        NSSound(named: "Pop")?.play()
        presenter.showLoading()
        await runStream(source: .image(image), target: .korean, recordSource: .image)
    }

    private func _runText() async {
        guard let text = clipboard.string(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            presenter.showError("복사된 텍스트가 없습니다")
            return
        }
        lastOriginalClipboard = text
        let target: TargetLanguage = LanguageDetector.isKorean(text) ? .english : .korean
        NSSound(named: "Pop")?.play()
        presenter.showLoading()
        await runStream(source: .text(text), target: target, recordSource: .text)
    }

    private func runStream(source: TranslationSource, target: TargetLanguage, recordSource: HistoryEntry.Source) async {
        var buffer = ""
        do {
            for try await chunk in translator.translate(source: source, target: target) {
                buffer += chunk
                presenter.append(chunk)
            }
        } catch TranslationError.serverUnreachable {
            presenter.showError("Ollama 서버에 연결할 수 없음")
            return
        } catch TranslationError.modelNotFound(let name) {
            presenter.showError("모델 없음: \(name)")
            return
        } catch TranslationError.firstTokenTimeout {
            presenter.showError("응답 시작 시간 초과")
            return
        } catch TranslationError.idleTimeout {
            presenter.showError("스트림 중단 (idle timeout)")
            return
        } catch TranslationError.hardTimeout {
            presenter.showError("총 시간 초과")
            return
        } catch is CancellationError {
            presenter.close()
            return
        } catch {
            presenter.showError(error.localizedDescription)
            return
        }
        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(텍스트 없음)" {
            presenter.showError("(텍스트 없음)")
            return
        }
        clipboard.setString(trimmed)
        history.append(HistoryEntry(
            timestamp: Date(),
            preview: String(trimmed.prefix(40)),
            full: trimmed,
            source: recordSource
        ))
        presenter.showDone(finalText: trimmed)
    }
}
