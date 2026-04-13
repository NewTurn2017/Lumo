import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @AppStorage(SettingsKey.ollamaURL)                 private var ollamaURL = "http://localhost:11434"
    @AppStorage(SettingsKey.model)                     private var model = "gemma4:e4b"
    @AppStorage(SettingsKey.keepAlive)                 private var keepAlive = "30m"
    @AppStorage(SettingsKey.maxImageLongEdge)          private var maxImageLongEdge = 1280
    @AppStorage(SettingsKey.temperature)               private var temperature = 0.2
    @AppStorage(SettingsKey.doubleCopyEnabled)         private var doubleCopyEnabled = true
    @AppStorage(SettingsKey.doubleCopyThresholdMs)     private var doubleCopyThresholdMs = 300
    @AppStorage(SettingsKey.overwriteClipboardOnDoubleCopy) private var overwrite = true
    @AppStorage(SettingsKey.launchAtLogin)             private var launchAtLogin = false
    @AppStorage(SettingsKey.firstTokenTimeoutSec)      private var firstTokenTimeoutSec = 20
    @AppStorage(SettingsKey.idleTimeoutSec)            private var idleTimeoutSec = 8
    @AppStorage(SettingsKey.hardTimeoutSec)            private var hardTimeoutSec = 120

    var body: some View {
        TabView {
            Form {
                TextField("Ollama URL", text: $ollamaURL)
                TextField("Model", text: $model)
                TextField("keep_alive", text: $keepAlive)
                Stepper("Max image long edge: \(maxImageLongEdge)px", value: $maxImageLongEdge, in: 480...1920, step: 160)
                Slider(value: $temperature, in: 0...1, step: 0.05) {
                    Text("Temperature: \(String(format: "%.2f", temperature))")
                }
                KeyboardShortcuts.Recorder("Capture hotkey", name: .captureAndTranslate)
            }
            .padding(20)
            .tabItem { Text("General") }

            Form {
                Toggle("Enable double ⌘C", isOn: $doubleCopyEnabled)
                Picker("Double-tap threshold", selection: $doubleCopyThresholdMs) {
                    Text("200 ms").tag(200)
                    Text("300 ms").tag(300)
                    Text("500 ms").tag(500)
                }
                Toggle("Overwrite clipboard with translation", isOn: $overwrite)
            }
            .padding(20)
            .tabItem { Text("Double Copy") }

            Form {
                Toggle("Launch at login", isOn: $launchAtLogin)
            }
            .padding(20)
            .tabItem { Text("Startup") }

            Form {
                Stepper("First-token timeout: \(firstTokenTimeoutSec)s", value: $firstTokenTimeoutSec, in: 5...60)
                Stepper("Idle timeout: \(idleTimeoutSec)s", value: $idleTimeoutSec, in: 2...30)
                Stepper("Hard timeout: \(hardTimeoutSec)s", value: $hardTimeoutSec, in: 10...600)
            }
            .padding(20)
            .tabItem { Text("Debug") }
        }
        .frame(width: 480, height: 360)
    }
}
