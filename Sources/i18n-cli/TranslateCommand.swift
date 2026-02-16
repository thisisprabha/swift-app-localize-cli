import Foundation

enum CLIError: LocalizedError {
    case invalidTargetLanguages
    case missingBaseLocalization(String)

    var errorDescription: String? {
        switch self {
        case .invalidTargetLanguages:
            return "No valid target language codes were provided."
        case .missingBaseLocalization(let path):
            return "Neither Localizable.strings nor Localizable.stringsdict exists in \(path)."
        }
    }
}

enum TranslateCommand {
    static func run(projectRoot: String, baseLang: String, targetLangsCSV: String) async throws {
        let root = URL(fileURLWithPath: projectRoot)
        let targetLangs = parseTargetLanguages(targetLangsCSV)

        guard !targetLangs.isEmpty else {
            throw CLIError.invalidTargetLanguages
        }

        let client = try OpenAIClient()
        for targetLang in targetLangs {
            try await translateProject(
                root: root,
                baseLang: baseLang,
                targetLang: targetLang,
                client: client
            )
        }
    }

    private static func parseTargetLanguages(_ raw: String) -> [String] {
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var result: [String] = []
        for part in parts {
            if seen.insert(part).inserted {
                result.append(part)
            }
        }
        return result
    }

    private static func translateProject(
        root: URL,
        baseLang: String,
        targetLang: String,
        client: OpenAIClient
    ) async throws {
        let baseDir = root.appendingPathComponent("\(baseLang).lproj")
        let targetDir = root.appendingPathComponent("\(targetLang).lproj")

        let baseStringsURL = baseDir.appendingPathComponent("Localizable.strings")
        let targetStringsURL = targetDir.appendingPathComponent("Localizable.strings")

        let baseStringsdictURL = baseDir.appendingPathComponent("Localizable.stringsdict")
        let targetStringsdictURL = targetDir.appendingPathComponent("Localizable.stringsdict")

        let cacheURL = root
            .appendingPathComponent(".i18n-cache")
            .appendingPathComponent("\(targetLang).json")

        let hasBaseStrings = FileManager.default.fileExists(atPath: baseStringsURL.path)
        let hasBaseStringsdict = FileManager.default.fileExists(atPath: baseStringsdictURL.path)
        if !hasBaseStrings && !hasBaseStringsdict {
            throw CLIError.missingBaseLocalization(baseDir.path)
        }

        print("=== Translating \(baseLang) -> \(targetLang) ===")

        var cache = loadTranslationCache(at: cacheURL)

        if hasBaseStrings {
            try await translateStrings(
                baseURL: baseStringsURL,
                targetURL: targetStringsURL,
                targetLang: targetLang,
                client: client,
                cache: &cache
            )
        } else {
            print("Skipped Localizable.strings (missing in base language)")
            cache.strings = [:]
        }

        if hasBaseStringsdict {
            try await translateStringsdict(
                baseURL: baseStringsdictURL,
                targetURL: targetStringsdictURL,
                targetLang: targetLang,
                client: client,
                cache: &cache
            )
        } else {
            print("Skipped Localizable.stringsdict (missing in base language)")
            cache.stringsdict = [:]
        }

        try saveTranslationCache(cache, to: cacheURL)
        print("Updated cache at \(cacheURL.path)")
    }

    private static func translateStrings(
        baseURL: URL,
        targetURL: URL,
        targetLang: String,
        client: OpenAIClient,
        cache: inout TranslationCache
    ) async throws {
        let baseStrings = try loadStrings(at: baseURL)
        let existingTargetStrings = try loadStringsIfExists(at: targetURL)
        let toTranslate = makeDiff(
            baseValues: baseStrings,
            existingTargetValues: existingTargetStrings,
            cachedSourceValues: cache.strings
        )

        print("Localizable.strings: \(baseStrings.count) total, \(toTranslate.count) new/changed")

        let translated = try await translateInBatches(
            client: client,
            pairs: toTranslate,
            targetLanguageCode: targetLang
        )

        var merged: [String: String] = [:]
        for key in baseStrings.keys.sorted() {
            if let newValue = translated[key] {
                merged[key] = newValue
                continue
            }

            if let existingValue = existingTargetStrings[key], toTranslate[key] == nil {
                merged[key] = existingValue
                continue
            }

            merged[key] = baseStrings[key] ?? ""
        }

        try saveStrings(merged, to: targetURL)
        print("Wrote \(merged.count) strings -> \(targetURL.path)")

        cache.strings = baseStrings
    }

    private static func translateStringsdict(
        baseURL: URL,
        targetURL: URL,
        targetLang: String,
        client: OpenAIClient,
        cache: inout TranslationCache
    ) async throws {
        let baseStringsdict = try loadStringsdict(at: baseURL)
        let baseValues = extractTranslatableStringsdictValues(from: baseStringsdict)

        let existingTargetStringsdict = try loadStringsdictIfExists(at: targetURL) ?? baseStringsdict
        let existingTargetValues = extractTranslatableStringsdictValues(from: existingTargetStringsdict)

        let toTranslate = makeDiff(
            baseValues: baseValues,
            existingTargetValues: existingTargetValues,
            cachedSourceValues: cache.stringsdict
        )

        print("Localizable.stringsdict: \(baseValues.count) translatable values, \(toTranslate.count) new/changed")

        let translated = try await translateInBatches(
            client: client,
            pairs: toTranslate,
            targetLanguageCode: targetLang
        )

        var mergedValues: [String: String] = [:]
        for key in baseValues.keys.sorted() {
            if let newValue = translated[key] {
                mergedValues[key] = newValue
                continue
            }

            if let existingValue = existingTargetValues[key], toTranslate[key] == nil {
                mergedValues[key] = existingValue
                continue
            }

            mergedValues[key] = baseValues[key] ?? ""
        }

        let finalDict = applyingStringsdictTranslations(base: baseStringsdict, translations: mergedValues)
        try saveStringsdict(finalDict, to: targetURL)
        print("Wrote Localizable.stringsdict -> \(targetURL.path)")

        cache.stringsdict = baseValues
    }

    private static func makeDiff(
        baseValues: [String: String],
        existingTargetValues: [String: String],
        cachedSourceValues: [String: String]
    ) -> [String: String] {
        var delta: [String: String] = [:]

        for (key, baseValue) in baseValues {
            if existingTargetValues[key] == nil {
                delta[key] = baseValue
                continue
            }

            if let cachedSourceValue = cachedSourceValues[key], cachedSourceValue != baseValue {
                delta[key] = baseValue
            }
        }

        return delta
    }

    private static func translateInBatches(
        client: OpenAIClient,
        pairs: [String: String],
        targetLanguageCode: String,
        batchSize: Int = 120
    ) async throws -> [String: String] {
        guard !pairs.isEmpty else {
            return [:]
        }

        let keys = pairs.keys.sorted()
        let totalBatches = Int(ceil(Double(keys.count) / Double(batchSize)))

        var result: [String: String] = [:]
        var batchIndex = 0

        var start = 0
        while start < keys.count {
            let end = min(start + batchSize, keys.count)
            let batchKeys = Array(keys[start..<end])
            var batch: [String: String] = [:]
            for key in batchKeys {
                batch[key] = pairs[key]
            }

            batchIndex += 1
            print("Translating batch \(batchIndex)/\(totalBatches) with \(batch.count) items...")
            let translated = try await client.translate(
                pairs: batch,
                targetLanguageCode: targetLanguageCode
            )

            for key in batchKeys {
                if let value = translated[key] {
                    result[key] = value
                }
            }

            start = end
        }

        return result
    }
}

