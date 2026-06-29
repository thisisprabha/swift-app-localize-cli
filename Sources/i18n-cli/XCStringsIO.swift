import Foundation

// MARK: - Dynamic coding key for sorted dictionary encoding

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        self.stringValue = string
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - Codable model types for .xcstrings (Xcode 15+ String Catalog format)

struct XCStringsDocument: Codable {
    var sourceLanguage: String
    var version: String
    var strings: [String: XCStringsEntry]

    enum CodingKeys: String, CodingKey {
        case sourceLanguage
        case version
        case strings
    }

    init(sourceLanguage: String, version: String, strings: [String: XCStringsEntry]) {
        self.sourceLanguage = sourceLanguage
        self.version = version
        self.strings = strings
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceLanguage, forKey: .sourceLanguage)
        try container.encode(version, forKey: .version)
        var stringsContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .strings)
        for key in strings.keys.sorted() {
            try stringsContainer.encodeIfPresent(strings[key], forKey: DynamicCodingKey(key))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLanguage = try container.decode(String.self, forKey: .sourceLanguage)
        version = try container.decode(String.self, forKey: .version)
        strings = try container.decode([String: XCStringsEntry].self, forKey: .strings)
    }
}

struct XCStringsEntry {
    var extractionState: ExtractionState?
    var comment: String?
    var localizations: [String: XCLocalization]

    enum CodingKeys: String, CodingKey {
        case extractionState
        case comment
        case localizations
    }
}

extension XCStringsEntry: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(extractionState, forKey: .extractionState)
        try container.encodeIfPresent(comment, forKey: .comment)
        var locContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .localizations)
        for lang in localizations.keys.sorted() {
            try locContainer.encodeIfPresent(localizations[lang], forKey: DynamicCodingKey(lang))
        }
    }
}

extension XCStringsEntry: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        extractionState = try container.decodeIfPresent(ExtractionState.self, forKey: .extractionState)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        localizations = try container.decode([String: XCLocalization].self, forKey: .localizations)
    }
}

struct XCLocalization: Codable {
    var stringUnit: XCStringUnit?
    var variations: XCPluralVariations?

    enum CodingKeys: String, CodingKey {
        case stringUnit
        case variations
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(stringUnit, forKey: .stringUnit)
        try container.encodeIfPresent(variations, forKey: .variations)
    }
}

struct XCStringUnit: Codable {
    var state: StringUnitState
    var value: String
}

struct XCPluralVariations: Codable {
    var plural: [String: XCStringUnit]

    enum CodingKeys: String, CodingKey {
        case plural
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var pluralContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .plural)
        for key in plural.keys.sorted() {
            try pluralContainer.encodeIfPresent(plural[key], forKey: DynamicCodingKey(key))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plural = try container.decode([String: XCStringUnit].self, forKey: .plural)
    }
}

// MARK: - State enums

enum ExtractionState: String, Codable {
    case extractedWithValue = "extracted_with_value"
    case manual
    case stale
    case migrated
}

enum StringUnitState: String, Codable {
    case translated
    case needsReview = "needs_review"
    case new
}

// MARK: - Reader

enum XCStringsIOError: LocalizedError {
    case readFailed(URL)
    case writeFailed(URL)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .readFailed(let url):
            return "Failed to read .xcstrings file: \(url.path)"
        case .writeFailed(let url):
            return "Failed to write .xcstrings file: \(url.path)"
        case .decodeFailed(let message):
            return "Failed to decode .xcstrings: \(message)"
        }
    }
}

enum XCStringsIO {
    /// Read .xcstrings JSON from a file URL.
    static func read(from url: URL) throws -> XCStringsDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XCStringsIOError.readFailed(url)
        }
        return try read(from: data)
    }

    /// Read .xcstrings JSON from raw Data.
    static func read(from data: Data) throws -> XCStringsDocument {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(XCStringsDocument.self, from: data)
        } catch let decodingError as DecodingError {
            throw XCStringsIOError.decodeFailed(decodingError.localizedDescription)
        } catch {
            throw XCStringsIOError.decodeFailed(error.localizedDescription)
        }
    }

    /// Build an XCStringsDocument from extracted key-value pairs.
    static func document(
        from strings: [String: String],
        comments: [String: String] = [:],
        sourceLanguage: String = "en"
    ) -> XCStringsDocument {
        var entries: [String: XCStringsEntry] = [:]

        for key in strings.keys.sorted() {
            let value = strings[key] ?? ""
            let entry = XCStringsEntry(
                extractionState: .extractedWithValue,
                comment: comments[key],
                localizations: [
                    sourceLanguage: XCLocalization(
                        stringUnit: XCStringUnit(state: .translated, value: value),
                        variations: nil
                    )
                ]
            )
            entries[key] = entry
        }

        return XCStringsDocument(
            sourceLanguage: sourceLanguage,
            version: "1.0",
            strings: entries
        )
    }

    // MARK: - Writer

    /// Encode an XCStringsDocument to pretty-printed JSON Data.
    static func encode(_ document: XCStringsDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// Write an XCStringsDocument to a file URL.
    static func write(_ document: XCStringsDocument, to url: URL) throws {
        let data: Data
        do {
            data = try encode(document)
        } catch {
            throw XCStringsIOError.writeFailed(url)
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        } catch {
            throw XCStringsIOError.writeFailed(url)
        }
    }
}
