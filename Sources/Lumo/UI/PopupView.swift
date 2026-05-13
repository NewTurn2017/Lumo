import SwiftUI

/// User-selectable popup window dimensions. Stored as the raw string
/// in `SettingsKey.popupSize` so it round-trips through @AppStorage.
enum PopupSize: String, CaseIterable, Identifiable {
    case small, medium, large, xlarge

    var id: String { rawValue }

    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .small:  return (460, 320)
        case .medium: return (600, 440)
        case .large:  return (760, 560)
        case .xlarge: return (900, 660)
        }
    }

    var label: String {
        switch self {
        case .small:  return "작게"
        case .medium: return "보통"
        case .large:  return "크게"
        case .xlarge: return "아주 크게"
        }
    }

    static func resolve(_ raw: String?) -> PopupSize {
        PopupSize(rawValue: raw ?? "") ?? .medium
    }
}

@MainActor
final class PopupModel: ObservableObject {
    enum Phase { case loading, streaming, done, error }
    @Published var phase: Phase = .loading
    @Published var text: String = ""
    @Published var errorMessage: String = ""
    @Published var canRestore: Bool = false
    @Published var fontSize: CGFloat = 18
    @Published var isHovered: Bool = false
    var onRestore: (() -> Void)?
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
}

struct PopupView: View {
    @ObservedObject var model: PopupModel

    private let cornerRadius: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            Divider().opacity(0.4)

            ScrollView {
                Text(displayText)
                    .font(.system(size: model.fontSize))
                    .lineSpacing(model.fontSize * 0.25)
                    .foregroundStyle(model.phase == .error ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .frame(maxHeight: .infinity)

            if model.phase == .done {
                Divider().opacity(0.4)
                HStack(spacing: 8) {
                    Button("복사") { model.onCopy?() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    if model.canRestore {
                        Button("원문 복원") { model.onRestore?() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovered in
            model.isHovered = hovered
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            headerIcon
            Text(headerText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: { model.onClose?() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
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
