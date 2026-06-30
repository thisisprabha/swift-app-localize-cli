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

    // MARK: - IL-008: More SwiftUI views

    func _runExtraction(on swiftCode: String, tmp: URL, file: String = "ContentView.swift", apply: Bool = false) throws -> (strings: [String: String], report: ExtractReport) {
        let srcDir = tmp.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        let swiftFile = srcDir.appendingPathComponent(file)
        try swiftCode.data(using: .utf8)!.write(to: swiftFile)

        let reportURL = tmp.appendingPathComponent(".i18n-cache/extract-report.json")
        let engine = SwiftUIExtractorEngine(
            keyPrefix: "app",
            overwriteExisting: false,
            noSkipKeys: false,
            applyChanges: apply,
            dryRun: !apply,
            stringsdictMode: .auto,
            include: [],
            exclude: [],
            reportURL: reportURL
        )

        try engine.run(projectRoot: tmp, baseLang: "en")

        let stringsURL = tmp.appendingPathComponent("en.lproj/Localizable.strings")
        let strings = try loadStrings(at: stringsURL)

        let reportData = try Data(contentsOf: reportURL)
        let report = try JSONDecoder().decode(ExtractReport.self, from: reportData)

        return (strings, report)
    }

    func testExtractSection() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                Section("Hello") { }
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Hello"), "Section should extract string literals")
    }

    func testExtractToggle() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            @State var on = false
            var body: some View {
                Toggle("Enable", isOn: $on)
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Enable"), "Toggle should extract string literals")
    }

    func testExtractPicker() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            @State var s = 0
            var body: some View {
                Picker("Size", selection: $s) { Text("Small") }
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Size"), "Picker title should be extracted")
    }

    func testExtractMenu() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                Menu("Actions") { Text("Copy") }
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Actions"), "Menu should extract string literals")
    }

    func testExtractTextField() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            @State var t = ""
            var body: some View {
                TextField("Enter name", text: $t)
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Enter name"), "TextField placeholder should be extracted")
    }

    func testExtractLink() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                Link("Visit Site", destination: URL(string: "https://example.com")!)
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Visit Site"), "Link should extract string literals")
    }

    func testExtractNavigationLink() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                NavigationLink("Details", destination: Text("Detail"))
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Details"), "NavigationLink should extract string literals")
    }

    func testExtractProgressView() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                ProgressView("Loading")
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Loading"), "ProgressView should extract string literals")
    }

    func testExtractGroupBox() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                GroupBox("Settings") { Text("Content") }
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Settings"), "GroupBox should extract string literals")
    }

    func testExtractDisclosureGroup() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                DisclosureGroup("More") { Text("Hidden") }
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("More"), "DisclosureGroup should extract string literals")
    }

    func testExtractShareLink() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                ShareLink("Share", item: "Hello")
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Share"), "ShareLink should extract string literals")
    }

    // MARK: - IL-009: UIKit/AppKit patterns

    func testSkipNSLocalizedString() throws {
        let tmp = try makeTempDir()
        let (strings, report) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                Text(NSLocalizedString("already_localized", comment: "Already localized"))
                Text("New string")
            }
        }
        """, tmp: tmp)
        // NSLocalizedString strings should NOT be extracted
        XCTAssertFalse(strings.values.contains("already_localized"), "NSLocalizedString should NOT be extracted")
        XCTAssertTrue(strings.values.contains("New string"), "Regular strings should still be extracted")
    }

    func testSkipStringLocalized() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                Text(String(localized: "already_done"))
                Text("Fresh string")
            }
        }
        """, tmp: tmp)
        XCTAssertFalse(strings.values.contains("already_done"), "String(localized:) should NOT be extracted")
        XCTAssertTrue(strings.values.contains("Fresh string"), "Regular strings should still be extracted")
    }

    func testExtractTitleAssignment() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        class Controller {
            func setup() {
                button.title = "Click me"
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Click me"), ".title = should extract string literals")
    }

    // MARK: - IL-010: i18n-ignore scope expansion

    func testIgnoreFileSkipsEverything() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        // i18n-ignore-file
        struct View: View {
            var body: some View {
                Text("Ignored")
                Button("Also ignored") { }
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.isEmpty, "// i18n-ignore-file should skip all strings in the file")
    }

    func testIgnoreNextSkipsOneCall() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                // i18n-ignore-next
                Text("Skipped")
                Text("Extracted")
            }
        }
        """, tmp: tmp)
        XCTAssertFalse(strings.values.contains("Skipped"), "// i18n-ignore-next should skip the next call")
        XCTAssertTrue(strings.values.contains("Extracted"), "Following calls should still be extracted")
    }

    func testIgnoreBlockSkipsRange() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                Text("Before")
                // i18n-ignore-block
                Text("Inside block")
                Button("Also block") { }
                // i18n-end-ignore
                Text("After")
            }
        }
        """, tmp: tmp)
        XCTAssertTrue(strings.values.contains("Before"), "Text before block should be extracted")
        XCTAssertFalse(strings.values.contains("Inside block"), "// i18n-ignore-block should skip text inside block")
        XCTAssertFalse(strings.values.contains("Also block"), "// i18n-ignore-block should skip button inside block")
        XCTAssertTrue(strings.values.contains("After"), "Text after // i18n-end-ignore should be extracted")
    }

    func testLegacyIgnoreStillWorks() throws {
        let tmp = try makeTempDir()
        let (strings, _) = try _runExtraction(on: """
        struct View: View {
            var body: some View {
                // i18n-ignore
                Text("Skipped")
            }
        }
        """, tmp: tmp)
        XCTAssertFalse(strings.values.contains("Skipped"), "// i18n-ignore should still work")
    }

    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("i18n-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
