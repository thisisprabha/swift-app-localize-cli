import Foundation

struct MigrateCommand {
    static func run(args: [String]) async throws {
        guard args.count >= 1 else { throw UsageError.invalidArguments }

        let projectRoot = args[0]
        var langs: [String] = []
        var dryRun = false
        var keyPrefix = "app"
        var context: String?

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--langs":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                langs = args[i + 1].split(separator: ",").map(String.init)
                i += 2
            case "--key-prefix":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                keyPrefix = args[i + 1]
                i += 2
            case "--dry-run":
                dryRun = true
                i += 1
            case "--context":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                context = args[i + 1]
                i += 2
            default:
                throw UsageError.invalidArguments
            }
        }

        let root = URL(fileURLWithPath: projectRoot)

        // Step 1: Extract (AST walk + source rewrite + xcstrings generation)
        print("=== Step 1: Extracting strings ===")
        let reportURL = root
            .appendingPathComponent(".i18n-cache")
            .appendingPathComponent("extract-report.json")

        let extractor = SwiftUIExtractorEngine(
            keyPrefix: keyPrefix,
            overwriteExisting: false,
            noSkipKeys: false,
            applyChanges: !dryRun,
            dryRun: dryRun,
            stringsdictMode: .auto,
            include: [],
            exclude: [],
            reportURL: reportURL
        )

        try extractor.run(projectRoot: root, baseLang: "en")

        // Generate .xcstrings from extraction output
        let baseStringsURL = root.appendingPathComponent("en.lproj/Localizable.strings")
        let xcstringsURL = root.appendingPathComponent("Localizable.xcstrings")
        if FileManager.default.fileExists(atPath: baseStringsURL.path) {
            let strings = try loadStrings(at: baseStringsURL)
            let doc = XCStringsIO.document(from: strings)
            try XCStringsIO.write(doc, to: xcstringsURL)
            print("Wrote xcstrings -> \(xcstringsURL.path) (\(doc.strings.count) keys)")
        }

        if langs.isEmpty {
            print("No --langs specified. Extract complete (no translation).")
            return
        }

        // Step 2: Translate via TranslateXCStringsCommand
        print("=== Step 2: Translating ===")
        var translateArgs = [xcstringsURL.path, "--langs", langs.joined(separator: ",")]
        if dryRun { translateArgs.append("--dry-run") }
        if let context { translateArgs += ["--context", context] }

        try await TranslateXCStringsCommand.run(args: translateArgs)
    }
}
