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

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render()
        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "설정...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Lumo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
