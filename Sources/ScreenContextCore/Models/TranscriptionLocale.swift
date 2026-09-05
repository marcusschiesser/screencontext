import Foundation

public struct TranscriptionLocale: Codable, Equatable, Hashable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public init(_ locale: Locale) {
        identifier = locale.identifier
    }

    public var locale: Locale {
        Locale(identifier: identifier)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        identifier = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}
