import Foundation

public struct RecordingHistoryEntry: Equatable, Sendable {
    public let id: UUID
    public let fileURL: URL
    public let keyframes: [RecordingKeyframe]
    public let recordedAt: Date
    public let requestedTranscription: Bool
    public let transcriptionLocale: TranscriptionLocale
    public let transcriptSRT: String
    public let transcriptIsAvailable: Bool

    public init(
        id: UUID,
        fileURL: URL,
        keyframes: [RecordingKeyframe],
        recordedAt: Date,
        requestedTranscription: Bool,
        transcriptionLocale: TranscriptionLocale,
        transcriptSRT: String,
        transcriptIsAvailable: Bool
    ) {
        self.id = id
        self.fileURL = fileURL
        self.keyframes = keyframes
        self.recordedAt = recordedAt
        self.requestedTranscription = requestedTranscription
        self.transcriptionLocale = transcriptionLocale
        self.transcriptSRT = transcriptSRT
        self.transcriptIsAvailable = transcriptIsAvailable
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
