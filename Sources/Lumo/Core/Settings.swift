import Foundation
import SwiftUI

enum SettingsKey {
    static let backendType                  = "lumo.backendType"
    static let ollamaURL                    = "lumo.ollamaURL"
    static let model                        = "lumo.model"
    static let keepAlive                    = "lumo.keepAlive"
    static let maxImageLongEdge             = "lumo.maxImageLongEdge"
    static let temperature                  = "lumo.temperature"
    static let doubleCopyEnabled            = "lumo.doubleCopyEnabled"
    static let doubleCopyThresholdMs        = "lumo.doubleCopyThresholdMs"
    static let overwriteClipboardOnDoubleCopy = "lumo.overwriteClipboardOnDoubleCopy"
    static let launchAtLogin                = "lumo.launchAtLogin"
    static let firstTokenTimeoutSec         = "lumo.firstTokenTimeoutSec"
    static let idleTimeoutSec               = "lumo.idleTimeoutSec"
    static let hardTimeoutSec               = "lumo.hardTimeoutSec"
    static let mlxServerEnabled             = "lumo.mlxServerEnabled"
    static let popupSize                    = "lumo.popupSize"
    static let popupDismissAfterSec         = "lumo.popupDismissAfterSec"
    static let popupFontSize                = "lumo.popupFontSize"
    static let history                      = "lumo.history"
}

struct SettingsSnapshot: Equatable {
    var backendType: String   // "mlx" | "ollama"
    var ollamaURL: String
    var model: String
    var keepAlive: String
    var maxImageLongEdge: Int
    var temperature: Double
    var doubleCopyEnabled: Bool
    var doubleCopyThresholdMs: Int
    var overwriteClipboardOnDoubleCopy: Bool
    var launchAtLogin: Bool
    var firstTokenTimeoutSec: Int
    var idleTimeoutSec: Int
    var hardTimeoutSec: Int
    var mlxServerEnabled: Bool
    var popupSize: String   // "small" | "medium" | "large" | "xlarge"
    var popupDismissAfterSec: Int   // -1 = manual only, positive = seconds
    var popupFontSize: Int          // points (clamped to 12...28 at runtime)

    static let defaults = SettingsSnapshot(
        backendType: "mlx",
        ollamaURL: "http://localhost:18080",
        model: "mlx-community/gemma-4-e4b-it-4bit",
        keepAlive: "30m",
        maxImageLongEdge: 1280,
        temperature: 0.2,
        doubleCopyEnabled: true,
        doubleCopyThresholdMs: 300,
        overwriteClipboardOnDoubleCopy: true,
        launchAtLogin: false,
        firstTokenTimeoutSec: 20,
        idleTimeoutSec: 8,
        hardTimeoutSec: 120,
        mlxServerEnabled: true,
        popupSize: "medium",
        popupDismissAfterSec: 15,
        popupFontSize: 18
    )

    static func load(from defaults: UserDefaults = .standard) -> SettingsSnapshot {
        var s = SettingsSnapshot.defaults
        if let v = defaults.string(forKey: SettingsKey.backendType) { s.backendType = v }
        if let v = defaults.string(forKey: SettingsKey.ollamaURL)   { s.ollamaURL = v }
        if let v = defaults.string(forKey: SettingsKey.model)     { s.model = v }
        if let v = defaults.string(forKey: SettingsKey.keepAlive) { s.keepAlive = v }
        if defaults.object(forKey: SettingsKey.maxImageLongEdge) != nil {
            s.maxImageLongEdge = defaults.integer(forKey: SettingsKey.maxImageLongEdge)
        }
        if defaults.object(forKey: SettingsKey.temperature) != nil {
            s.temperature = defaults.double(forKey: SettingsKey.temperature)
        }
        if defaults.object(forKey: SettingsKey.doubleCopyEnabled) != nil {
            s.doubleCopyEnabled = defaults.bool(forKey: SettingsKey.doubleCopyEnabled)
        }
        if defaults.object(forKey: SettingsKey.doubleCopyThresholdMs) != nil {
            s.doubleCopyThresholdMs = defaults.integer(forKey: SettingsKey.doubleCopyThresholdMs)
        }
        if defaults.object(forKey: SettingsKey.overwriteClipboardOnDoubleCopy) != nil {
            s.overwriteClipboardOnDoubleCopy = defaults.bool(forKey: SettingsKey.overwriteClipboardOnDoubleCopy)
        }
        if defaults.object(forKey: SettingsKey.launchAtLogin) != nil {
            s.launchAtLogin = defaults.bool(forKey: SettingsKey.launchAtLogin)
        }
        if defaults.object(forKey: SettingsKey.firstTokenTimeoutSec) != nil {
            s.firstTokenTimeoutSec = defaults.integer(forKey: SettingsKey.firstTokenTimeoutSec)
        }
        if defaults.object(forKey: SettingsKey.idleTimeoutSec) != nil {
            s.idleTimeoutSec = defaults.integer(forKey: SettingsKey.idleTimeoutSec)
        }
        if defaults.object(forKey: SettingsKey.hardTimeoutSec) != nil {
            s.hardTimeoutSec = defaults.integer(forKey: SettingsKey.hardTimeoutSec)
        }
        if defaults.object(forKey: SettingsKey.mlxServerEnabled) != nil {
            s.mlxServerEnabled = defaults.bool(forKey: SettingsKey.mlxServerEnabled)
        }
        if let v = defaults.string(forKey: SettingsKey.popupSize) { s.popupSize = v }
        if defaults.object(forKey: SettingsKey.popupDismissAfterSec) != nil {
            s.popupDismissAfterSec = defaults.integer(forKey: SettingsKey.popupDismissAfterSec)
        }
        if defaults.object(forKey: SettingsKey.popupFontSize) != nil {
            s.popupFontSize = defaults.integer(forKey: SettingsKey.popupFontSize)
        }
        return s
    }
}
