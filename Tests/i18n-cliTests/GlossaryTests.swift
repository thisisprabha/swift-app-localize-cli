import Foundation
import XCTest
@testable import i18n_cli

final class GlossaryTests: XCTestCase {
    func testSystemPromptAppendix() throws {
        let json = """
        {
          "entries": [
            {
              "term": "Run",
              "translations": { "fr": "Courir", "de": "Laufen" },
              "context": "fitness app button"
            }
          ]
        }
        """
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("glossary-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: tmp)

        let glossary = try Glossary(path: tmp.path)
        let appendix = glossary.systemPromptAppendix(for: "fr")
        XCTAssertTrue(appendix.contains("Courir"), "French translation should appear in prompt")
        XCTAssertTrue(appendix.contains("fitness app"), "Context should appear in prompt")

        let deAppendix = glossary.systemPromptAppendix(for: "de")
        XCTAssertTrue(deAppendix.contains("Laufen"), "German translation should appear")

        try FileManager.default.removeItem(at: tmp)
    }

    func testEmptyGlossary() throws {
        let json = """
        {
          "entries": []
        }
        """
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("glossary-\(UUID().uuidString).json")
        try json.data(using: .utf8)!.write(to: tmp)

        let glossary = try Glossary(path: tmp.path)
        let appendix = glossary.systemPromptAppendix(for: "fr")
        XCTAssertTrue(appendix.isEmpty, "Empty glossary should produce no appendix")

        try FileManager.default.removeItem(at: tmp)
    }
}
