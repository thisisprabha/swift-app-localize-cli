import Foundation

enum AuditError: LocalizedError {
    case invalidProjectRoot(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectRoot(let path):
            return "Invalid project root: \(path)"
        }
    }
}

struct AuditCommand {
    static func run(args: [String]) async throws {
        guard args.count >= 1 else { throw UsageError.invalidArguments }

        let projectRoot = args[0]
        let root = URL(fileURLWithPath: projectRoot)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw AuditError.invalidProjectRoot(projectRoot)
        }

        var include: [String] = []
        var exclude: [String] = []

        var i = 1
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--include":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                include = splitCSV(args[i + 1])
                i += 2
            case "--exclude":
                guard i + 1 < args.count else { throw UsageError.invalidArguments }
                exclude = splitCSV(args[i + 1])
                i += 2
            default:
                throw UsageError.invalidArguments
            }
        }

        let reportURL = root
            .appendingPathComponent(".i18n-cache")
            .appendingPathComponent("audit-report.json")

        // Use the same engine as extract, but dry-run with no writes
        let engine = SwiftUIExtractorEngine(
            keyPrefix: "app",
            overwriteExisting: false,
            noSkipKeys: false,
            applyChanges: false,
            dryRun: true,
            stringsdictMode: .report,
            include: include,
            exclude: exclude,
            reportURL: reportURL
        )

        // Run extract in dry-run mode — it generates a report with all findings
        try engine.run(projectRoot: root, baseLang: "en")

        // Read the report back and output findings to stdout
        let reportData = try Data(contentsOf: reportURL)
        let report = try JSONDecoder().decode(ExtractReport.self, from: reportData)

        let findings = report.rewritten.filter { $0.reason != "dry_run" } + report.skipped + report.interpolations

        if findings.isEmpty {
            print("✅ No hardcoded strings found — all localized!")
        } else {
            for item in findings {
                let file = URL(fileURLWithPath: item.file).lastPathComponent
                let context = item.context
                let text = item.original
                if let reason = item.reason {
                    print("⚠ \(file):\(item.line) \(context)(\"\(text)\") — \(reason)")
                } else {
                    print("⚠ \(file):\(item.line) \(context)(\"\(text)\") — not localized")
                }
            }
        }

        let summary = report.summary
        print("\nFound \(findings.count) hardcoded strings in \(summary.scannedFiles) files")

        if findings.count > 0 {
            exit(1)
        }
    }

    private static func splitCSV(_ value: String) -> [String] {
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
