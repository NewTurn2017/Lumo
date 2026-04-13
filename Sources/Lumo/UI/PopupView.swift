import SwiftUI

@MainActor
final class PopupModel: ObservableObject {
    enum Phase { case loading, streaming, done, error }
    @Published var phase: Phase = .loading
    @Published var text: String = ""
    @Published var errorMessage: String = ""
    @Published var canRestore: Bool = false
    var onRestore: (() -> Void)?
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                headerIcon
                Text(headerText).font(.headline)
                Spacer()
                Button(action: { model.onClose?() }) {
                    Image(systemName: "xmark.circle.fill")
                }.buttonStyle(.borderless)
            }
            ScrollView {
                Text(displayText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            if model.phase == .done {
                HStack {
                    Button("복사") { model.onCopy?() }
                    if model.canRestore {
                        Button("원문 복원") { model.onRestore?() }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 380)
        .background(.ultraThinMaterial)
    }

    private var headerIcon: some View {
        Group {
            switch model.phase {
            case .loading: ProgressView().controlSize(.small)
            case .streaming: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            }
        }
    }

    private var headerText: String {
        switch model.phase {
        case .loading: return "번역 중..."
        case .streaming: return "번역 중..."
        case .done: return "클립보드에 복사됨"
        case .error: return "오류"
        }
    }

    private var displayText: String {
        switch model.phase {
        case .error: return model.errorMessage
        default: return model.text
        }
    }
}
