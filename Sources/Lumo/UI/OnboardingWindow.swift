import SwiftUI
import AppKit

struct OnboardingView: View {
    @State private var screenGranted = ScreenPermission.isGranted
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lumo 권한 설정").font(.title2).bold()
            Text("Lumo는 화면 영역을 캡처하고 전역 단축키를 관찰하기 위해 두 가지 권한이 필요합니다.")
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                title: "화면 기록 (Screen Recording)",
                detail: "⌘⇧1로 영역을 캡처하는 데 필요합니다.",
                granted: screenGranted,
                action: {
                    ScreenPermission.request()
                    ScreenPermission.openSystemSettings()
                }
            )

            permissionRow(
                title: "손쉬운 사용 (Accessibility)",
                detail: "⌘C 두 번 누름을 감지하는 데 필요합니다.",
                granted: accessibilityGranted,
                action: {
                    let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                }
            )

            HStack {
                Spacer()
                Button("완료") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { refresh() }
    }

    @ViewBuilder
    private func permissionRow(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundColor(.secondary)
            }
            Spacer()
            if !granted {
                Button("허용") { action(); refresh() }
            }
        }
    }

    private func refresh() {
        screenGranted = ScreenPermission.isGranted
        accessibilityGranted = AXIsProcessTrusted()
    }
}

@MainActor
enum OnboardingWindow {
    static func showIfNeeded() {
        if ScreenPermission.isGranted && AXIsProcessTrusted() { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lumo 설정"
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
