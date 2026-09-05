import Foundation

private struct Catalog: Decodable {
    let strings: [String: Entry]
}

private struct Entry: Decodable {
    let localizations: [String: Localization]?
}

private struct Localization: Decodable {
    let stringUnit: StringUnit?
}

private struct StringUnit: Decodable {
    let state: String
    let value: String
}

private struct ValidationFailure: LocalizedError {
    let messages: [String]

    var errorDescription: String? {
        (["Localization validation failed:"] + messages.map { "- \($0)" })
            .joined(separator: "\n")
    }
}

@main
private enum LocalizationValidator {
    static func main() throws {
        guard CommandLine.arguments.count >= 5 else {
            throw ValidationFailure(messages: [
                "Expected catalog path, AppLanguage source path, output path, and Swift source files.",
            ])
        }

        let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let appLanguageURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
        let sourceURLs = CommandLine.arguments.dropFirst(4).map(URL.init(fileURLWithPath:))
        let expectedLocales = try localeIdentifiers(in: appLanguageURL)
        let catalog = try JSONDecoder().decode(
            Catalog.self,
            from: Data(contentsOf: catalogURL)
        )

        var failures: [String] = []
        if expectedLocales.isEmpty {
            failures.append("AppLanguage declares no explicit locale identifiers.")
        }
        if catalog.strings.isEmpty {
            failures.append("The string catalog contains no user-visible strings.")
        }

        for key in catalog.strings.keys.sorted() {
            guard let localizations = catalog.strings[key]?.localizations else {
                failures.append("\(key.debugDescription) has no localizations.")
                continue
            }

            let actualLocales = Set(localizations.keys)
            let missing = expectedLocales.subtracting(actualLocales).sorted()
            let unexpected = actualLocales.subtracting(expectedLocales).sorted()
            if !missing.isEmpty {
                failures.append("\(key.debugDescription) is missing: \(missing.joined(separator: ", ")).")
            }
            if !unexpected.isEmpty {
                failures.append("\(key.debugDescription) has unsupported locales: \(unexpected.joined(separator: ", ")).")
            }

            for locale in expectedLocales.sorted() {
                guard let unit = localizations[locale]?.stringUnit else {
                    continue
                }
                if unit.state != "translated" {
                    failures.append(
                        "\(key.debugDescription) [\(locale)] has state \(unit.state.debugDescription), not translated."
                    )
                }
                if unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    failures.append("\(key.debugDescription) [\(locale)] is empty.")
                }
            }
        }
        let catalogKeys = Set(catalog.strings.keys)
        var referencedCatalogKeys: Set<String> = []
        failures.append(contentsOf: try sourceFailures(
            sourceURLs: sourceURLs,
            catalogKeys: catalogKeys,
            referencedCatalogKeys: &referencedCatalogKeys
        ))
        for key in catalogKeys.subtracting(referencedCatalogKeys).sorted() {
            failures.append(
                "\(key.debugDescription) is unused; remove it from the string catalog "
                    + "or reference it from Swift source."
            )
        }

        guard failures.isEmpty else {
            throw ValidationFailure(messages: failures)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stamp = "Validated \(catalog.strings.count) keys across \(expectedLocales.count) locales "
            + "and \(sourceURLs.count) Swift source files.\n"
        try Data(stamp.utf8).write(to: outputURL)
    }

    private static func sourceFailures(
        sourceURLs: [URL],
        catalogKeys: Set<String>,
        referencedCatalogKeys: inout Set<String>
    ) throws -> [String] {
        let localizedLiteralPatterns = [
            #"\b(?:Text|Button|Label|Picker|Toggle|Section|ProgressView|Menu|GroupBox|LocalizedStringKey|LocalizedStringResource)\s*\(\s*\"((?:\\.|[^\"\\])*)\""#,
            #"\bString\s*\(\s*localized\s*:\s*\"((?:\\.|[^\"\\])*)\""#,
            #"\.(?:help|accessibilityLabel|confirmationDialog|alert)\s*\(\s*\"((?:\\.|[^\"\\])*)\""#,
            #"\b(?:title|help|accessibilityLabel)\s*:\s*\"((?:\\.|[^\"\\])*)\""#,
            #"\b(?:messageText|informativeText|placeholderString|toolTip)\s*=\s*\"((?:\\.|[^\"\\])*)\""#,
            #"\b(?:setAccessibilityLabel|setAccessibilityHelp|addButton)\s*\([^\"\n]*\"((?:\\.|[^\"\\])*)\""#,
        ].map { try! NSRegularExpression(pattern: $0) }
        let localizedPropertyPattern = try NSRegularExpression(
            pattern: #"(?s)(?:var|func)\s+\w+[^\{\n]*:\s*(?:LocalizedStringKey|LocalizedStringResource)\s*\{(.*?)\n\s*\}"#
        )
        let stringLiteralPattern = try NSRegularExpression(
            pattern: #"\"((?:\\.|[^\"\\])*)\""#
        )
        let verbatimPattern = try NSRegularExpression(
            pattern: #"\bText\s*\(\s*verbatim\s*:"#
        )
        let verbatimLiteralPattern = try NSRegularExpression(
            pattern: #"\bText\s*\(\s*verbatim\s*:\s*\""#
        )

        var failures: [String] = []
        for sourceURL in sourceURLs.sorted(by: { $0.path < $1.path }) {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
            let lines = source.components(separatedBy: .newlines)

            for match in stringLiteralPattern.matches(in: source, range: sourceRange) {
                let rawLiteral = (source as NSString).substring(with: match.range(at: 1))
                _ = catalogContains(
                    rawLiteral: rawLiteral,
                    catalogKeys: catalogKeys,
                    referencedCatalogKeys: &referencedCatalogKeys
                )
            }

            for match in verbatimPattern.matches(in: source, range: sourceRange) {
                let lineNumber = lineNumber(forUTF16Location: match.range.location, in: source)
                let line = lines[lineNumber - 1]
                let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
                let location = "\(sourceURL.path):\(lineNumber)"

                if verbatimLiteralPattern.firstMatch(in: line, range: lineRange) != nil {
                    failures.append(
                        "\(location) uses a string literal with Text(verbatim:); use a localized Text initializer."
                    )
                    continue
                }

                let marker = "// localization: allow-verbatim"
                guard let markerRange = line.range(of: marker) else {
                    failures.append(
                        "\(location) uses Text(verbatim:) without \(marker) <reason>."
                    )
                    continue
                }
                let reason = line[markerRange.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if reason.isEmpty {
                    failures.append("\(location) has a localization bypass without a reason.")
                }
            }

            var checkedLocations: Set<Int> = []
            for pattern in localizedLiteralPatterns {
                for match in pattern.matches(in: source, range: sourceRange) {
                    appendMissingCatalogFailure(
                        captureRange: match.range(at: 1),
                        source: source,
                        sourceURL: sourceURL,
                        catalogKeys: catalogKeys,
                        checkedLocations: &checkedLocations,
                        referencedCatalogKeys: &referencedCatalogKeys,
                        failures: &failures
                    )
                }
            }

            for propertyMatch in localizedPropertyPattern.matches(in: source, range: sourceRange) {
                let bodyRange = propertyMatch.range(at: 1)
                let body = (source as NSString).substring(with: bodyRange)
                let bodySearchRange = NSRange(location: 0, length: (body as NSString).length)
                for literalMatch in stringLiteralPattern.matches(in: body, range: bodySearchRange) {
                    let captureRange = literalMatch.range(at: 1)
                    let sourceCaptureRange = NSRange(
                        location: bodyRange.location + captureRange.location,
                        length: captureRange.length
                    )
                    appendMissingCatalogFailure(
                        captureRange: sourceCaptureRange,
                        source: source,
                        sourceURL: sourceURL,
                        catalogKeys: catalogKeys,
                        checkedLocations: &checkedLocations,
                        referencedCatalogKeys: &referencedCatalogKeys,
                        failures: &failures
                    )
                }
            }
        }
        return failures
    }

    private static func appendMissingCatalogFailure(
        captureRange: NSRange,
        source: String,
        sourceURL: URL,
        catalogKeys: Set<String>,
        checkedLocations: inout Set<Int>,
        referencedCatalogKeys: inout Set<String>,
        failures: inout [String]
    ) {
        guard captureRange.location != NSNotFound,
              checkedLocations.insert(captureRange.location).inserted else {
            return
        }
        let rawLiteral = (source as NSString).substring(with: captureRange)
        guard !catalogContains(
            rawLiteral: rawLiteral,
            catalogKeys: catalogKeys,
            referencedCatalogKeys: &referencedCatalogKeys
        ) else {
            return
        }
        let lineNumber = lineNumber(forUTF16Location: captureRange.location, in: source)
        failures.append(
            "\(sourceURL.path):\(lineNumber) uses \(rawLiteral.debugDescription) as localized UI text, "
                + "but the key is missing from the string catalog."
        )
    }

    private static func catalogContains(
        rawLiteral: String,
        catalogKeys: Set<String>,
        referencedCatalogKeys: inout Set<String>
    ) -> Bool {
        guard rawLiteral.contains(#"\("#) else {
            let quotedLiteral = "\"\(rawLiteral)\""
            let decoded = try? JSONDecoder().decode(String.self, from: Data(quotedLiteral.utf8))
            let key = decoded ?? rawLiteral
            guard catalogKeys.contains(key) else { return false }
            referencedCatalogKeys.insert(key)
            return true
        }

        let interpolationPattern = try! NSRegularExpression(pattern: #"\\\([^\)]*\)"#)
        let literalRange = NSRange(rawLiteral.startIndex..<rawLiteral.endIndex, in: rawLiteral)
        var pattern = "^"
        var offset = 0
        for match in interpolationPattern.matches(in: rawLiteral, range: literalRange) {
            let prefixRange = NSRange(location: offset, length: match.range.location - offset)
            let prefix = (rawLiteral as NSString).substring(with: prefixRange)
            pattern += NSRegularExpression.escapedPattern(for: prefix) + ".*"
            offset = match.range.location + match.range.length
        }
        let suffixRange = NSRange(
            location: offset,
            length: (rawLiteral as NSString).length - offset
        )
        pattern += NSRegularExpression.escapedPattern(
            for: (rawLiteral as NSString).substring(with: suffixRange)
        ) + "$"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let matchingKeys = catalogKeys.filter { key in
            let range = NSRange(key.startIndex..<key.endIndex, in: key)
            return expression.firstMatch(in: key, range: range) != nil
        }
        referencedCatalogKeys.formUnion(matchingKeys)
        return !matchingKeys.isEmpty
    }

    private static func lineNumber(forUTF16Location location: Int, in source: String) -> Int {
        let utf16 = source.utf16
        let end = utf16.index(utf16.startIndex, offsetBy: min(location, utf16.count))
        return utf16[..<end].reduce(into: 1) { line, character in
            if character == 10 { line += 1 }
        }
    }

    private static func localeIdentifiers(in sourceURL: URL) throws -> Set<String> {
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"case\s+\w+\s*=\s*\"([^\"]+)\""#
        )
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(expression.matches(in: source, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[capture])
        })
    }
}
