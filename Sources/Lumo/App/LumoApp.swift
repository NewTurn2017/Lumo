import SwiftUI

@main
struct LumoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(delegate.mlxServerManager)
        }
    }
}
