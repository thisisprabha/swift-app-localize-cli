import Foundation
import SwiftParser
import SwiftSyntax

enum ExtractError: LocalizedError {
    case invalidProjectRoot(String)
    case readFileFailed(String)
    case writeFileFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectRoot(let path):
            return "Invalid project root: \(path)"
        case .readFileFailed(let path):
            return "Failed to read file: \(path)"
        case .writeFileFailed(let path):
            return "Failed to write file: \(path)"
        }
    }
}

struct SwiftUIExtractorEngine {
    let keyPrefix: String
    let overwriteExisting: Bool
    let noSkipKeys: Bool
    let applyChanges: Bool
    let dryRun: Bool
    let stringsdictMode: StringsdictMode
    let include: [String]
    let exclude: [String]
    let reportURL: URL

    private let defaultExcludedDirNames: Set<String> = [
        ".build", "DerivedData", "Pods", "Carthage", "Tests", ".git", ".swiftpm"
    ]

    func run(projectRoot root: URL, baseLang: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw ExtractError.invalidProjectRoot(root.path)
        }

        let baseStringsURL = root
            .appendingPathComponent("\(baseLang).lproj")
            .appendingPathComponent("Localizable.strings")

        var baseStrings = (try? loadStringsIfExists(at: baseStringsURL)) ?? [:]

        let keygen = KeyGenerator(prefix: keyPrefix)
        let files = try enumerateSwiftFiles(root: root)

        var foundLiterals = 0
        var extractedCount = 0
        var rewrittenCount = 0

        var rewrittenItems: [ExtractReport.Item] = []
        var skippedItems: [ExtractReport.Item] = []
        var interpolationItems: [ExtractReport.Item] = []
        var stringsdictCandidates: [ExtractReport.Item] = []
        var stringsdictGenerated: [ExtractReport.Item] = []

        var generatedStringsdictEntries: [String: Any] = [:]

        for fileURL in files {
            let path = fileURL.path
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else {
                skippedItems.append(.init(file: path, line: 1, context: "file", original: "", key: nil, reason: "read_failed"))
                continue
            }

            let tree = Parser.parse(source: source)
            let converter = SourceLocationConverter(fileName: path, tree: tree)

            let collector = SwiftUILiteralCollector(
                filePath: path,
                source: source,
                converter: converter,
                keygen: keygen,
                noSkipKeys: noSkipKeys
            )
            collector.walk(tree)

            foundLiterals += collector.matches.count + collector.skipped.count + collector.interpolations.count

            // Merge extracted keys into base strings.
            for match in collector.matches {
                extractedCount += 1
                if baseStrings[match.key] == nil || overwriteExisting {
                    baseStrings[match.key] = match.original
                }

                if isFormatCandidate(match.original) {
                    if stringsdictMode == .auto,
                       let plural = buildPluralForms(from: match.original) {
                        generatedStringsdictEntries[match.key] = makePluralStringsdictEntry(
                            singular: plural.singular,
                            other: plural.other,
                            valueType: plural.valueType
                        )
                        stringsdictGenerated.append(.init(
                            file: path,
                            line: match.line,
                            context: match.context,
                            original: match.original,
                            key: match.key,
                            reason: "auto_generated"
                        ))
                    } else {
                        stringsdictCandidates.append(.init(
                            file: path,
                            line: match.line,
                            context: match.context,
                            original: match.original,
                            key: match.key,
                            reason: "format_ambiguous"
                        ))
                    }
                }

                rewrittenItems.append(.init(
                    file: path,
                    line: match.line,
                    context: match.context,
                    original: match.original,
                    key: match.key,
                    reason: dryRun ? "dry_run" : nil
                ))
            }

            for skip in collector.skipped {
                skippedItems.append(.init(
                    file: path,
                    line: skip.line,
                    context: skip.context,
                    original: skip.original,
                    key: skip.key,
                    reason: skip.reason
                ))
            }

            for interp in collector.interpolations {
                interpolationItems.append(.init(
                    file: path,
                    line: interp.line,
                    context: interp.context,
                    original: interp.original,
                    key: nil,
                    reason: "interpolation"
                ))
            }

            // Apply rewrites to source only when requested.
            if applyChanges && !dryRun, !collector.edits.isEmpty {
                let updated = applyEdits(source: source, edits: collector.edits)
                do {
                    try updated.data(using: .utf8)?.write(to: fileURL)
                    rewrittenCount += collector.edits.count
                } catch {
                    throw ExtractError.writeFileFailed(path)
                }
            }
        }

        // Always write/update base Localizable.strings.
        try saveStrings(baseStrings, to: baseStringsURL)
        print("Wrote base strings -> \(baseStringsURL.path) (\(baseStrings.count) keys)")

        if stringsdictMode == .auto, !generatedStringsdictEntries.isEmpty {
            let baseStringsdictURL = root
                .appendingPathComponent("\(baseLang).lproj")
                .appendingPathComponent("Localizable.stringsdict")

            let existing = (try? loadStringsdictIfExists(at: baseStringsdictURL)) ?? [:]
            let merged = mergeStringsdictEntries(
                base: existing,
                entries: generatedStringsdictEntries,
                overwrite: overwriteExisting
            )
            try saveStringsdict(merged, to: baseStringsdictURL)
            print("Wrote base stringsdict -> \(baseStringsdictURL.path) (\(generatedStringsdictEntries.count) entries)")
        }

        let report = ExtractReport(
            summary: .init(
                scannedFiles: files.count,
                foundLiterals: foundLiterals,
                extracted: extractedCount,
                rewritten: rewrittenCount,
                skipped: skippedItems.count,
                interpolations: interpolationItems.count,
                stringsdictCandidates: stringsdictCandidates.count,
                stringsdictGenerated: stringsdictGenerated.count,
                dryRun: dryRun
            ),
            rewritten: rewrittenItems.sorted(by: reportSort),
            skipped: skippedItems.sorted(by: reportSort),
            interpolations: interpolationItems.sorted(by: reportSort),
            stringsdictCandidates: stringsdictCandidates.sorted(by: reportSort),
            stringsdictGenerated: stringsdictGenerated.sorted(by: reportSort)
        )

        try writeExtractReport(report, to: reportURL)
        print("Wrote extract report -> \(reportURL.path)")
    }

    private func enumerateSwiftFiles(root: URL) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var out: [URL] = []
        for case let url as URL in enumerator {
            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")

            if shouldExclude(relativePath: rel) {
                if isDirectory(url) {
                    enumerator.skipDescendants()
                }
                continue
            }

            if url.pathExtension == "swift", !isDirectory(url) {
                out.append(url)
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private func shouldExclude(relativePath: String) -> Bool {
        let parts = relativePath.split(separator: "/").map(String.init)
        if parts.contains(where: { defaultExcludedDirNames.contains($0) }) {
            return true
        }

        if !exclude.isEmpty {
            for ex in exclude {
                if relativePath.hasPrefix(ex) || parts.contains(ex) {
                    return true
                }
            }
        }

        if !include.isEmpty {
            for inc in include {
                if relativePath.hasPrefix(inc) {
                    return false
                }
            }
            return true
        }

        return false
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}

private func reportSort(_ a: ExtractReport.Item, _ b: ExtractReport.Item) -> Bool {
    if a.file != b.file { return a.file < b.file }
    if a.line != b.line { return a.line < b.line }
    return a.context < b.context
}

private func isFormatCandidate(_ text: String) -> Bool {
    return text.range(of: #"%(@|d|ld|lld|f|\.?\d*f)"#, options: .regularExpression) != nil
}

private struct PluralForms {
    let singular: String
    let other: String
    let valueType: String
}

private func buildPluralForms(from text: String) -> PluralForms? {
    let allowedSpecRegex = try? NSRegularExpression(pattern: #"%((lld)|(ld)|d)"#)
    let anyPercentRegex = try? NSRegularExpression(pattern: #"%+"#)
    let nsText = text as NSString

    guard let allowedSpecRegex,
          let anyPercentRegex else {
        return nil
    }

    let allowedMatches = allowedSpecRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
    let anyPercentMatches = anyPercentRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

    // Strict: exactly one integer format specifier and no other % usage.
    guard allowedMatches.count == 1, anyPercentMatches.count == 1 else {
        return nil
    }

    let specRange = allowedMatches[0].range
    let spec = nsText.substring(with: specRange)
    let valueType: String
    if spec.contains("lld") {
        valueType = "lld"
    } else if spec.contains("ld") {
        valueType = "ld"
    } else {
        valueType = "d"
    }

    let pattern = #"^(.*?)(%(?:lld|ld|d))\s+([A-Za-z]+(?:\(s\)|es|s))(.*)$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
          match.numberOfRanges == 5 else {
        return nil
    }

    let prefix = nsText.substring(with: match.range(at: 1))
    let token = nsText.substring(with: match.range(at: 3))
    let suffix = nsText.substring(with: match.range(at: 4))

    guard let singularWord = singularize(token: token) else {
        return nil
    }

    let pluralWord = token.replacingOccurrences(of: "(s)", with: "s")
    let singular = "\(prefix)\(spec) \(singularWord)\(suffix)"
    let other = "\(prefix)\(spec) \(pluralWord)\(suffix)"
    return PluralForms(singular: singular, other: other, valueType: valueType)
}

private func singularize(token: String) -> String? {
    if token.contains("(s)") {
        return token.replacingOccurrences(of: "(s)", with: "")
    }

    if token.hasSuffix("ies") {
        return String(token.dropLast(3)) + "y"
    }

    let lower = token.lowercased()
    if lower.hasSuffix("ches") || lower.hasSuffix("shes") || lower.hasSuffix("xes") || lower.hasSuffix("ses") {
        return String(token.dropLast(2))
    }

    if token.hasSuffix("es") {
        let base = String(token.dropLast(2))
        let lowerBase = base.lowercased()
        if lowerBase.hasSuffix("s") || lowerBase.hasSuffix("x") || lowerBase.hasSuffix("z")
            || lowerBase.hasSuffix("ch") || lowerBase.hasSuffix("sh") {
            return base
        }
        // Treat like a simple trailing "s" for words ending with "e" (e.g., "moves" -> "move").
        if token.dropLast(1).hasSuffix("e") {
            return String(token.dropLast(1))
        }
        return nil
    }

    if token.hasSuffix("ss") {
        return nil
    }

    if token.hasSuffix("s") {
        return String(token.dropLast(1))
    }

    return nil
}

struct SourceEdit {
    let start: Int
    let end: Int
    let replacement: String
}

private func applyEdits(source: String, edits: [SourceEdit]) -> String {
    var bytes = Array(source.utf8)
    for edit in edits.sorted(by: { $0.start > $1.start }) {
        let rep = Array(edit.replacement.utf8)
        if edit.start >= 0, edit.end <= bytes.count, edit.start <= edit.end {
            bytes.replaceSubrange(edit.start..<edit.end, with: rep)
        }
    }
    return String(decoding: bytes, as: UTF8.self)
}

final class SwiftUILiteralCollector: SyntaxVisitor {
    struct Match {
        let key: String
        let original: String
        let context: String
        let line: Int
        let startUTF8: Int
        let endUTF8: Int
    }

    struct Skip {
        let key: String?
        let original: String
        let context: String
        let line: Int
        let reason: String
    }

    struct Interpolation {
        let original: String
        let context: String
        let line: Int
    }

    let filePath: String
    let source: String
    let converter: SourceLocationConverter
    let keygen: KeyGenerator
    let noSkipKeys: Bool

    var matches: [Match] = []
    var skipped: [Skip] = []
    var interpolations: [Interpolation] = []
    var edits: [SourceEdit] = []

    init(
        filePath: String,
        source: String,
        converter: SourceLocationConverter,
        keygen: KeyGenerator,
        noSkipKeys: Bool
    ) {
        self.filePath = filePath
        self.source = source
        self.converter = converter
        self.keygen = keygen
        self.noSkipKeys = noSkipKeys
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let context = callContext(node)
        guard !context.isEmpty else { return .visitChildren }

        if triviaHasIgnore(node.leadingTrivia) {
            // Skip entire callsite if ignore comment is attached.
            return .skipChildren
        }

        guard let firstArg = node.arguments.first else { return .visitChildren }
        if let label = firstArg.label?.text, label == "verbatim" {
            recordSkip(expr: firstArg.expression, context: context, reason: "verbatim")
            return .visitChildren
        }

        guard let literal = firstArg.expression.as(StringLiteralExprSyntax.self) else { return .visitChildren }

        let loc = converter.location(for: literal.positionAfterSkippingLeadingTrivia)
        let line = loc.line

        if isRawOrMultiline(literal) {
            skipped.append(.init(key: nil, original: literal.description, context: context, line: line, reason: "raw_or_multiline"))
            return .visitChildren
        }

        if containsInterpolation(literal) {
            interpolations.append(.init(original: literal.description, context: context, line: line))
            skipped.append(.init(key: nil, original: literal.description, context: context, line: line, reason: "interpolation"))
            return .visitChildren
        }

        let english = unescapedLiteralText(literal) ?? ""
        if !noSkipKeys, keygen.isAlreadyKeyLike(english) {
            skipped.append(.init(key: nil, original: english, context: context, line: line, reason: "already_key_like"))
            return .visitChildren
        }

        let key = keygen.makeKey(forEnglish: english)

        let start = literal.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = literal.endPositionBeforeTrailingTrivia.utf8Offset

        matches.append(.init(
            key: key,
            original: english,
            context: context,
            line: line,
            startUTF8: start,
            endUTF8: end
        ))

        edits.append(.init(start: start, end: end, replacement: "\"\(key)\""))
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        // Detect .title = "..." patterns on UIKit types
        // SequenceExpr wraps: [MemberAccessExpr, AssignmentExpr, StringLiteralExpr]
        let elements = Array(node.elements)
        guard elements.count == 3 else { return .visitChildren }
        guard let leftMember = elements[0].as(MemberAccessExprSyntax.self) else { return .visitChildren }
        let propertyName = leftMember.declName.baseName.text
        guard propertyName == "title" else { return .visitChildren }
        guard elements[1].is(AssignmentExprSyntax.self) else { return .visitChildren }
        guard let literal = elements[2].as(StringLiteralExprSyntax.self) else { return .visitChildren }

        let loc = converter.location(for: literal.positionAfterSkippingLeadingTrivia)

        if containsInterpolation(literal) {
            interpolations.append(.init(original: literal.description, context: ".title =", line: loc.line))
            return .visitChildren
        }

        let english = unescapedLiteralText(literal) ?? ""
        if !noSkipKeys, keygen.isAlreadyKeyLike(english) {
            skipped.append(.init(key: nil, original: english, context: ".title =", line: loc.line, reason: "already_key_like"))
            return .visitChildren
        }

        let key = keygen.makeKey(forEnglish: english)
        let start = literal.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = literal.endPositionBeforeTrailingTrivia.utf8Offset

        matches.append(.init(
            key: key,
            original: english,
            context: ".title =",
            line: loc.line,
            startUTF8: start,
            endUTF8: end
        ))

        edits.append(.init(start: start, end: end, replacement: "\"\(key)\""))
        return .visitChildren
    }

    private func recordSkip(expr: ExprSyntax, context: String, reason: String) {
        let pos = expr.positionAfterSkippingLeadingTrivia
        let line = converter.location(for: pos).line
        skipped.append(.init(key: nil, original: expr.description, context: context, line: line, reason: reason))
    }

    private func callContext(_ node: FunctionCallExprSyntax) -> String {
        if let decl = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = decl.baseName.text
            switch name {
            case "Text", "Button", "Label",
                 "Section", "Toggle", "Picker", "Menu", "TextField", "Link",
                 "NavigationLink", "ProgressView", "GroupBox",
                 "DisclosureGroup", "ShareLink":
                return name
            case "NSLocalizedString":
                // Already localized (Apple macro)
                return ""
            case "String":
                // Only skip if it's String(localized:)
                if let firstLabel = node.arguments.first?.label?.text, firstLabel == "localized" {
                    return ""
                }
                return ""
            default:
                return ""
            }
        }

        if let member = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            if name == "navigationTitle" || name == "alert" || name == "confirmationDialog" {
                return ".\(name)"
            }
            return ""
        }

        return ""
    }

    private func triviaHasIgnore(_ trivia: Trivia) -> Bool {
        for piece in trivia {
            switch piece {
            case .lineComment(let text), .blockComment(let text), .docLineComment(let text), .docBlockComment(let text):
                if text.contains("i18n-ignore") { return true }
            default:
                continue
            }
        }
        return false
    }

    private func isRawOrMultiline(_ literal: StringLiteralExprSyntax) -> Bool {
        let open = literal.openingQuote.text
        if open.contains("#") { return true }
        if open.contains("\"\"\"") { return true }
        return false
    }

    private func containsInterpolation(_ literal: StringLiteralExprSyntax) -> Bool {
        for seg in literal.segments {
            if seg.as(ExpressionSegmentSyntax.self) != nil {
                return true
            }
        }
        return false
    }

    private func unescapedLiteralText(_ literal: StringLiteralExprSyntax) -> String? {
        // For simple literals without interpolation, segments are all string segments.
        var out = ""
        for seg in literal.segments {
            if let s = seg.as(StringSegmentSyntax.self) {
                out.append(s.content.text)
            } else {
                return nil
            }
        }
        return out
    }
}
