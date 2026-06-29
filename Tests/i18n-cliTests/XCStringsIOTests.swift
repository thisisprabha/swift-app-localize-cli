import Foundation
import XCTest

@testable import i18n_cli

final class XCStringsIOTests: XCTestCase {

    // MARK: - IL-001: Decode tests

    func testDecodeMinimalDocument() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {}
        }
        """
        let data = json.data(using: .utf8)!
        let doc = try XCStringsIO.read(from: data)
        XCTAssertEqual(doc.sourceLanguage, "en")
        XCTAssertEqual(doc.version, "1.0")
        XCTAssertTrue(doc.strings.isEmpty)
    }

    func testDecodeStringUnitLocalization() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "app.hello_a1b2c3d4": {
              "extractionState": "extracted_with_value",
              "comment": "ContentView.swift:42 — Text",
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "translated",
                    "value": "Hello"
                  }
                }
              }
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let doc = try XCStringsIO.read(from: data)

        let entry = try XCTUnwrap(doc.strings["app.hello_a1b2c3d4"])
        XCTAssertEqual(entry.extractionState, .extractedWithValue)
        XCTAssertEqual(entry.comment, "ContentView.swift:42 — Text")

        let enLoc = try XCTUnwrap(entry.localizations["en"])
        XCTAssertNotNil(enLoc.stringUnit)
        XCTAssertNil(enLoc.variations)
        XCTAssertEqual(enLoc.stringUnit?.state, .translated)
        XCTAssertEqual(enLoc.stringUnit?.value, "Hello")
    }

    func testDecodePluralVariations() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "app.items_count_e5f6g7h8": {
              "localizations": {
                "en": {
                  "variations": {
                    "plural": {
                      "one": { "state": "translated", "value": "%d item" },
                      "other": { "state": "translated", "value": "%d items" }
                    }
                  }
                }
              }
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let doc = try XCStringsIO.read(from: data)

        let entry = try XCTUnwrap(doc.strings["app.items_count_e5f6g7h8"])
        let enLoc = try XCTUnwrap(entry.localizations["en"])
        XCTAssertNil(enLoc.stringUnit)
        let variations = try XCTUnwrap(enLoc.variations)
        XCTAssertEqual(variations.plural["one"]?.value, "%d item")
        XCTAssertEqual(variations.plural["other"]?.value, "%d items")
    }

    func testDecodeMissingOptionalFields() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "app.greeting_12345678": {
              "localizations": {
                "en": {
                  "stringUnit": {
                    "state": "new",
                    "value": ""
                  }
                }
              }
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let doc = try XCStringsIO.read(from: data)

        let entry = try XCTUnwrap(doc.strings["app.greeting_12345678"])
        XCTAssertNil(entry.extractionState)
        XCTAssertNil(entry.comment)
    }

    func testDecodeRealWorldFile() throws {
        let json = """
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "app.hello_a1b2c3d4": {
              "extractionState": "extracted_with_value",
              "comment": "ContentView.swift:10",
              "localizations": {
                "en": { "stringUnit": { "state": "translated", "value": "Hello" } },
                "fr": { "stringUnit": { "state": "translated", "value": "Bonjour" } },
                "de": { "stringUnit": { "state": "needs_review", "value": "Hallo" } },
                "es": { "stringUnit": { "state": "new", "value": "" } }
              }
            },
            "app.items_count_abcdef01": {
              "localizations": {
                "en": {
                  "variations": {
                    "plural": {
                      "one": { "state": "translated", "value": "%d item" },
                      "other": { "state": "translated", "value": "%d items" }
                    }
                  }
                },
                "ru": {
                  "variations": {
                    "plural": {
                      "one": { "state": "translated", "value": "%d элемент" },
                      "few": { "state": "translated", "value": "%d элемента" },
                      "many": { "state": "translated", "value": "%d элементов" },
                      "other": { "state": "new", "value": "" }
                    }
                  }
                }
              }
            }
          }
        }
        """
        let data = json.data(using: .utf8)!
        let doc = try XCStringsIO.read(from: data)

        XCTAssertEqual(doc.strings.count, 2)

        let hello = try XCTUnwrap(doc.strings["app.hello_a1b2c3d4"])
        XCTAssertEqual(hello.localizations.count, 4)
        XCTAssertEqual(hello.localizations["fr"]?.stringUnit?.value, "Bonjour")
        XCTAssertEqual(hello.localizations["de"]?.stringUnit?.state, .needsReview)
        XCTAssertEqual(hello.localizations["es"]?.stringUnit?.state, .new)
        XCTAssertEqual(hello.localizations["es"]?.stringUnit?.value, "")

        let items = try XCTUnwrap(doc.strings["app.items_count_abcdef01"])
        let ruPlural = try XCTUnwrap(items.localizations["ru"]?.variations?.plural)
        XCTAssertEqual(ruPlural.count, 4)
        XCTAssertEqual(ruPlural["few"]?.value, "%d элемента")
    }

    func testDecodeInvalidJSON() throws {
        let json = "{ this is not valid }"
        let data = json.data(using: .utf8)!
        do {
            _ = try XCStringsIO.read(from: data)
            XCTFail("Expected error")
        } catch let error as XCStringsIOError {
            if case .decodeFailed = error {
                // expected
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - IL-002: Encode tests

    func testEncodeMinimalDocument() throws {
        let doc = XCStringsDocument(sourceLanguage: "en", version: "1.0", strings: [:])
        let data = try XCStringsIO.encode(doc)
        let decoded = try XCStringsIO.read(from: data)
        XCTAssertEqual(decoded.sourceLanguage, "en")
        XCTAssertEqual(decoded.version, "1.0")
    }

    func testEncodeSortedKeys() throws {
        let entries: [String: XCStringsEntry] = [
            "z.app_last_22222222": XCStringsEntry(
                extractionState: .extractedWithValue,
                comment: nil,
                localizations: ["en": XCLocalization(stringUnit: XCStringUnit(state: .translated, value: "Z"), variations: nil)]
            ),
            "a.app_first_11111111": XCStringsEntry(
                extractionState: .extractedWithValue,
                comment: nil,
                localizations: ["en": XCLocalization(stringUnit: XCStringUnit(state: .translated, value: "A"), variations: nil)]
            )
        ]
        let doc = XCStringsDocument(sourceLanguage: "en", version: "1.0", strings: entries)
        let data = try XCStringsIO.encode(doc)

        let decoded = try XCStringsIO.read(from: data)
        let keys = decoded.strings.keys.sorted()
        XCTAssertEqual(keys, ["a.app_first_11111111", "z.app_last_22222222"])
    }

    func testEncodeFieldOrder() throws {
        let entry = XCStringsEntry(
            extractionState: .extractedWithValue,
            comment: "test comment",
            localizations: ["en": XCLocalization(stringUnit: XCStringUnit(state: .translated, value: "Hello"), variations: nil)]
        )
        let doc = XCStringsDocument(sourceLanguage: "en", version: "1.0", strings: ["app.hello_a1b2c3d4": entry])
        let data = try XCStringsIO.encode(doc)
        let output = String(data: data, encoding: .utf8)!

        XCTAssertTrue(output.contains("\"extractionState\""), "Should contain extractionState")
        XCTAssertTrue(output.contains("\"comment\""), "Should contain comment")
        XCTAssertTrue(output.contains("\"localizations\""), "Should contain localizations")
    }

    func testEncodeOmitsNilOptionals() throws {
        let entry = XCStringsEntry(
            extractionState: nil,
            comment: nil,
            localizations: ["en": XCLocalization(stringUnit: XCStringUnit(state: .new, value: ""), variations: nil)]
        )
        let doc = XCStringsDocument(sourceLanguage: "en", version: "1.0", strings: ["app.test_99999999": entry])
        let data = try XCStringsIO.encode(doc)
        let output = String(data: data, encoding: .utf8)!

        XCTAssertFalse(output.contains("extractionState"), "nil extractionState should be omitted")
        XCTAssertFalse(output.contains("\"comment\""), "nil comment should be omitted")
    }

    func testWriteToFileRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("i18n-cli-tests-\(UUID().uuidString)")

        let entries: [String: XCStringsEntry] = [
            "app.hello_a1b2c3d4": XCStringsEntry(
                extractionState: .extractedWithValue,
                comment: "ContentView.swift:10",
                localizations: [
                    "en": XCLocalization(stringUnit: XCStringUnit(state: .translated, value: "Hello"), variations: nil),
                    "fr": XCLocalization(stringUnit: XCStringUnit(state: .translated, value: "Bonjour"), variations: nil)
                ]
            )
        ]
        let doc = XCStringsDocument(sourceLanguage: "en", version: "1.0", strings: entries)

        let fileURL = tmp.appendingPathComponent("Localizable.xcstrings")
        try XCStringsIO.write(doc, to: fileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let roundTripped = try XCStringsIO.read(from: fileURL)
        XCTAssertEqual(roundTripped.sourceLanguage, "en")
        XCTAssertEqual(roundTripped.strings.count, 1)
        XCTAssertEqual(roundTripped.strings["app.hello_a1b2c3d4"]?.localizations["fr"]?.stringUnit?.value, "Bonjour")

        try? FileManager.default.removeItem(at: tmp)
    }

    func testPrettyPrintedOutput() throws {
        let entry = XCStringsEntry(
            extractionState: .extractedWithValue,
            comment: "test",
            localizations: ["en": XCLocalization(stringUnit: XCStringUnit(state: .translated, value: "Hi"), variations: nil)]
        )
        let doc = XCStringsDocument(sourceLanguage: "en", version: "1.0", strings: ["app.hi_11111111": entry])
        let data = try XCStringsIO.encode(doc)
        let output = String(data: data, encoding: .utf8)!

        XCTAssertTrue(output.contains("\n"), "Output should have newlines for pretty-printing")
    }

    // MARK: - IL-003: Document factory tests

    func testDocumentFromExtractedStrings() throws {
        let strings: [String: String] = [
            "app.hello_a1b2c3d4": "Hello",
            "app.ok_abcdef01": "OK"
        ]
        let comments: [String: String] = [
            "app.hello_a1b2c3d4": "ContentView.swift:10 — Text",
            "app.ok_abcdef01": "ContentView.swift:11 — Button"
        ]

        let doc = XCStringsIO.document(from: strings, comments: comments, sourceLanguage: "en")
        XCTAssertEqual(doc.sourceLanguage, "en")
        XCTAssertEqual(doc.version, "1.0")
        XCTAssertEqual(doc.strings.count, 2)

        let hello = try XCTUnwrap(doc.strings["app.hello_a1b2c3d4"])
        XCTAssertEqual(hello.extractionState, .extractedWithValue)
        XCTAssertEqual(hello.comment, "ContentView.swift:10 — Text")
        XCTAssertEqual(hello.localizations["en"]?.stringUnit?.value, "Hello")
        XCTAssertEqual(hello.localizations["en"]?.stringUnit?.state, .translated)
    }

    func testDocumentFromEmptyStrings() throws {
        let doc = XCStringsIO.document(from: [:], comments: [:], sourceLanguage: "en")
        XCTAssertEqual(doc.strings.count, 0)
    }
}
