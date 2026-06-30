import Foundation

/// Xcode Localization Catalog (.xcloc) export — creates a bundle for human translator handoff.
/// An .xcloc bundle is a directory structure that Xcode uses for importing/exporting localizations.
enum XCLocExport {
    struct Options {
        let sourceLanguage: String
        let targetLanguages: [String]
        let outputPath: String
    }

    static func export(document: XCStringsDocument, options: Options) throws {
        let outputURL = URL(fileURLWithPath: options.outputPath)

        for targetLang in options.targetLanguages {
            let bundleURL = outputURL.appendingPathComponent("\(options.sourceLanguage)-\(targetLang).xcloc")
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

            // Create Contents.json
            let contents: [String: Any] = [
                "sourceLanguage": options.sourceLanguage,
                "targetLanguage": targetLang,
                "developmentRegion": "en",
                "version": "1.0"
            ]
            let contentsData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
            try contentsData.write(to: bundleURL.appendingPathComponent("Contents.json"))

            // Copy the source .xcstrings
            let sourceDir = bundleURL.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
            let sourceFile = sourceDir.appendingPathComponent("Localizable.xcstrings")
            try XCStringsIO.write(document, to: sourceFile)

            // Create empty translated directory structure
            let transDir = bundleURL.appendingPathComponent("translated")
            try FileManager.default.createDirectory(at: transDir, withIntermediateDirectories: true)
        }

        print("Exported \(options.targetLanguages.count) .xcloc bundles to \(options.outputPath)")
    }
}
