import Foundation

enum ExtractCommand {
    struct Options {
        var applyChanges: Bool = false
        var dryRun: Bool = true
        var keyPrefix: String = "app"
        var reportPath: String? = nil
        var includeCSV: String? = nil
        var excludeCSV: String? = nil
        var overwriteExisting: Bool = false
        var noSkipKeys: Bool = false
        var stringsdictMode: StringsdictMode = .auto
    }

    static func run(args: [String]) async throws {
        guard args.count >= 2 else { throw UsageError.invalidArguments }

        let projectRoot = args[0]
        let baseLang = args[1]
        var options = Options()

        var i = 2
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--apply":
                options.applyChanges = true
                options.dryRun = false
                i += 1
            case "--dry-run":
                options.dryRun = true
                i += 1
            case "--key-prefix":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                options.keyPrefix = args[i + 1]
                i += 2
            case "--report":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                options.reportPath = args[i + 1]
                i += 2
            case "--include":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                options.includeCSV = args[i + 1]
                i += 2
            case "--exclude":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                options.excludeCSV = args[i + 1]
                i += 2
            case "--overwrite-existing":
                options.overwriteExisting = true
                i += 1
            case "--no-skip-keys":
                options.noSkipKeys = true
                i += 1
            case "--stringsdict":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                options.stringsdictMode = StringsdictMode(rawValue: args[i + 1]) ?? .auto
                i += 2
            default:
                throw UsageError.invalidArguments
            }
        }

        let rootURL = URL(fileURLWithPath: projectRoot)
        let reportURL = resolveReportURL(root: rootURL, reportPath: options.reportPath)

        let extractor = SwiftUIExtractorEngine(
            keyPrefix: options.keyPrefix,
            overwriteExisting: options.overwriteExisting,
            noSkipKeys: options.noSkipKeys,
            applyChanges: options.applyChanges,
            dryRun: options.dryRun,
            stringsdictMode: options.stringsdictMode,
            include: splitCSV(options.includeCSV),
            exclude: splitCSV(options.excludeCSV),
            reportURL: reportURL
        )

        try extractor.run(projectRoot: rootURL, baseLang: baseLang)
    }

    private static func splitCSV(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func resolveReportURL(root: URL, reportPath: String?) -> URL {
        if let reportPath, !reportPath.isEmpty {
            let url = URL(fileURLWithPath: reportPath)
            if url.path.hasPrefix("/") {
                return url
            }
            return root.appendingPathComponent(reportPath)
        }
        return root
            .appendingPathComponent(".i18n-cache")
            .appendingPathComponent("extract-report.json")
    }
}

enum StringsdictMode: String {
    case auto
    case report
}
