import Foundation
import os

enum Log {
    static let subsystem = "app.lumo"
    static let app       = Logger(subsystem: subsystem, category: "app")
    static let capture   = Logger(subsystem: subsystem, category: "capture")
    static let translate = Logger(subsystem: subsystem, category: "translate")
    static let hotkey    = Logger(subsystem: subsystem, category: "hotkey")
    static let ui        = Logger(subsystem: subsystem, category: "ui")
}

struct LatencySample: Equatable {
    var capture: Int
    var encode: Int
    var firstToken: Int
    var total: Int
}

final class LatencyStore {
    private let capacity: Int
    private(set) var recent: [LatencySample] = []
    init(capacity: Int = 10) { self.capacity = capacity }
    func record(_ sample: LatencySample) {
        recent.append(sample)
        if recent.count > capacity { recent.removeFirst(recent.count - capacity) }
    }
}
