import Foundation

public enum RecordingContextDestination: String, CaseIterable, Sendable {
    case codex
    case claude

    public var scheme: String { rawValue }
}

public struct RecordingContextPromptLengthError: Error, Equatable, Sendable {
    public let destination: RecordingContextDestination
    public let maximumCharacterCount: Int
    public let actualCharacterCount: Int

    public init(
        destination: RecordingContextDestination,
        maximumCharacterCount: Int,
        actualCharacterCount: Int
    ) {
        self.destination = destination
        self.maximumCharacterCount = maximumCharacterCount
        self.actualCharacterCount = actualCharacterCount
    }
}

public struct RecordingContextDeepLinkBuilder: Sendable {
    public static let claudeMaximumPromptLength = 14_000

    public init() {}

    public static func url(
        for destination: RecordingContextDestination,
        prompt: String
    ) throws -> URL {
        try RecordingContextDeepLinkBuilder().url(for: destination, prompt: prompt)
    }

    public func url(
        for destination: RecordingContextDestination,
        prompt: String
    ) throws -> URL {
        if destination == .claude,
           prompt.count > Self.claudeMaximumPromptLength {
            throw RecordingContextPromptLengthError(
                destination: destination,
                maximumCharacterCount: Self.claudeMaximumPromptLength,
                actualCharacterCount: prompt.count
            )
        }

        var components = URLComponents()
        components.scheme = destination.scheme

        switch destination {
        case .codex:
            components.host = "threads"
            components.path = "/new"
            components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]
        case .claude:
            components.host = "claude.ai"
            components.path = "/new"
            components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        }

        // The scheme, host, path, and query names above are fixed valid URL components.
        return components.url!
    }
}
