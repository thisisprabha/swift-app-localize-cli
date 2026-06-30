import Foundation
import XCTest
@testable import i18n_cli

final class TranslationMemoryTests: XCTestCase {
    func testLookupMiss() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tm = TranslationMemory(projectRoot: root)
        XCTAssertNil(tm.lookup(source: "Hello", targetLang: "fr"))
    }

    func testStoreAndLookup() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var tm = TranslationMemory(projectRoot: root)
        tm.store(source: "Hello", targetLang: "fr", translation: "Bonjour")
        XCTAssertEqual(tm.lookup(source: "Hello", targetLang: "fr"), "Bonjour")
    }
}
