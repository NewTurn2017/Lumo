import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let mlxServerManager: MLXServerManager

    private var menu: MenuBarController!
    private var orchestrator: TranslationOrchestrator!
    private var hotkey: HotkeyManager!
    private var doubleCopy: DoubleCopyMonitor!
    private var popup: PopupWindow!
    private var clipboard: NSPasteboardClipboard!
    private var translator: (any Translator)!
    private var retryTask: Task<Void, Never>?

    override init() {
        // Manager is created eagerly so LumoApp.body can inject it into
        // the Settings scene via .environmentObject. Lifecycle start/stop
        // is driven from applicationDidFinishLaunching / applicationWillTerminate.
        self.mlxServerManager = MLXServerManager.live(
            modelID: SettingsSnapshot.load().model
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.terminateOtherInstances()
        let settings = SettingsSnapshot.load()
        if settings.backendType == "mlx" && settings.mlxServerEnabled {
            Task { [mlxServerManager] in await mlxServerManager.enable() }
        }
        menu = MenuBarController()
        popup = PopupWindow()
        clipboard = NSPasteboardClipboard()

        let defaultURL = settings.backendType == "mlx" ? "http://localhost:8080" : "http://localhost:11434"
        let baseURL = URL(string: settings.ollamaURL) ?? URL(string: defaultURL)!
        let session: URLSession = {
            let cfg = URLSessionConfiguration.default
            cfg.httpMaximumConnectionsPerHost = 1
            return URLSession(configuration: cfg)
        }()
        if settings.backendType == "mlx" {
            translator = OpenAITranslator(
                baseURL: baseURL,
                model: settings.model,
                temperature: settings.temperature,
                session: session,
                maxImageLongEdge: settings.maxImageLongEdge
            )
        } else {
            translator = OllamaTranslator(
                baseURL: baseURL,
                model: settings.model,
                temperature: settings.temperature,
                keepAlive: settings.keepAlive,
                session: session,
                maxImageLongEdge: settings.maxImageLongEdge
            )
        }
        let wrapped = WrappedTranslator(
            inner: translator,
            firstToken: .seconds(settings.firstTokenTimeoutSec),
            idle: .seconds(settings.idleTimeoutSec),
            hard: .seconds(settings.hardTimeoutSec)
        )

        let captureService: CaptureService = NativeScreenCapture()

        let presenter = MenuBarPresenter(popup: popup, menu: menu)
        orchestrator = TranslationOrchestrator(
            capture: captureService,
            recognizer: VisionTextRecognizer(),
            translator: wrapped,
            clipboard: clipboard,
            presenter: presenter,
            history: HistoryStore()
        )
        popup.onRestore = { [weak orchestrator] in orchestrator?.restoreOriginalClipboard() }
        popup.onCancel = { [weak orchestrator] in orchestrator?.cancelCurrent() }

        hotkey = HotkeyManager { [weak orchestrator] in
            Task { @MainActor in await orchestrator?.runCapture() }
        }
        hotkey.start()

        if settings.doubleCopyEnabled {
            doubleCopy = DoubleCopyMonitor(
                thresholdMs: settings.doubleCopyThresholdMs,
                clipboard: clipboard
            ) { [weak orchestrator] in
                Task { @MainActor in await orchestrator?.runText() }
            }
            doubleCopy.start()
        }

        OnboardingWindow.showIfNeeded()
        runWarmup(baseURL: baseURL, settings: settings, backendType: settings.backendType)
    }

    private func runWarmup(baseURL: URL, settings: SettingsSnapshot, backendType: String) {
        Task { @MainActor in
            let result = await Warmup.run(
                baseURL: baseURL,
                model: settings.model,
                keepAlive: settings.keepAlive,
                backendType: backendType
            )
            switch result {
            case .healthy:
                menu.send(.warningCleared)
            case .warning(let msg):
                menu.send(.warningRaised(msg))
                scheduleRetry(baseURL: baseURL, settings: settings)
            }
        }
    }

    /// Ensures only one Lumo status item exists: kills prior Xcode-launched instances
    /// that linger after rebuilds (LSUIElement apps aren't auto-terminated by Xcode).
    private static func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where app.processIdentifier != me {
            app.forceTerminate()
        }
    }

    private func scheduleRetry(baseURL: URL, settings: SettingsSnapshot) {
        retryTask?.cancel()
        retryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            runWarmup(baseURL: baseURL, settings: settings, backendType: settings.backendType)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mlxServerManager.shutdown()
    }
}

/// Routes PopupPresenting calls to both PopupWindow and MenuBarController.
@MainActor
private final class MenuBarPresenter: PopupPresenting {
    private let popup: PopupWindow
    private let menu: MenuBarController

    init(popup: PopupWindow, menu: MenuBarController) {
        self.popup = popup
        self.menu = menu
    }

    func showLoading() {
        menu.send(.beganTranslation)
        popup.showLoading()
    }
    func append(_ chunk: String) { popup.append(chunk) }
    func showDone(finalText: String) {
        menu.send(.finishedSuccessfully)
        popup.showDone(finalText: finalText)
    }
    func showError(_ message: String) {
        menu.send(.failed(message))
        popup.showError(message)
    }
    func close() {
        menu.send(.finishedSuccessfully)
        popup.close()
    }
}

/// Wraps an inner Translator with the timeout Watchdog.
final class WrappedTranslator: Translator {
    private let inner: Translator
    private let firstToken: Duration
    private let idle: Duration
    private let hard: Duration
    init(inner: Translator, firstToken: Duration, idle: Duration, hard: Duration) {
        self.inner = inner
        self.firstToken = firstToken
        self.idle = idle
        self.hard = hard
    }
    func translate(source: TranslationSource, target: TargetLanguage)
        -> AsyncThrowingStream<String, Error>
    {
        Watchdog.wrap(
            inner.translate(source: source, target: target),
            firstToken: firstToken,
            idle: idle,
            hard: hard
        )
    }
}
