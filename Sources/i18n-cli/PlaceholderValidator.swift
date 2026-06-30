import Foundation

/// Validates that format specifiers in a source string are preserved in the translated output.
enum PlaceholderValidator {
    enum Severity {
        case match
        case mismatch(String)
    }

    /// Extract all format specifiers from a string (e.g. %d, %@, %.2f, %1$@, %%, \n).
    static func extractSpecifiers(_ text: String) -> [String] {
        var specs: [String] = []
        let patterns = [
            "%(\\d+\\$)?[.\\d]*[difs@DF]",
            "%%",
            "\\\\n"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let r = match?.range else { return }
                specs.append(ns.substring(with: r))
            }
        }
        return specs
    }

    /// Compare specifiers between source and translated text.
    /// Returns a severity for each specifier in source.
    static func validate(source: String, translation: String) -> [Severity] {
        let sourceSpecs = extractSpecifiers(source)
        guard !sourceSpecs.isEmpty else { return [.match] }

        var results: [Severity] = []
        for spec in sourceSpecs {
            if translation.contains(spec) {
                results.append(.match)
            } else {
                // Check for positional reordering: source has %1$@, translation has %1$@ at different position
                if spec.contains("$") {
                    // Positional specifier — check if it exists anywhere
                    if translation.range(of: spec) != nil {
                        results.append(.match)
                    } else {
                        results.append(.mismatch("Missing '\(spec)' in translation"))
                    }
                } else if spec == "%%" {
                    // Literal percent — common omission, less severe
                    if translation.contains("%%") || translation.contains("%") {
                        results.append(.match)
                    } else {
                        results.append(.mismatch("Missing '%%' in translation"))
                    }
                } else if spec == "\\n" {
                    if translation.contains("\\n") || translation.contains("\n") {
                        results.append(.match)
                    } else {
                        results.append(.mismatch("Missing newline in translation"))
                    }
                } else {
                    results.append(.mismatch("Missing '\(spec)' in translation"))
                }
            }
        }
        return results
    }

    /// Full validation of a batch of key → translated value pairs.
    /// Returns warnings for any mismatches.
    static func validateBatch(pairs: [(key: String, source: String, translation: String)]) -> [String] {
        var warnings: [String] = []
        for (key, source, translation) in pairs {
            let results = validate(source: source, translation: translation)
            for result in results {
                if case .mismatch(let msg) = result {
                    warnings.append("\(key): \(msg)")
                }
            }
        }
        return warnings
    }
}
