import Foundation

public protocol TranscriptTransforming: Sendable {
    func transform(_ transcript: Transcript) -> String
}

public struct SRTTranscriptTransformer: TranscriptTransforming {
    public init() {}

    public func transform(_ transcript: Transcript) -> String {
        let normalized = transcript.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime { return lhs.duration < rhs.duration }
                return lhs.startTime < rhs.startTime
            }
        guard !normalized.isEmpty else { return "" }

        var cues: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []
        for segment in normalized {
            if shouldStartNewCue(with: segment, current: current) {
                cues.append(current)
                current = []
            }
            current.append(segment)
            if current.count >= 12 || endsSentence(segment.text) {
                cues.append(current)
                current = []
            }
        }
        if !current.isEmpty { cues.append(current) }

        return cues.enumerated().map { index, cue in
            let start = max(0, cue.first?.startTime ?? 0)
            let spokenEnd = cue.map { $0.startTime + max(0, $0.duration) }.max() ?? start
            let nextStart = cues.indices.contains(index + 1)
                ? max(0, cues[index + 1].first?.startTime ?? spokenEnd)
                : .infinity
            let end = min(max(spokenEnd, start + 0.2), nextStart)
            return "\(index + 1)\n\(timestamp(start)) --> \(timestamp(max(start + 0.001, end)))\n\(joinedText(cue.map(\.text)))"
        }.joined(separator: "\n\n")
    }

    private func shouldStartNewCue(
        with segment: TranscriptSegment,
        current: [TranscriptSegment]
    ) -> Bool {
        guard let first = current.first else { return false }
        return current.count >= 12 || segment.startTime - first.startTime >= 5
    }

    private func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return ".!?。！？".contains(last)
    }

    private func joinedText(_ parts: [String]) -> String {
        parts.reduce(into: "") { result, rawPart in
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { return }
            guard !result.isEmpty else {
                result = part
                return
            }
            if let first = part.first, ",.!?;:)]}、。！？；：".contains(first) {
                result += part
            } else {
                result += " " + part
            }
        }
    }

    private func timestamp(_ time: TimeInterval) -> String {
        let totalMilliseconds = Int64((max(0, time) * 1_000).rounded())
        let milliseconds = totalMilliseconds % 1_000
        let totalSeconds = totalMilliseconds / 1_000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(
            format: "%02lld:%02lld:%02lld,%03lld",
            hours,
            minutes,
            seconds,
            milliseconds
        )
    }
}

public struct TranscriptMarkdownFormatter: Sendable {
    public init() {}

    public func format(
        recordingURL: URL?,
        keyframes: [RecordingKeyframe],
        srt: String
    ) -> String {
        return [
            recordingSection(recordingURL: recordingURL),
            keyframesSection(keyframes: keyframes),
            transcriptSection(srt: srt),
        ].joined(separator: "\n\n")
    }

    public func format(
        template: String,
        recordingURL: URL?,
        keyframes: [RecordingKeyframe],
        srt: String
    ) -> String {
        ScreenContextTemplateFormatter().format(
            template: template,
            recordingURL: recordingURL,
            keyframes: keyframes,
            srt: srt
        )
    }

    public func format(
        keyframes: [RecordingKeyframe],
        srt: String
    ) -> String {
        [
            keyframesSection(keyframes: keyframes),
            transcriptSection(srt: srt),
        ].joined(separator: "\n\n")
    }

    public func recordingSection(recordingURL: URL?) -> String {
        section(heading: "Recording", body: recordingURL.map(\.path) ?? "")
    }

    public func keyframesSection(keyframes: [RecordingKeyframe]) -> String {
        let keyframeLines = keyframes
            .sorted { $0.timestamp < $1.timestamp }
            .map { "- \(compactTimestamp($0.timestamp)) — \($0.fileURL.path)" }
        return section(heading: "Keyframes", body: keyframeLines.joined(separator: "\n"))
    }

    public func transcriptSection(srt: String) -> String {
        let normalizedSRT = srt
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let transcriptLines = normalizedSRT
            .components(separatedBy: "\n\n")
            .compactMap(markdownLine)

        guard !transcriptLines.isEmpty else { return "## Transcript" }
        return "## Transcript\n\n" + transcriptLines.joined(separator: "\n")
    }

    private func section(heading: String, body: String) -> String {
        guard !body.isEmpty else { return "## \(heading)" }
        return "## \(heading)\n\n\(body)"
    }

    private func markdownLine(from cue: String) -> String? {
        let lines = cue.components(separatedBy: "\n")
        guard lines.count >= 3,
              let separatorRange = lines[1].range(of: " --> "),
              let timestamp = compactTimestamp(String(lines[1][..<separatorRange.lowerBound])) else {
            return nil
        }

        let text = lines.dropFirst(2)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return "[\(timestamp)] \(text)"
    }

    private func compactTimestamp(_ srtTimestamp: String) -> String? {
        let clock = srtTimestamp.split(separator: ",", maxSplits: 1).first ?? ""
        let components = clock.split(separator: ":")
        guard components.count == 3 else { return nil }

        if components[0] == "00" {
            return "\(components[1]):\(components[2])"
        }
        return "\(components[0]):\(components[1]):\(components[2])"
    }

    private func compactTimestamp(_ timestamp: TimeInterval) -> String {
        let totalSeconds = Int(max(0, timestamp).rounded(.down))
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        if hours == 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
