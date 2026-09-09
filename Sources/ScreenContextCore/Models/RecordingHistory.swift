import Foundation

public struct RecordingHistoryEntry: Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let recordedAt: Date

    public init(
        id: UUID,
        fileURL: URL,
        recordedAt: Date
    ) {
        self.id = id
        self.fileURL = fileURL
        self.recordedAt = recordedAt
    }
}

public struct RecordingHistorySnapshot: Equatable, Sendable {
    public let recordings: [RecordingHistoryEntry]
    public let selectedRecordingID: UUID?

    public init(
        recordings: [RecordingHistoryEntry] = [],
        selectedRecordingID: UUID? = nil
    ) {
        self.recordings = recordings
        self.selectedRecordingID = selectedRecordingID
    }
}
