import Foundation
import XCTest
@testable import i18n_cli

final class PlaceholderValidatorTests: XCTestCase {
    func testExtractSpecifiers() {
        let specs = PlaceholderValidator.extractSpecifiers("%d items, %@ name, %.2f price")
        XCTAssertTrue(specs.contains("%d"))
        XCTAssertTrue(specs.contains("%@"))
        XCTAssertTrue(specs.contains("%.2f"))
        XCTAssertEqual(specs.count, 3)
    }

    func testExtractNewline() {
        let specs = PlaceholderValidator.extractSpecifiers("line1\\nline2")
        XCTAssertTrue(specs.contains("\\n"))
    }

    func testValidationPasses() {
        let results = PlaceholderValidator.validate(
            source: "%d items",
            translation: "%d articles"
        )
        for r in results {
            guard case .mismatch = r else { continue }
            XCTFail("Expected all matches, got: \(r)")
        }
    }

    func testValidationFails() {
        let results = PlaceholderValidator.validate(
            source: "%d items and %@ name",
            translation: "articles"
        )
        let mismatches = results.filter { if case .mismatch = $0 { return true }; return false }
        XCTAssertGreaterThanOrEqual(mismatches.count, 1)
    }

    func testNoSpecifiersIsMatch() {
        let results = PlaceholderValidator.validate(source: "Hello", translation: "Bonjour")
        XCTAssertEqual(results.count, 1)
        if case .match = results[0] { } else { XCTFail() }
    }
}
