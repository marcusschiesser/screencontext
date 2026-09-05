import Foundation

public struct ScreenContextTemplateFormatter: Sendable {
    public static let recordingPlaceholder = "{recording}"
    public static let keyframesPlaceholder = "{keyframes}"
    public static let transcriptPlaceholder = "{transcript}"

    public static let placeholders = [
        recordingPlaceholder,
        keyframesPlaceholder,
        transcriptPlaceholder,
    ]

    public init() {}

    public func format(
        template: String,
        recordingURL: URL?,
        keyframes: [RecordingKeyframe],
        srt: String
    ) -> String {
        let formatter = TranscriptMarkdownFormatter()
        let replacements = [
            Self.recordingPlaceholder: formatter.recordingSection(recordingURL: recordingURL),
            Self.keyframesPlaceholder: formatter.keyframesSection(keyframes: keyframes),
            Self.transcriptPlaceholder: formatter.transcriptSection(srt: srt),
        ]
        var remaining = template[...]
        var output = ""
        while let match = Self.placeholders.compactMap({ placeholder in
            remaining.range(of: placeholder).map { (range: $0, placeholder: placeholder) }
        }).min(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            output += remaining[..<match.range.lowerBound]
            output += replacements[match.placeholder] ?? match.placeholder
            remaining = remaining[match.range.upperBound...]
        }
        output += remaining
        return output
    }
}
