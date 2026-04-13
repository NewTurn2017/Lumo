import Foundation

struct HistoryEntry: Codable, Equatable {
    enum Source: String, Codable { case image, text }
    var timestamp: Date
    var preview: String
    var full: String
    var source: Source
}

final class HistoryStore {
    static let capacity = 10
    private let defaults: UserDefaults
    private(set) var recent: [HistoryEntry] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recent = load()
    }

    func append(_ entry: HistoryEntry) {
        recent.append(entry)
        if recent.count > Self.capacity {
            recent.removeFirst(recent.count - Self.capacity)
        }
        save()
    }

    private func load() -> [HistoryEntry] {
        guard let data = defaults.data(forKey: SettingsKey.history),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recent) {
            defaults.set(data, forKey: SettingsKey.history)
        }
    }
}
