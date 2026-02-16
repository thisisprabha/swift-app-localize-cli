import Foundation

enum StringsdictError: Error {
    case invalidFormat
    case writeFailed
}

struct TranslationCache: Codable {
    var strings: [String: String] = [:]
    var stringsdict: [String: String] = [:]
}

func loadTranslationCache(at url: URL) -> TranslationCache {
    guard FileManager.default.fileExists(atPath: url.path),
          let data = try? Data(contentsOf: url),
          let cache = try? JSONDecoder().decode(TranslationCache.self, from: data) else {
        return TranslationCache()
    }
    return cache
}

func saveTranslationCache(_ cache: TranslationCache, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(cache)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
}

func loadStringsdictIfExists(at url: URL) throws -> [String: Any]? {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
    }
    return try loadStringsdict(at: url)
}

func loadStringsdict(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    guard let dict = plist as? [String: Any] else {
        throw StringsdictError.invalidFormat
    }
    return dict
}

func saveStringsdict(_ dict: [String: Any], to url: URL) throws {
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    } catch {
        throw StringsdictError.writeFailed
    }
}

func mergeStringsdictEntries(
    base: [String: Any],
    entries: [String: Any],
    overwrite: Bool
) -> [String: Any] {
    var merged = base
    for (key, value) in entries {
        if merged[key] == nil || overwrite {
            merged[key] = value
        }
    }
    return merged
}

func makePluralStringsdictEntry(
    singular: String,
    other: String,
    valueType: String = "d"
) -> [String: Any] {
    return [
        "NSStringLocalizedFormatKey": "%#@value@",
        "value": [
            "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
            "NSStringFormatValueTypeKey": valueType,
            "one": singular,
            "other": other
        ]
    ]
}

func extractTranslatableStringsdictValues(from root: [String: Any]) -> [String: String] {
    var result: [String: String] = [:]
    collectTranslatableValues(node: root, path: "", parentKey: nil, into: &result)
    return result
}

func applyingStringsdictTranslations(
    base: [String: Any],
    translations: [String: String]
) -> [String: Any] {
    guard let translated = applyTranslations(node: base, path: "", parentKey: nil, translations: translations) as? [String: Any] else {
        return base
    }
    return translated
}

private let nonTranslatableStringsdictKeys: Set<String> = [
    "NSStringFormatSpecTypeKey",
    "NSStringFormatValueTypeKey"
]

private func collectTranslatableValues(
    node: Any,
    path: String,
    parentKey: String?,
    into result: inout [String: String]
) {
    if let dict = node as? [String: Any] {
        for key in dict.keys.sorted() {
            guard let child = dict[key] else {
                continue
            }
            let childPath = appendPath(path, segment: key)
            collectTranslatableValues(node: child, path: childPath, parentKey: key, into: &result)
        }
        return
    }

    if let array = node as? [Any] {
        for (index, value) in array.enumerated() {
            let childPath = appendPath(path, segment: String(index))
            collectTranslatableValues(node: value, path: childPath, parentKey: nil, into: &result)
        }
        return
    }

    if let text = node as? String,
       shouldTranslateStringsdictValue(parentKey: parentKey, value: text) {
        result[path] = text
    }
}

private func applyTranslations(
    node: Any,
    path: String,
    parentKey: String?,
    translations: [String: String]
) -> Any {
    if let dict = node as? [String: Any] {
        var newDict: [String: Any] = [:]
        for key in dict.keys.sorted() {
            guard let child = dict[key] else {
                continue
            }
            let childPath = appendPath(path, segment: key)
            newDict[key] = applyTranslations(node: child, path: childPath, parentKey: key, translations: translations)
        }
        return newDict
    }

    if let array = node as? [Any] {
        return array.enumerated().map { index, value in
            let childPath = appendPath(path, segment: String(index))
            return applyTranslations(node: value, path: childPath, parentKey: nil, translations: translations)
        }
    }

    if let text = node as? String,
       shouldTranslateStringsdictValue(parentKey: parentKey, value: text),
       let translated = translations[path] {
        return translated
    }

    return node
}

private func shouldTranslateStringsdictValue(parentKey: String?, value: String) -> Bool {
    if let key = parentKey, nonTranslatableStringsdictKeys.contains(key) {
        return false
    }

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return false
    }

    // Skip values that are only placeholders/symbols and have no natural-language letters.
    if trimmed.range(of: "[A-Za-z]", options: .regularExpression) == nil {
        return false
    }

    return true
}

private func appendPath(_ path: String, segment: String) -> String {
    let escaped = segment
        .replacingOccurrences(of: "~", with: "~0")
        .replacingOccurrences(of: "/", with: "~1")

    if path.isEmpty {
        return "/\(escaped)"
    }
    return "\(path)/\(escaped)"
}
