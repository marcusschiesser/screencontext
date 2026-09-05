import AVFAudio
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import Speech

private final class OneShotAudioInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        defer { buffer = nil }
        return buffer
    }
}

@available(macOS 26.0, *)
actor SpeechAnalyzerOnDeviceTranscriber: SpeechAnalyzerTranscribing {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<[TranscriptSegment], Error>?
    private var analyzerFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    func start(localeIdentifier: String?) async throws {
        await cancel()
        let requestedLocale = Locale(
            identifier: localeIdentifier ?? Locale.autoupdatingCurrent.identifier
        )
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(
                equivalentTo: requestedLocale
              ) else {
            throw OnDeviceSpeechTranscriberError.recognizerUnavailable
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedProgressiveTranscription
        )
        guard await SpeechAssetPreparation.status(for: transcriber) == .installed,
              let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber]
              ) else {
            throw OnDeviceSpeechTranscriberError.onDeviceRecognitionUnavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        let inputs = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputs.stream)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.inputContinuation = inputs.continuation
        self.analyzerFormat = analyzerFormat
        resultsTask = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = result.range.start.seconds
                let duration = result.range.duration.seconds
                segments.append(TranscriptSegment(
                    startTime: start.isFinite ? max(0, start) : 0,
                    duration: duration.isFinite ? max(0, duration) : 0,
                    text: text
                ))
            }
            return segments
        }
    }

    func append(_ sample: SpeechAudioSample) {
        guard inputContinuation != nil,
              let pcmBuffer = Self.pcmBuffer(from: sample.buffer),
              let analyzerInput = try? analyzerInput(from: pcmBuffer) else {
            return
        }
        inputContinuation?.yield(analyzerInput)
    }

    func finishTranscript() async -> Transcript {
        inputContinuation?.finish()
        inputContinuation = nil
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            let segments = try await resultsTask?.value ?? []
            reset()
            return Transcript(segments: segments)
        } catch {
            await analyzer?.cancelAndFinishNow()
            reset()
            return .empty
        }
    }

    func cancel() async {
        inputContinuation?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel()
        reset()
    }

    private func analyzerInput(from inputBuffer: AVAudioPCMBuffer) throws -> AnalyzerInput? {
        guard let analyzerFormat else { return nil }
        let outputBuffer: AVAudioPCMBuffer
        if Self.formatsMatch(inputBuffer.format, analyzerFormat) {
            outputBuffer = inputBuffer
        } else {
            if audioConverter == nil
                || !Self.formatsMatch(converterInputFormat, inputBuffer.format) {
                audioConverter = AVAudioConverter(
                    from: inputBuffer.format,
                    to: analyzerFormat
                )
                converterInputFormat = inputBuffer.format
            }
            guard let audioConverter else { return nil }
            let ratio = analyzerFormat.sampleRate / inputBuffer.format.sampleRate
            let capacity = AVAudioFrameCount(
                ceil(Double(inputBuffer.frameLength) * ratio) + 32
            )
            guard let converted = AVAudioPCMBuffer(
                pcmFormat: analyzerFormat,
                frameCapacity: capacity
            ) else { return nil }
            let inputProvider = OneShotAudioInput(inputBuffer)
            var conversionError: NSError?
            let status = audioConverter.convert(
                to: converted,
                error: &conversionError
            ) { _, inputStatus in
                guard let input = inputProvider.take() else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            if status == .error {
                throw conversionError ?? OnDeviceSpeechTranscriberError.recognizerUnavailable
            }
            guard converted.frameLength > 0 else { return nil }
            outputBuffer = converted
        }

        return AnalyzerInput(buffer: outputBuffer)
    }

    private static func pcmBuffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                description
              ),
              let format = AVAudioFormat(streamDescription: streamDescription) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
              ) else {
            return nil
        }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }

    private static func formatsMatch(
        _ lhs: AVAudioFormat?,
        _ rhs: AVAudioFormat?
    ) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private func reset() {
        transcriber = nil
        analyzer = nil
        inputContinuation = nil
        resultsTask = nil
        analyzerFormat = nil
        audioConverter = nil
        converterInputFormat = nil
    }
}
