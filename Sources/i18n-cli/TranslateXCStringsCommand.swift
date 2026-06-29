import Foundation

enum TranslateXCStringsError: Error {
    case invalidPath(String)
    case missingFlag(String)
    case noTargetLanguages
    case noUntranslatedKeys
    case readFailed(String)
}

struct TranslateXCStringsCommand {
    static func run(args: [String]) async throws {
        guard !args.isEmpty else { throw UsageError.invalidArguments }

        let path = args[0]
        let xcstringsURL = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: xcstringsURL.path) else {
            throw TranslateXCStringsError.invalidPath(path)
        }

        let doc = try XCStringsIO.read(from: xcstringsURL)
        let sourceLang = doc.sourceLanguage

        var langs: [String] = []
        var dryRun = false
        var context: String?
        var model: String?

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--langs":
                guard i + 1 < args.count else { throw TranslateXCStringsError.missingFlag("--langs") }
                langs = args[i + 1].split(separator: ",").map(String.init)
                i += 2
            case "--dry-run":
                dryRun = true
                i += 1
            case "--context":
                guard i + 1 < args.count else { throw TranslateXCStringsError.missingFlag("--context") }
                context = args[i + 1]
                i += 2
            case "--model":
                guard i + 1 < args.count else { throw TranslateXCStringsError.missingFlag("--model") }
                model = args[i + 1]
                i += 2
            default:
                throw UsageError.invalidArguments
            }
        }

        guard !langs.isEmpty else {
            throw TranslateXCStringsError.noTargetLanguages
        }

        let client = try OpenAIClient()
        let projectRoot = xcstringsURL.deletingLastPathComponent()

        var totalTranslated = 0
        var totalSkipped = 0
        var mutableDoc = doc

        for lang in langs {
            print("=== Translating \(sourceLang) -> \(lang) ===")

            let cache = XCStringsDiffEngine.loadCache(for: lang, projectRoot: projectRoot)
            let needsTranslation = XCStringsDiffEngine.needsTranslation(
                source: mutableDoc,
                targetLanguage: lang,
                cache: cache
            )

            if needsTranslation.isEmpty {
                print("  All \(doc.strings.count) keys up-to-date for '\(lang)'")
                totalSkipped += doc.strings.count
                continue
            }

            print("  \(needsTranslation.count) key(s) need translation")

            if dryRun {
                print("  [dry-run] would translate \(needsTranslation.count) keys")
                totalSkipped += needsTranslation.count
                continue
            }

            let translated = try await client.translate(
                pairs: needsTranslation,
                targetLanguageCode: lang,
                model: model ?? "gpt-4o-mini",
                context: context
            )

            var langTranslated = 0

            for key in needsTranslation.keys {
                guard let translatedValue = translated[key], !translatedValue.isEmpty else {
                    continue
                }
                if mutableDoc.strings[key] != nil {
                    mutableDoc.strings[key]?.localizations[lang] = XCLocalization(
                        stringUnit: XCStringUnit(state: .translated, value: translatedValue),
                        variations: nil
                    )
                    langTranslated += 1
                }
            }

            try XCStringsDiffEngine.saveCache(mutableDoc, for: lang, projectRoot: projectRoot)
            print("  Translated \(langTranslated)/\(needsTranslation.count) keys for '\(lang)'")
            totalTranslated += langTranslated
            totalSkipped += needsTranslation.count - langTranslated
        }

        if !dryRun {
            try XCStringsIO.write(mutableDoc, to: xcstringsURL)
            print("Wrote updated xcstrings -> \(xcstringsURL.path)")
        }

        let totalKeys = doc.strings.count
        print("--- Summary: \(totalKeys) total keys, \(totalTranslated) translated, \(totalSkipped) skipped")
    }
}

// (translate extension lives in OpenAIClient.swift)