import SwiftUI
import AppKit

struct OnboardingView: View {
    @State private var screenGranted = ScreenPermission.isGranted
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenPendingRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lumo 권한 설정").font(.title2).bold()
            Text("Lumo는 화면 영역을 캡처하고 전역 단축키를 관찰하기 위해 두 가지 권한이 필요합니다.")
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                title: "화면 기록 (Screen Recording)",
                detail: screenPendingRestart
                    ? "권한이 허용되었습니다. 앱을 재시작하면 적용됩니다."
                    : "⌘⇧1로 영역을 캡처하는 데 필요합니다.",
                granted: screenGranted,
                pendingRestart: screenPendingRestart,
                action: {
                    ScreenPermission.request()
                    ScreenPermission.openSystemSettings()
                }
            )

            permissionRow(
                title: "손쉬운 사용 (Accessibility)",
                detail: "⌘C 두 번 누름을 감지하는 데 필요합니다.",
                granted: accessibilityGranted,
                pendingRestart: false,
                action: {
                    let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                }
            )

            if screenGranted && accessibilityGranted {
                Label("모든 권한이 허용되었습니다.", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
            }

            HStack {
                if screenPendingRestart {
                    Button("재시작") { restartApp() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                Button("완료") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { refresh() }
        // 사용자가 시스템 설정에서 권한 부여 후 앱으로 돌아올 때 자동 새로고침
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let wasGranted = screenGranted
            refresh()
            // Screen Recording은 이미 허용됐지만 앱 재시작 전까지는 false를 반환할 수 있음
            if !wasGranted && !screenGranted {
                // CGPreflightScreenCaptureAccess가 false여도 실제로 허용됐을 수 있음 — pendingRestart 상태로 전환
                screenPendingRestart = CGRequestScreenCaptureAccess()
            }
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        pendingRestart: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : (pendingRestart ? "arrow.clockwise.circle.fill" : "circle"))
                .foregroundColor(granted ? .green : (pendingRestart ? .orange : .secondary))
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundColor(pendingRestart ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted && !pendingRestart {
                Button("시스템 설정 열기") { action() }
            }
        }
    }

    private func refresh() {
        screenGranted = ScreenPermission.isGranted
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [url.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

@MainActor
enum OnboardingWindow {
    static func showIfNeeded() {
        if ScreenPermission.isGranted && AXIsProcessTrusted() { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
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
