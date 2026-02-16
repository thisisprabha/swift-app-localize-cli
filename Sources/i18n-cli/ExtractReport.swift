import Foundation

struct ExtractReport: Codable {
    struct Summary: Codable {
        var scannedFiles: Int
        var foundLiterals: Int
        var extracted: Int
        var rewritten: Int
        var skipped: Int
        var interpolations: Int
        var stringsdictCandidates: Int
        var stringsdictGenerated: Int
        var dryRun: Bool
    }

    struct Item: Codable {
        var file: String
        var line: Int
        var context: String
        var original: String
        var key: String?
        var reason: String?
    }

    var summary: Summary
    var rewritten: [Item]
    var skipped: [Item]
    var interpolations: [Item]
    var stringsdictCandidates: [Item]
    var stringsdictGenerated: [Item]
}

func writeExtractReport(_ report: ExtractReport, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
}
