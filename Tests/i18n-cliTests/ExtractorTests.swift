import Foundation
import XCTest

@testable import i18n_cli

final class ExtractorTests: XCTestCase {
    func testKeyGenerationDeterministic() {
        let gen = KeyGenerator(prefix: "app")
        XCTAssertEqual(gen.makeKey(forEnglish: "Hello world"), gen.makeKey(forEnglish: "Hello   world"))
    }

    func testExtractDryRunWritesBaseStringsButDoesNotRewriteSwift() throws {
        let tmp = try makeTempDir()
        let root = tmp.appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let srcDir = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let swiftFile = srcDir.appendingPathComponent("ContentView.swift")
        let originalSwift = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Hello")
                    Button("OK") { }
                    Text("Hi \\(name)")
                    Text(verbatim: "Raw")
                }
                .navigationTitle("Home")
            }
        }
        """
        try originalSwift.data(using: .utf8)!.write(to: swiftFile)

        let reportURL = root.appendingPathComponent(".i18n-cache/extract-report.json")
        let engine = SwiftUIExtractorEngine(
            keyPrefix: "app",
            overwriteExisting: false,
            noSkipKeys: false,
            applyChanges: false,
            dryRun: true,
            stringsdictMode: .auto,
            include: [],
            exclude: [],
            reportURL: reportURL
        )

        try engine.run(projectRoot: root, baseLang: "en")

        let baseStringsURL = root.appendingPathComponent("en.lproj/Localizable.strings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: baseStringsURL.path))
        let strings = try loadStrings(at: baseStringsURL)
        XCTAssertEqual(strings.count, 3) // Hello, OK, Home

        let swiftAfter = try String(contentsOf: swiftFile, encoding: .utf8)
        XCTAssertEqual(swiftAfter, originalSwift)
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))
    }

    func testExtractApplyRewritesSwift() throws {
        let tmp = try makeTempDir()
        let root = tmp.appendingPathComponent("MyApp2")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let srcDir = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let swiftFile = srcDir.appendingPathComponent("ContentView.swift")
        let originalSwift = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Hello")
                    Button("OK") { }
                }
                .navigationTitle("Home")
            }
        }
        """
        try originalSwift.data(using: .utf8)!.write(to: swiftFile)

        let reportURL = root.appendingPathComponent(".i18n-cache/extract-report.json")
        let engine = SwiftUIExtractorEngine(
            keyPrefix: "app",
            overwriteExisting: false,
            noSkipKeys: false,
            applyChanges: true,
            dryRun: false,
            stringsdictMode: .auto,
            include: [],
            exclude: [],
            reportURL: reportURL
        )

        try engine.run(projectRoot: root, baseLang: "en")

        let swiftAfter = try String(contentsOf: swiftFile, encoding: .utf8)
        XCTAssertFalse(swiftAfter.contains("Text(\"Hello\")"))
        XCTAssertFalse(swiftAfter.contains("Button(\"OK\")"))
        XCTAssertFalse(swiftAfter.contains(".navigationTitle(\"Home\")"))
    }

    func testAutoGeneratesStringsdictForPluralFormats() throws {
        let tmp = try makeTempDir()
        let root = tmp.appendingPathComponent("MyApp3")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let srcDir = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let swiftFile = srcDir.appendingPathComponent("ContentView.swift")
        let originalSwift = """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                VStack {
                    Text(\"%d moves\")
                    Text(\"%d move(s)\")
                    Text(\"%d tries\")
                    Text(\"%d success\") // ambiguous
                }
            }
        }
        """
        try originalSwift.data(using: .utf8)!.write(to: swiftFile)

        let reportURL = root.appendingPathComponent(".i18n-cache/extract-report.json")
        let engine = SwiftUIExtractorEngine(
            keyPrefix: "app",
            overwriteExisting: false,
            noSkipKeys: false,
            applyChanges: false,
            dryRun: true,
            stringsdictMode: .auto,
            include: [],
            exclude: [],
            reportURL: reportURL
        )

        try engine.run(projectRoot: root, baseLang: "en")

        let stringsdictURL = root.appendingPathComponent("en.lproj/Localizable.stringsdict")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stringsdictURL.path))

        let dict = try loadStringsdict(at: stringsdictURL)
        XCTAssertTrue(dict.keys.count >= 3)

        let reportData = try Data(contentsOf: reportURL)
        let report = try JSONDecoder().decode(ExtractReport.self, from: reportData)
        XCTAssertGreaterThanOrEqual(report.stringsdictGenerated.count, 3)
        XCTAssertGreaterThanOrEqual(report.stringsdictCandidates.count, 1)
    }

    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("i18n-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
