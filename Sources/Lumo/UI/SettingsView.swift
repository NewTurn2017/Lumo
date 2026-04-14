import AppKit
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var mlxServerManager: MLXServerManager
    @AppStorage(SettingsKey.backendType)               private var backendType = "mlx"
    @AppStorage(SettingsKey.ollamaURL)                 private var ollamaURL = "http://localhost:8080"
    @AppStorage(SettingsKey.model)                     private var model = "mlx-community/gemma-4-e4b-it-4bit"
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
    @AppStorage(SettingsKey.popupSize)                 private var popupSize = "medium"

    var body: some View {
        TabView {
            GeneralTab(
                backendType: $backendType,
                ollamaURL: $ollamaURL,
                model: $model,
                keepAlive: $keepAlive,
                maxImageLongEdge: $maxImageLongEdge,
                temperature: $temperature,
                popupSize: $popupSize
            )
            .tabItem { Label("일반", systemImage: "gearshape") }

            DoubleCopyTab(
                doubleCopyEnabled: $doubleCopyEnabled,
                doubleCopyThresholdMs: $doubleCopyThresholdMs,
                overwrite: $overwrite
            )
            .tabItem { Label("복사 단축", systemImage: "doc.on.doc") }

            StartupTab(launchAtLogin: $launchAtLogin)
                .tabItem { Label("시작", systemImage: "power") }

            DebugTab(
                firstTokenTimeoutSec: $firstTokenTimeoutSec,
                idleTimeoutSec: $idleTimeoutSec,
                hardTimeoutSec: $hardTimeoutSec
            )
            .tabItem { Label("디버그", systemImage: "ladybug") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Binding var backendType: String
    @Binding var ollamaURL: String
    @Binding var model: String
    @Binding var keepAlive: String
    @Binding var maxImageLongEdge: Int
    @Binding var temperature: Double
    @Binding var popupSize: String

    var body: some View {
        Form {
            Section("백엔드") {
                Picker("종류", selection: $backendType) {
                    Text("MLX").tag("mlx")
                    Text("Ollama").tag("ollama")
                }
                .pickerStyle(.segmented)

                LabeledContent("서버 URL") {
                    TextField("", text: $ollamaURL, prompt: Text("http://localhost:8080"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                LabeledContent("모델") {
                    TextField("", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                if backendType == "ollama" {
                    LabeledContent("keep_alive") {
                        TextField("", text: $keepAlive)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                    }
                }
            }

            if backendType == "mlx" {
                Section("MLX 서버") {
                    MLXServerSection()
                }
            }

            Section("번역") {
                LabeledContent("Temperature") {
                    HStack(spacing: 8) {
                        Slider(value: $temperature, in: 0...1, step: 0.05)
                            .frame(maxWidth: 200)
                        Text(String(format: "%.2f", temperature))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                LabeledContent("이미지 최대 변") {
                    HStack(spacing: 6) {
                        Text("\(maxImageLongEdge)")
                            .font(.system(.body, design: .monospaced))
                        Text("px")
                            .foregroundColor(.secondary)
                        Stepper("", value: $maxImageLongEdge, in: 480...1920, step: 160)
                            .labelsHidden()
                    }
                }
                Picker("결과 팝업 크기", selection: $popupSize) {
                    ForEach(PopupSize.allCases) { size in
                        Text("\(size.label) (\(Int(size.dimensions.width))×\(Int(size.dimensions.height)))")
                            .tag(size.rawValue)
                    }
                }
            }

            Section("단축키") {
                LabeledContent("캡처 + 번역") {
                    KeyboardShortcuts.Recorder("", name: .captureAndTranslate)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Double Copy

private struct DoubleCopyTab: View {
    @Binding var doubleCopyEnabled: Bool
    @Binding var doubleCopyThresholdMs: Int
    @Binding var overwrite: Bool

    var body: some View {
        Form {
            Section {
                Toggle("이중 ⌘C 감지 사용", isOn: $doubleCopyEnabled)
                Picker("두 번 누름 간격", selection: $doubleCopyThresholdMs) {
                    Text("200 ms").tag(200)
                    Text("300 ms").tag(300)
                    Text("500 ms").tag(500)
                }
                Toggle("번역 결과로 클립보드 덮어쓰기", isOn: $overwrite)
            } footer: {
                Text("⌘C 를 빠르게 두 번 누르면 클립보드 텍스트를 즉시 번역합니다.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Startup

private struct StartupTab: View {
    @Binding var launchAtLogin: Bool

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in LaunchAtLogin.set(newValue) }
            } footer: {
                Text("Mac 에 로그인할 때 Lumo 가 자동으로 메뉴바에 나타납니다.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Debug

private struct DebugTab: View {
    @Binding var firstTokenTimeoutSec: Int
    @Binding var idleTimeoutSec: Int
    @Binding var hardTimeoutSec: Int

    var body: some View {
        Form {
            Section {
                Stepper("첫 토큰: \(firstTokenTimeoutSec)s", value: $firstTokenTimeoutSec, in: 5...60)
                Stepper("Idle: \(idleTimeoutSec)s", value: $idleTimeoutSec, in: 2...30)
                Stepper("강제 종료: \(hardTimeoutSec)s", value: $hardTimeoutSec, in: 10...600)
            } header: {
                Text("타임아웃")
            } footer: {
                Text("번역 응답이 지연될 때 watchdog 이 작업을 중단하기까지의 시간입니다.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - MLX Server status row

private struct MLXServerSection: View {
    @EnvironmentObject private var manager: MLXServerManager
    @AppStorage(SettingsKey.mlxServerEnabled) private var mlxServerEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                statusDot
                Text(statusLabel)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { mlxServerEnabled },
                    set: { newValue in
                        mlxServerEnabled = newValue
                        if newValue {
                            Task { await manager.enable() }
                        } else {
                            manager.disable()
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            if case .error(let msg) = manager.status {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if msg.contains("모델") {
                    Button("설치 가이드 열기") {
                        if let url = URL(string: "https://github.com/newTurn2017/Lumo#mlx-setup") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
            )
    }

    private var statusLabel: String {
        switch manager.status {
        case .stopped: return "정지됨"
        case .installing: return "설치 중…"
        case .starting: return "시작 중…"
        case .running: return "실행 중"
        case .error: return "오류"
        }
    }

    private var dotColor: Color {
        switch manager.status {
        case .running: return .green
        case .starting, .installing: return .yellow
        case .stopped: return .gray
        case .error: return .red
        }
    }
}
