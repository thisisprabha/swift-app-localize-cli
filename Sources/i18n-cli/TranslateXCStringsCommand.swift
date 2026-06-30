import Foundation

enum TranslateXCStringsError: Error {
    case invalidPath(String)
    case missingFlag(String)
    case noTargetLanguages
    case noUntranslatedKeys
    case readFailed(String)
    case glossaryLoadFailed(String)
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
        var glossaryPath: String?
        var screenshotsPath: String?
        var noTM = false
        var clearTM = false

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
            case "--glossary":
                guard i + 1 < args.count else { throw TranslateXCStringsError.missingFlag("--glossary") }
                glossaryPath = args[i + 1]
                i += 2
            case "--context-screenshots":
                guard i + 1 < args.count else { throw TranslateXCStringsError.missingFlag("--context-screenshots") }
                screenshotsPath = args[i + 1]
                i += 2
            case "--no-tm":
                noTM = true
                i += 1
            case "--clear-tm":
                clearTM = true
                i += 1
            default:
                throw UsageError.invalidArguments
            }
        }

        guard !langs.isEmpty else {
            throw TranslateXCStringsError.noTargetLanguages
        }

        let client = try OpenAIClient()
        let projectRoot = xcstringsURL.deletingLastPathComponent()

        // Load glossary if provided
        var glossary: Glossary?
        if let path = glossaryPath {
            do {
                glossary = try Glossary(path: path)
            } catch {
                throw TranslateXCStringsError.glossaryLoadFailed(error.localizedDescription)
            }
        }

        // Load context screenshots if provided
        let screenshots = screenshotsPath.flatMap { ContextScreenshots(path: $0) }

        // Init translation memory
        var tm = TranslationMemory(projectRoot: projectRoot, enabled: !noTM)
        if clearTM { tm.clear() }

        var totalTranslated = 0
        var totalSkipped = 0
        var totalPlaceholderWarnings = 0
        var totalTMHits = 0
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
                print("  All \(mutableDoc.strings.count) keys up-to-date for '\(lang)'")
                totalSkipped += mutableDoc.strings.count
                continue
            }

            print("  \(needsTranslation.count) key(s) need translation")

            // Build appendixes
            var contextAppendix = ""
            if let context, !context.isEmpty {
                contextAppendix = "\n\nApp context: \(context)"
            }
            if let glossary {
                contextAppendix += glossary.systemPromptAppendix(for: lang)
            }
            if let screenshots {
                contextAppendix += screenshots.systemPromptAppendix(for: lang)
            }

            if dryRun {
                print("  [dry-run] would translate \(needsTranslation.count) keys")
                totalSkipped += needsTranslation.count
                continue
            }

            // Check TM first
            var needsLLM: [String: String] = [:]
            var tmHits = 0
            for (key, sourceValue) in needsTranslation {
                if let cached = tm.lookup(source: sourceValue, targetLang: lang) {
                    if mutableDoc.strings[key] != nil {
                        mutableDoc.strings[key]?.localizations[lang] = XCLocalization(
                            stringUnit: XCStringUnit(state: .translated, value: cached),
                            variations: nil
                        )
                    }
                    tmHits += 1
                } else {
                    needsLLM[key] = sourceValue
                }
            }
            totalTMHits += tmHits

            if needsLLM.isEmpty {
                print("  All \(needsTranslation.count) keys served from translation memory")
                totalSkipped += needsTranslation.count
                try XCStringsDiffEngine.saveCache(mutableDoc, for: lang, projectRoot: projectRoot)
                continue
            }

            let translated = try await client.translate(
                pairs: needsLLM,
                targetLanguageCode: lang,
                model: model ?? "gpt-4o-mini",
                context: contextAppendix.isEmpty ? nil : contextAppendix
            )

            var langTranslated = 0

            for key in needsLLM.keys {
                guard let translatedValue = translated[key], !translatedValue.isEmpty else {
                    continue
                }
                if mutableDoc.strings[key] != nil {
                    mutableDoc.strings[key]?.localizations[lang] = XCLocalization(
                        stringUnit: XCStringUnit(state: .translated, value: translatedValue),
                        variations: nil
                    )
                    langTranslated += 1

                    // Update TM
                    if let sourceValue = needsLLM[key] {
                        tm.store(source: sourceValue, targetLang: lang, translation: translatedValue)
                    }
                }
            }

            // Placeholder validation
            var batch: [(key: String, source: String, translation: String)] = []
            for key in needsLLM.keys {
                if let sourceValue = needsLLM[key], let transValue = translated[key] {
                    batch.append((key, sourceValue, transValue))
                }
            }
            let warnings = PlaceholderValidator.validateBatch(pairs: batch)
            if !warnings.isEmpty {
                totalPlaceholderWarnings += warnings.count
                for w in warnings {
                    fputs("  ⚠ \(w)\n", stderr)
                }
            }

            try XCStringsDiffEngine.saveCache(mutableDoc, for: lang, projectRoot: projectRoot)
            print("  Translated \(langTranslated)/\(needsTranslation.count) keys for '\(lang)' (TM hit: \(tmHits))")
            totalTranslated += langTranslated
            totalSkipped += needsTranslation.count - langTranslated - tmHits
        }

        try tm.save()

        if !dryRun {
            try XCStringsIO.write(mutableDoc, to: xcstringsURL)
            print("Wrote updated xcstrings -> \(xcstringsURL.path)")
        }

        let totalKeys = mutableDoc.strings.count
        print("--- Summary: \(totalKeys) total keys, \(totalTranslated) LLM-translated, \(totalTMHits) TM hits, \(totalPlaceholderWarnings) placeholder warnings, \(totalSkipped) skipped")
    }
}
