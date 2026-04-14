import SwiftUI
import AppKit

@main
struct LumoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(delegate.mlxServerManager)
                .onAppear {
                    // Settings 가 열릴 때는 앱을 일반 앱처럼 취급해서
                    // 상단 메뉴바에 "Lumo" 가 노출되도록 한다.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear {
                    // Settings 가 닫히면 다시 메뉴바 전용으로 복귀.
                    NSApp.setActivationPolicy(.accessory)
                }
        }
    }
}
