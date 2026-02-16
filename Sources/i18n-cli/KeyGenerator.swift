import CryptoKit
import Foundation

struct KeyGenerator {
    let prefix: String

    func makeKey(forEnglish english: String) -> String {
        let normalized = normalize(english)
        let slug = makeSlug(normalized)
        let hash = shortHash(normalized)
        return "\(prefix).\(slug)_\(hash)"
    }

    func isAlreadyKeyLike(_ value: String) -> Bool {
        if value.hasPrefix("\(prefix).") { return true }
        if value.contains(" ") { return false }
        if !value.contains(".") { return false }
        return value.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
    }

    private func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed
    }

    private func makeSlug(_ normalized: String) -> String {
        let words = normalized
            .lowercased()
            .split(separator: " ")
            .prefix(5)

        var out: [Character] = []
        out.reserveCapacity(48)

        for (idx, word) in words.enumerated() {
            if idx > 0 { out.append("_") }
            for ch in word {
                if ch.isLetter || ch.isNumber {
                    out.append(ch)
                } else if ch == "_" {
                    out.append("_")
                }
            }
        }

        var slug = String(out)
        slug = slug.replacingOccurrences(of: #"__+"#, with: "_", options: .regularExpression)
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty { slug = "string" }
        if slug.count > 32 { slug = String(slug.prefix(32)) }
        return slug
    }

    private func shortHash(_ normalized: String) -> String {
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(8).description
    }
}

