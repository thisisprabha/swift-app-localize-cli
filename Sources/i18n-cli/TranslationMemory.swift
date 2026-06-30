import Foundation

/// Translation memory — caches (sourceText, targetLang) → translatedText pairs.
/// On exact match, returns cached result at zero API cost.
struct TranslationMemory {
    private static let filename = "tm.json"

    struct Entry: Codable {
        let sourceText: String
        let targetLang: String
        let translatedText: String
    }

    private var entries: [String: Entry] = [:]  // key: "sourceText|targetLang"
    private let url: URL
    private let enabled: Bool

    /// Key for the in-memory dictionary.
    private static func cacheKey(source: String, targetLang: String) -> String {
        return "\(source)|\(targetLang)"
    }

    init(projectRoot: URL, enabled: Bool = true) {
        self.enabled = enabled
        self.url = projectRoot
            .appendingPathComponent(".i18n-cache")
            .appendingPathComponent(Self.filename)
        if enabled {
            self.entries = Self.load(from: url)
        }
    }

    /// Look up a cached translation. Returns nil if not found.
    func lookup(source: String, targetLang: String) -> String? {
        guard enabled else { return nil }
        return entries[Self.cacheKey(source: source, targetLang: targetLang)]?.translatedText
    }

    /// Store a translation.
    mutating func store(source: String, targetLang: String, translation: String) {
        guard enabled else { return }
        let key = Self.cacheKey(source: source, targetLang: targetLang)
        entries[key] = Entry(sourceText: source, targetLang: targetLang, translatedText: translation)
    }

    /// Persist to disk.
    func save() throws {
        guard enabled else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Array(entries.values))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Load from disk.
    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else {
            return [:]
        }
        var map: [String: Entry] = [:]
        for entry in list {
            map[cacheKey(source: entry.sourceText, targetLang: entry.targetLang)] = entry
        }
        return map
    }

    /// Number of cached entries.
    var count: Int { entries.count }

    /// Clear all entries.
    mutating func clear() {
        entries = [:]
    }
}
