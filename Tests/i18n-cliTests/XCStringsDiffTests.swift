import Foundation
import XCTest

@testable import i18n_cli

final class XCStringsDiffTests: XCTestCase {

    // MARK: - Helpers

    typealias Translation = (lang: String, state: StringUnitState, value: String)

    func makeDocument(lang: String, keys: [String: String]) -> XCStringsDocument {
        var entries: [String: XCStringsEntry] = [:]
        for (key, value) in keys {
            entries[key] = XCStringsEntry(
                extractionState: .extractedWithValue,
                comment: nil,
                localizations: [
                    lang: XCLocalization(
                        stringUnit: XCStringUnit(state: .translated, value: value),
                        variations: nil
                    )
                ]
            )
        }
        return XCStringsDocument(sourceLanguage: lang, version: "1.0", strings: entries)
    }

    func makeDocumentWithTranslations(
        sourceLang: String,
        entries: [String: (sourceValue: String, translations: [Translation])]
    ) -> XCStringsDocument {
        var docs: [String: XCStringsEntry] = [:]
        for (key, (sourceValue, translations)) in entries {
            var locs: [String: XCLocalization] = [
                sourceLang: XCLocalization(
                    stringUnit: XCStringUnit(state: .translated, value: sourceValue),
                    variations: nil
                )
            ]
            for t in translations {
                locs[t.lang] = XCLocalization(
                    stringUnit: XCStringUnit(state: t.state, value: t.value),
                    variations: nil
                )
            }
            docs[key] = XCStringsEntry(
                extractionState: nil,
                comment: nil,
                localizations: locs
            )
        }
        return XCStringsDocument(sourceLanguage: sourceLang, version: "1.0", strings: docs)
    }

    // MARK: - needsTranslation tests

    func testNoCacheMeansAllKeysNeedTranslation() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.hello_11111111": "Hello",
            "app.world_22222222": "World"
        ])

        let needs = XCStringsDiffEngine.needsTranslation(source: source, targetLanguage: "fr", cache: nil)
        XCTAssertEqual(needs.count, 2)
        XCTAssertEqual(needs["app.hello_11111111"], "Hello")
        XCTAssertEqual(needs["app.world_22222222"], "World")
    }

    func testNewKeysDetected() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.hello_11111111": "Hello",
            "app.world_22222222": "World"
        ])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.hello_11111111": (sourceValue: "Hello", translations: [(lang: "fr", state: .translated, value: "Bonjour")])
        ])

        let needs = XCStringsDiffEngine.needsTranslation(source: source, targetLanguage: "fr", cache: cache)
        XCTAssertEqual(needs.count, 1)
        XCTAssertEqual(needs["app.world_22222222"], "World")
    }

    func testStaleTranslationDetected() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.hello_11111111": "Hello World"
        ])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.hello_11111111": (sourceValue: "Hello", translations: [(lang: "fr", state: .translated, value: "Bonjour")])
        ])

        let needs = XCStringsDiffEngine.needsTranslation(source: source, targetLanguage: "fr", cache: cache)
        XCTAssertEqual(needs.count, 1, "Source English changed, should need retranslation")
    }

    func testUntranslatedLanguageDetected() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.hello_11111111": "Hello"
        ])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.hello_11111111": (sourceValue: "Hello", translations: [(lang: "de", state: .translated, value: "Hallo")])
        ])

        let needs = XCStringsDiffEngine.needsTranslation(source: source, targetLanguage: "fr", cache: cache)
        XCTAssertEqual(needs.count, 1, "French is missing from cache, should need translation")
    }

    func testAlreadyTranslatedSkipped() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.hello_11111111": "Hello"
        ])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.hello_11111111": (sourceValue: "Hello", translations: [(lang: "fr", state: .translated, value: "Bonjour")])
        ])

        let needs = XCStringsDiffEngine.needsTranslation(source: source, targetLanguage: "fr", cache: cache)
        XCTAssertEqual(needs.count, 0)
    }

    func testEmptySource() throws {
        let source = makeDocument(lang: "en", keys: [:])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.hello_11111111": (sourceValue: "Hello", translations: [(lang: "fr", state: .translated, value: "Bonjour")])
        ])

        let needs = XCStringsDiffEngine.needsTranslation(source: source, targetLanguage: "fr", cache: cache)
        XCTAssertEqual(needs.count, 0)
    }

    // MARK: - Full diff tests

    func testFullDiffNewAndUnchanged() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.a_11111111": "A",
            "app.b_22222222": "B"
        ])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.a_11111111": (sourceValue: "A", translations: [(lang: "fr", state: .translated, value: "A-fr")])
        ])

        let diff = XCStringsDiffEngine.diff(source: source, cache: cache, targetLanguage: "fr")
        XCTAssertEqual(diff.added.count, 1)
        XCTAssertEqual(diff.added.first?.key, "app.b_22222222")
        XCTAssertEqual(diff.translated.count, 1)
        XCTAssertEqual(diff.translated.first?.key, "app.a_11111111")
    }

    func testFullDiffRemovedKeys() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.a_11111111": "A"
        ])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.a_11111111": (sourceValue: "A", translations: [(lang: "fr", state: .translated, value: "A-fr")]),
            "app.deleted_99999999": (sourceValue: "Deleted", translations: [(lang: "fr", state: .translated, value: "Supprimé")])
        ])

        let diff = XCStringsDiffEngine.diff(source: source, cache: cache, targetLanguage: "fr")
        XCTAssertEqual(diff.removed.count, 1)
        XCTAssertEqual(diff.removed.first?.key, "app.deleted_99999999")
    }

    func testFullDiffNoCacheProducesAllAdded() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.a_11111111": "A",
            "app.b_22222222": "B"
        ])

        let diff = XCStringsDiffEngine.diff(source: source, cache: nil, targetLanguage: "fr")
        XCTAssertEqual(diff.added.count, 2)
        XCTAssertEqual(diff.translated.count, 0)
    }

    func testFullDiffChangedSource() throws {
        let source = makeDocument(lang: "en", keys: [
            "app.hello_11111111": "Hi there"
        ])
        let cache = makeDocumentWithTranslations(sourceLang: "en", entries: [
            "app.hello_11111111": (sourceValue: "Hello", translations: [(lang: "fr", state: .translated, value: "Bonjour")])
        ])

        let diff = XCStringsDiffEngine.diff(source: source, cache: cache, targetLanguage: "fr")
        XCTAssertEqual(diff.changed.count, 1)
        XCTAssertEqual(diff.changed.first?.sourceValue, "Hi there")
        XCTAssertEqual(diff.changed.first?.cachedValue, "Hello")
    }

    // MARK: - Cache round-trip tests

    func testCacheWriteAndLoad() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("i18n-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let doc = makeDocument(lang: "en", keys: ["app.hello_11111111": "Hello"])
        try XCStringsDiffEngine.saveCache(doc, for: "fr", projectRoot: tmp)

        let cached = XCStringsDiffEngine.loadCache(for: "fr", projectRoot: tmp)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.strings["app.hello_11111111"]?.localizations["en"]?.stringUnit?.value, "Hello")

        try? FileManager.default.removeItem(at: tmp)
    }

    func testLoadCacheMissing() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("i18n-cli-tests-\(UUID().uuidString)")

        let cached = XCStringsDiffEngine.loadCache(for: "nonexistent", projectRoot: tmp)
        XCTAssertNil(cached)
    }

    func testCacheURLPattern() {
        let root = URL(fileURLWithPath: "/app")
        let url = XCStringsDiffEngine.cacheURL(for: "fr", projectRoot: root)
        XCTAssertEqual(url.path, "/app/.i18n-cache/fr.xcstrings-cache.json")
    }
}
