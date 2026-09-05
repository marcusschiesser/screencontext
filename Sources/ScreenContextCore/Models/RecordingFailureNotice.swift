import Foundation

public struct RecordingFailureNotice: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case partialRecordingPreserved
        case recordingNotSaved
    }

    public let id: UUID
    public let kind: Kind
    public let recoveryURL: URL?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        recoveryURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.recoveryURL = recoveryURL
    }
}
