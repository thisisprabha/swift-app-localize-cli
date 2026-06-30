import Foundation

/// --context-screenshots <dir> support for vision-capable LLMs.
/// Scans a directory for screenshot images and includes them in the translation prompt
/// so the LLM can see the UI context where each string appears.
struct ContextScreenshots {
    let directory: URL

    init?(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        self.directory = url
    }

    /// List screenshot files in the directory (png, jpg, jpeg, gif).
    var files: [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif"].contains(ext) {
                results.append(url)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Build a system prompt appendix describing available screenshots.
    func systemPromptAppendix(for targetLang: String) -> String {
        let screenshots = files
        guard !screenshots.isEmpty else { return "" }
        var lines: [String] = ["\nAvailable UI screenshots for context:"]
        for url in screenshots {
            lines.append("- \(url.lastPathComponent)")
        }
        lines.append("Use these screenshots to understand the UI context of each string.")
        return lines.joined(separator: "\n")
    }
}
