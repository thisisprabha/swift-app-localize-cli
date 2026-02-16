import Foundation

enum StringsError: Error {
    case readFailed
    case writeFailed
}

func loadStrings(at url: URL) throws -> [String: String] {
    let data = try Data(contentsOf: url)
    guard let raw = String(data: data, encoding: .utf8) else {
        throw StringsError.readFailed
    }

    var dict: [String: String] = [:]

    let pattern = #"^\s*\"([^\"]+)\"\s*=\s*\"((?:[^\"\\]|\\.)*)\"\s*;\s*$"#
    let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])

    let nsString = raw as NSString
    let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsString.length))

    for match in matches {
        if match.numberOfRanges == 3 {
            let key = nsString.substring(with: match.range(at: 1))
            let value = nsString.substring(with: match.range(at: 2))
            dict[key] = value
        }
    }

    return dict
}

func loadStringsIfExists(at url: URL) throws -> [String: String] {
    if FileManager.default.fileExists(atPath: url.path) {
        return try loadStrings(at: url)
    }
    return [:]
}

func saveStrings(_ dict: [String: String], to url: URL) throws {
    var lines: [String] = []
    for key in dict.keys.sorted() {
        let value = dict[key] ?? ""
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        lines.append("\"\(key)\" = \"\(escaped)\";")
    }
    let output = lines.joined(separator: "\n") + "\n"
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = output.data(using: .utf8) else {
            throw StringsError.writeFailed
        }
        try data.write(to: url)
    } catch {
        throw StringsError.writeFailed
    }
}
