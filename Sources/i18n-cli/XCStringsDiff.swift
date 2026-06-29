import Foundation

// MARK: - Diff result model

struct XCStringsDiff {
    enum Status {
        case added         // new key, no translation
        case changed       // source English changed, translation stale
        case removed       // key no longer in source (orphan cache entry)
        case untranslated  // key exists but target language missing
        case translated    // up-to-date
    }

    struct Entry {
        let key: String
        let status: Status
        let sourceValue: String?
        let cachedValue: String?
        let language: String
    }

    let entries: [Entry]

    var added: [Entry] { entries.filter { $0.status == .added } }
    var changed: [Entry] { entries.filter { $0.status == .changed } }
    var removed: [Entry] { entries.filter { $0.status == .removed } }
    var untranslated: [Entry] { entries.filter { $0.status == .untranslated } }
    var translated: [Entry] { entries.filter { $0.status == .translated } }
}

// MARK: - Diff engine

enum XCStringsDiffEngine {
    /// Compare source document against cached translations for a target language.
    /// Returns a dictionary of [key: English source value] for keys needing translation.
    static func needsTranslation(
        source: XCStringsDocument,
        targetLanguage: String,
        cache: XCStringsDocument? = nil
    ) -> [String: String] {
        guard let cache else {
            var result: [String: String] = [:]
            for (key, entry) in source.strings {
                if let enLoc = entry.localizations[source.sourceLanguage],
                   let value = enLoc.stringUnit?.value {
                    result[key] = value
                }
            }
            return result
        }

        var result: [String: String] = [:]

        for (key, sourceEntry) in source.strings {
            guard let sourceEnLoc = sourceEntry.localizations[source.sourceLanguage],
                  let sourceValue = sourceEnLoc.stringUnit?.value else {
                continue
            }

            guard let cachedEntry = cache.strings[key] else {
                result[key] = sourceValue
                continue
            }

            let cachedSourceValue = cachedEntry.localizations[source.sourceLanguage]?.stringUnit?.value

            if cachedSourceValue != sourceValue {
                result[key] = sourceValue
                continue
            }

            if cachedEntry.localizations[targetLanguage] == nil {
                result[key] = sourceValue
                continue
            }

            let targetLoc = cachedEntry.localizations[targetLanguage]
            if targetLoc?.stringUnit?.state == .new, targetLoc?.stringUnit?.value.isEmpty == true {
                result[key] = sourceValue
            }
        }

        return result
    }

    /// Full diff between source and cached documents for a target language.
    static func diff(
        source: XCStringsDocument,
        cache: XCStringsDocument?,
        targetLanguage: String
    ) -> XCStringsDiff {
        let sourceLang = source.sourceLanguage
        var entries: [XCStringsDiff.Entry] = []

        for (key, sourceEntry) in source.strings {
            let sourceValue = sourceEntry.localizations[sourceLang]?.stringUnit?.value

            guard let cachedEntry = cache?.strings[key] else {
                entries.append(XCStringsDiff.Entry(
                    key: key, status: .added,
                    sourceValue: sourceValue, cachedValue: nil,
                    language: targetLanguage
                ))
                continue
            }

            let cachedSourceValue = cachedEntry.localizations[sourceLang]?.stringUnit?.value

            if cachedSourceValue != sourceValue {
                entries.append(XCStringsDiff.Entry(
                    key: key, status: .changed,
                    sourceValue: sourceValue, cachedValue: cachedSourceValue,
                    language: targetLanguage
                ))
                continue
            }

            if let targetLoc = cachedEntry.localizations[targetLanguage],
               let unit = targetLoc.stringUnit,
               unit.state == .translated || unit.state == .needsReview,
               !unit.value.isEmpty {
                entries.append(XCStringsDiff.Entry(
                    key: key, status: .translated,
                    sourceValue: sourceValue, cachedValue: unit.value,
                    language: targetLanguage
                ))
            } else {
                entries.append(XCStringsDiff.Entry(
                    key: key, status: .untranslated,
                    sourceValue: sourceValue, cachedValue: nil,
                    language: targetLanguage
                ))
            }
        }

        if let cache {
            for (key, cachedEntry) in cache.strings {
                if source.strings[key] == nil {
                    let cachedValue = cachedEntry.localizations[targetLanguage]?.stringUnit?.value
                    entries.append(XCStringsDiff.Entry(
                        key: key, status: .removed,
                        sourceValue: nil, cachedValue: cachedValue,
                        language: targetLanguage
                    ))
                }
            }
        }

        return XCStringsDiff(entries: entries)
    }
}

// MARK: - Cache helpers

extension XCStringsDiffEngine {
    /// Cache file URL pattern: .i18n-cache/<lang>.xcstrings-cache.json
    static func cacheURL(for language: String, projectRoot: URL) -> URL {
        return projectRoot
            .appendingPathComponent(".i18n-cache")
            .appendingPathComponent("\(language).xcstrings-cache.json")
    }

    /// Load a cached XCStringsDocument if it exists.
    static func loadCache(for language: String, projectRoot: URL) -> XCStringsDocument? {
        let url = cacheURL(for: language, projectRoot: projectRoot)
        return try? XCStringsIO.read(from: url)
    }

    /// Save a cache snapshot of the source document after successful translation.
    static func saveCache(_ document: XCStringsDocument, for language: String, projectRoot: URL) throws {
        let url = cacheURL(for: language, projectRoot: projectRoot)
        try XCStringsIO.write(document, to: url)
    }
}
