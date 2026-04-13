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
    }

    func send(_ event: MenuBarEvent) {
        state = state.reduce(event)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        switch state {
        case .idle:              button.title = "Lumo"
        case .busy:              button.title = "Lumo ⟳"
        case .warning(let msg):  button.title = "Lumo ⚠"; button.toolTip = msg
        case .error(let msg):    button.title = "Lumo ✕"; button.toolTip = msg
        }
    }
}
