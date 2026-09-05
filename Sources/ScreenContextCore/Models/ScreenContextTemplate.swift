import Foundation

public struct ScreenContextTemplate: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var body: String

    public init(id: String = UUID().uuidString, name: String, body: String) {
        self.id = id
        self.name = name
        self.body = body
    }

    public func displayName(fallback: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? fallback : trimmedName
    }
}

public struct ScreenContextTemplateInsertion: Equatable, Sendable {
    public let body: String
    public let cursorOffset: Int

    public init(body: String, cursorOffset: Int) {
        self.body = body
        self.cursorOffset = cursorOffset
    }
}

public enum ScreenContextTemplateEditing {
    public static func inserting(
        _ placeholder: String,
        into body: String,
        replacing range: Range<String.Index>
    ) -> ScreenContextTemplateInsertion {
        let insertionOffset = body.distance(from: body.startIndex, to: range.lowerBound)
        var updatedBody = body
        updatedBody.replaceSubrange(range, with: placeholder)
        return ScreenContextTemplateInsertion(
            body: updatedBody,
            cursorOffset: insertionOffset + placeholder.count
        )
    }
}

public enum ScreenContextTemplateLibrary {
    private final class BundleToken {}

    public static let markdownID = "builtin.markdown"
    private static let bundledTemplates = loadBundledTemplates()

    public static func decode(_ data: Data) -> [ScreenContextTemplate] {
        decode(data, bundledTemplates: bundledTemplates)
    }

    public static func encode(_ templates: [ScreenContextTemplate]) throws -> Data {
        try encode(templates, bundledTemplates: bundledTemplates)
    }

    // Store user choices separately so future bundled additions and unedited updates appear.
    private struct StoredLibrary: Codable {
        var templates: [ScreenContextTemplate]
        var deletedBundledIDs: Set<String>
        var orderedIDs: [String]
    }

    static func decode(
        _ data: Data,
        bundledTemplates: [ScreenContextTemplate]
    ) -> [ScreenContextTemplate] {
        guard let stored = try? JSONDecoder().decode(StoredLibrary.self, from: data) else {
            return bundledTemplates
        }
        var available: [String: ScreenContextTemplate] = [:]
        for template in bundledTemplates where !stored.deletedBundledIDs.contains(template.id) {
            available[template.id] = template
        }
        for template in stored.templates {
            available[template.id] = template
        }
        // Removing each entry also prevents duplicate identities in SwiftUI lists and pickers.
        return (stored.orderedIDs + bundledTemplates.map(\.id) + stored.templates.map(\.id))
            .compactMap { available.removeValue(forKey: $0) }
    }

    static func encode(
        _ templates: [ScreenContextTemplate],
        bundledTemplates: [ScreenContextTemplate]
    ) throws -> Data {
        let installedIDs = Set(templates.map(\.id))
        let stored = StoredLibrary(
            templates: templates.filter { template in
                !bundledTemplates.contains(template)
            },
            deletedBundledIDs: Set(bundledTemplates.map(\.id)).subtracting(installedIDs),
            orderedIDs: templates.map(\.id)
        )
        return try JSONEncoder().encode(stored)
    }

    public static func restoringMissingBundledTemplates(
        in templates: [ScreenContextTemplate]
    ) -> [ScreenContextTemplate] {
        let installedIDs = Set(templates.map(\.id))
        return templates + bundledTemplates.filter { !installedIDs.contains($0.id) }
    }

    private static func loadBundledTemplates() -> [ScreenContextTemplate] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: BundleToken.self)
        #endif
        var urls = bundle.urls(
            forResourcesWithExtension: "md",
            subdirectory: "Templates"
        ) ?? []
        if urls.isEmpty {
            urls = bundle.urls(
                forResourcesWithExtension: "md",
                subdirectory: nil
            ) ?? []
        }

        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                    return nil
                }
                return parseTemplate(source)
            }
    }

    private static func parseTemplate(_ source: String) -> ScreenContextTemplate? {
        let normalizedSource = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalizedSource.hasPrefix("---\n"),
              let closingDelimiter = normalizedSource.range(
                  of: "\n---\n",
                  range: normalizedSource.index(
                      normalizedSource.startIndex,
                      offsetBy: 4
                  )..<normalizedSource.endIndex
              ) else {
            return nil
        }

        let metadataStart = normalizedSource.index(
            normalizedSource.startIndex,
            offsetBy: 4
        )
        let metadataSource = normalizedSource[metadataStart..<closingDelimiter.lowerBound]
        var metadata: [String: String] = [:]
        for line in metadataSource.split(separator: "\n") {
            let fields = line.split(separator: ":", maxSplits: 1)
            guard fields.count == 2 else { continue }
            metadata[fields[0].trimmingCharacters(in: .whitespaces)] =
                fields[1].trimmingCharacters(in: .whitespaces)
        }

        guard let id = metadata["id"], !id.isEmpty,
              let name = metadata["name"], !name.isEmpty else {
            return nil
        }

        var body = String(normalizedSource[closingDelimiter.upperBound...])
        if body.hasSuffix("\n") {
            body.removeLast()
        }

        return ScreenContextTemplate(
            id: id,
            name: name,
            body: body
        )
    }
}
