import Foundation

/// Glossary maps source terms to preferred translations per language.
/// Injected into the LLM system prompt for domain-aware translations.
struct Glossary: Codable {
    struct Entry: Codable {
        let term: String
        let translations: [String: String]  // [languageCode: preferredTranslation]
        let context: String?
    }

    var entries: [Entry]

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        self = try decoder.decode(Glossary.self, from: data)

    }

    /// Build system prompt appendix from glossary entries for a target language.
    func systemPromptAppendix(for targetLang: String) -> String {
        let relevant = entries.filter { $0.translations[targetLang] != nil }
        guard !relevant.isEmpty else { return "" }

        var lines: [String] = ["\nGlossary terms (use these translations):"]
        for entry in relevant {
            let translation = entry.translations[targetLang]!
            if let context = entry.context {
                lines.append("- \"\(entry.term)\" → \"\(translation)\" (context: \(context))")
            } else {
                lines.append("- \"\(entry.term)\" → \"\(translation)\"")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum GlossaryError: LocalizedError {
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let msg):
            return "Failed to load glossary: \(msg)"
        }
    }
}
