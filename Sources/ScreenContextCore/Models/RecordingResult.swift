import Foundation
import Observation

@Observable
public final class RecordingResult: Identifiable {
    public let id: UUID
    public let fileURL: URL
    public let keyframes: [RecordingKeyframe]
    public let recordedAt: Date
    public let requestedTranscription: Bool
    public let transcriptionLocale: TranscriptionLocale
    public internal(set) var transcriptSRT: String
    public internal(set) var transcriptIsAvailable: Bool
    public internal(set) var transcriptionModelAvailability: TranscriptionModelAvailability
    public internal(set) var isRetranscribing = false

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        keyframes: [RecordingKeyframe] = [],
        recordedAt: Date = Date(),
        requestedTranscription: Bool,
        transcriptionLocale: TranscriptionLocale,
        transcriptSRT: String = "",
        transcriptIsAvailable: Bool = false,
        transcriptionModelAvailability: TranscriptionModelAvailability = .checking
    ) {
        self.id = id
        self.fileURL = fileURL
        self.keyframes = keyframes
        self.recordedAt = recordedAt
        self.requestedTranscription = requestedTranscription
        self.transcriptionLocale = transcriptionLocale
        self.transcriptSRT = transcriptSRT
        self.transcriptIsAvailable = transcriptIsAvailable
        self.transcriptionModelAvailability = transcriptionModelAvailability
    }

    public var locale: Locale {
        transcriptionLocale.locale
    }
}
