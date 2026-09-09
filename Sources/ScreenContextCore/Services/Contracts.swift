@preconcurrency import CoreMedia
import Foundation

public protocol CaptureSourceCatalog: Sendable {
    func sources() async throws -> [CaptureSource]
    func requestAccess() async -> Bool
}

public protocol CaptureAuthorization: Sendable {
    func requestCameraAccess() async -> Bool
    func requestMicrophoneAccess() async -> Bool
    func requestSystemAudioAccess(for source: CaptureSource) async -> Bool
}

public extension CaptureSourceCatalog {
    func requestAccess() async -> Bool { true }

    func restoredSource(
        from sources: [CaptureSource],
        preferredID: CaptureSourceID?
    ) -> CaptureSource? {
        if let preferredID,
           preferredID.kind == .display,
           let restored = sources.first(where: { $0.id == preferredID }) {
            return restored
        }
        let displays = sources.compactMap { source -> CaptureSource? in
            guard case .display = source else { return nil }
            return source
        }
        return displays.first {
            guard case let .display(screen) = $0 else { return false }
            return screen.isPrimary
        } ?? displays.first
    }
}

public protocol PreferencesStore: Sendable {
    func load() async -> PreferencesSnapshot
    func save(_ snapshot: PreferencesSnapshot) async
}

public enum RecordingPipelineEvent: Equatable, Sendable {
    case optionalInputLost(name: String)
    case fatal(message: String)
}

public protocol RecordingPipeline: Sendable {
    func start(configuration: RecordingConfiguration) async throws -> AsyncStream<RecordingPipelineEvent>
    func stop() async throws -> RecordingArtifacts
    func cancel() async
}

public protocol MediaSampleSink: Sendable {
    func appendVideo(_ sampleBuffer: CMSampleBuffer, track: UInt8) async
    func appendAudio(_ sampleBuffer: CMSampleBuffer, track: UInt8) async
}
