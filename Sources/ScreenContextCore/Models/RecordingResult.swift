import Foundation

public struct RecordingResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let recordedAt: Date

    public init(id: UUID = UUID(), fileURL: URL, recordedAt: Date = Date()) {
        self.id = id
        self.fileURL = fileURL
        self.recordedAt = recordedAt
    }

    public var context: String {
        fileURL.path
    }
}
