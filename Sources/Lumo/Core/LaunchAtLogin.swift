import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("LaunchAtLogin toggle failed: \(error.localizedDescription)")
        }
    }
}
