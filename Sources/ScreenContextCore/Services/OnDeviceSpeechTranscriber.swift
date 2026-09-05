@preconcurrency import CoreMedia
import Foundation

struct SpeechAudioSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

enum OnDeviceSpeechTranscriberError: Error, LocalizedError {
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            "Speech recognition is unavailable for the selected language."
        case .onDeviceRecognitionUnavailable:
            "On-device speech recognition is unavailable for the selected language."
        }
    }
}

protocol SpeechAnalyzerTranscribing: Actor {
    func start(localeIdentifier: String?) async throws
    func append(_ sample: SpeechAudioSample) async
    func finishTranscript() async -> Transcript
    func cancel() async
}

actor OnDeviceSpeechTranscriber {
    private var backend: (any SpeechAnalyzerTranscribing)?

    func start(localeIdentifier: String?) async throws {
        await cancel()
        guard #available(macOS 26.0, *) else {
            throw OnDeviceSpeechTranscriberError.recognizerUnavailable
        }
        let backend = SpeechAnalyzerOnDeviceTranscriber()
        try await backend.start(localeIdentifier: localeIdentifier)
        self.backend = backend
    }

    func append(_ sample: SpeechAudioSample) async {
        await backend?.append(sample)
    }

    func finishTranscript() async -> Transcript {
        guard let backend else { return .empty }
        let transcript = await backend.finishTranscript()
        self.backend = nil
        return transcript
    }

    func cancel() async {
        await backend?.cancel()
        backend = nil
    }
}
