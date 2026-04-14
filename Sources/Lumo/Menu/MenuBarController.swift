import AppKit

enum MenuBarState: Equatable {
    case idle
    case busy
    case warning(String)
    case error(String)
}

enum MenuBarEvent {
    case beganTranslation
    case finishedSuccessfully
    case failed(String)
    case warningRaised(String)
    case warningCleared
}

extension MenuBarState {
    func reduce(_ event: MenuBarEvent) -> MenuBarState {
        switch event {
        case .beganTranslation: return .busy
        case .finishedSuccessfully: return .idle
        case .failed(let msg): return .error(msg)
        case .warningRaised(let msg): return .warning(msg)
        case .warningCleared: return .idle
        }
    }
}

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private(set) var state: MenuBarState = .idle {
        didSet { render() }
    }

    /// AppDelegate가 Sparkle updater와 연결하기 위해 주입하는 콜백
    var onCheckForUpdates: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render()
        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let updateItem = NSMenuItem(title: "업데이트 확인...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "설정...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Lumo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func openSettings() {
        // Accessory 앱은 클릭 시점에 active 가 아니라서 responder chain 이 비어
        // sendAction 이 조용히 실패한다. 먼저 .regular 로 승격 + activate 한 뒤
        // 다음 runloop 에서 SwiftUI Settings 씬의 showSettingsWindow: 를 전송해야
        // 응답이 온다.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func send(_ event: MenuBarEvent) {
        state = state.reduce(event)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
        button.image?.isTemplate = true
        button.toolTip = nil

        switch state {
        case .idle:
            button.appearsDisabled = false
        case .busy:
            button.appearsDisabled = false
        case .warning(let msg):
            button.toolTip = msg
        case .error(let msg):
            button.appearsDisabled = true
            button.toolTip = msg
        }
    }
}
