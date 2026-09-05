import Foundation

public struct Transcript: Equatable, Sendable {
    public let segments: [TranscriptSegment]

    public init(segments: [TranscriptSegment]) {
        self.segments = segments
    }

    public static let empty = Transcript(segments: [])
}

public struct TranscriptSegment: Equatable, Sendable {
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let text: String

    public init(startTime: TimeInterval, duration: TimeInterval, text: String) {
        self.startTime = startTime
        self.duration = duration
        self.text = text
    }
}
