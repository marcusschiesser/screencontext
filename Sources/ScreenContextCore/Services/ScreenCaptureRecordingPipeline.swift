@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit

public actor ScreenCaptureRecordingPipeline: RecordingPipeline {
    private let logger = Logger(
        subsystem: "de.marcusschiesser.contextcast",
        category: "capture"
    )
    private let recorder: LocalMediaRecorder
    private let transcriber = OnDeviceSpeechTranscriber()
    private let bundleIdentifier: String
    private var captureStream: SCStream?
    private var outputBridge: ScreenCaptureOutputBridge?
    private var eventContinuation: AsyncStream<RecordingPipelineEvent>.Continuation?
    private var sampleForwarder: MediaSampleForwarder?
    private var webcamCapture: WebcamCaptureSource?
    private var microphoneCapture: MicrophoneCaptureSource?

    public init(
        recorder: LocalMediaRecorder = LocalMediaRecorder(),
        bundleIdentifier: String = "de.marcusschiesser.contextcast"
    ) {
        self.recorder = recorder
        self.bundleIdentifier = bundleIdentifier
    }

    public func start(configuration: RecordingConfiguration) async throws -> AsyncStream<RecordingPipelineEvent> {
        await cancel()
        try Task.checkCancellation()

        let events = AsyncStream<RecordingPipelineEvent> { continuation in
            self.eventContinuation = continuation
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        try Task.checkCancellation()
        let resolvedTarget = try ScreenCaptureKitContentFilterFactory.resolve(
            for: configuration.source,
            in: content,
            excludingBundleIdentifier: bundleIdentifier
        )
        let filter = resolvedTarget.filter
        let profile = OutputProfile.make(
            pixelWidth: resolvedTarget.pixelWidth,
            pixelHeight: resolvedTarget.pixelHeight
        )
        let sourceID = configuration.source.id
        logger.info(
            "Preparing \(sourceID.kind.rawValue, privacy: .public) \(sourceID.rawValue, privacy: .public) at \(profile.width, privacy: .public)x\(profile.height, privacy: .public)"
        )
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = profile.width
        streamConfiguration.height = profile.height
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfiguration.queueDepth = 5
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = true
        streamConfiguration.capturesAudio = configuration.capturesSystemAudio
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2

        let sampleForwarder = MediaSampleForwarder(
            sink: recorder,
            systemAudioTrack: MediaTrackLayout.systemAudioTrack(
                capturesMicrophone: configuration.capturesMicrophone
            ),
            microphoneTrack: MediaTrackLayout.microphoneTrack,
            microphoneTap: { [transcriber] sample in
                await transcriber.append(sample)
            }
        )
        self.sampleForwarder = sampleForwarder

        do {
            try await recorder.start(
                profile: profile,
                capturesAudio: configuration.capturesSystemAudio || configuration.capturesMicrophone,
                webcamEnabled: configuration.capturesWebcam,
                webcamLayout: configuration.webcamLayout
            )
            try Task.checkCancellation()

            if configuration.capturesMicrophone {
                do {
                    try await transcriber.start(
                        localeIdentifier: configuration.transcriptionLocale.identifier
                    )
                    eventContinuation?.yield(.transcriptionAvailable)
                } catch {
                    logger.warning(
                        "Local transcription is unavailable: \(error.localizedDescription, privacy: .public)"
                    )
                    eventContinuation?.yield(
                        .transcriptionUnavailable(message: error.localizedDescription)
                    )
                }
                let microphoneCapture = MicrophoneCaptureSource { sampleBuffer in
                    sampleForwarder.yieldMicrophone(sampleBuffer)
                }
                try await microphoneCapture.start(
                    microphoneID: configuration.microphoneDeviceID
                )
                try Task.checkCancellation()
                self.microphoneCapture = microphoneCapture
            }

            if configuration.capturesWebcam {
                let webcamCapture = WebcamCaptureSource { sampleBuffer in
                    sampleForwarder.yieldWebcam(sampleBuffer)
                }
                try await webcamCapture.start(
                    cameraID: configuration.webcamDeviceID,
                    frameRate: profile.frameRate
                )
                try Task.checkCancellation()
                self.webcamCapture = webcamCapture
            }

            let outputBridge = ScreenCaptureOutputBridge(
                onSample: { sampleBuffer, outputType in
                    sampleForwarder.yield(sampleBuffer, outputType: outputType)
                },
                onFatalError: { [weak self] error in
                    Task {
                        await self?.eventContinuation?.yield(.fatal(message: error.localizedDescription))
                    }
                }
            )
            let captureStream = SCStream(
                filter: filter,
                configuration: streamConfiguration,
                delegate: outputBridge
            )
            try captureStream.addStreamOutput(
                outputBridge,
                type: .screen,
                sampleHandlerQueue: outputBridge.videoQueue
            )
            if configuration.capturesSystemAudio {
                try captureStream.addStreamOutput(
                    outputBridge,
                    type: .audio,
                    sampleHandlerQueue: outputBridge.audioQueue
                )
            }
            self.outputBridge = outputBridge
            self.captureStream = captureStream
            try await captureStream.startCapture()
            try Task.checkCancellation()
            logger.info("ScreenCaptureKit capture started")
            return events
        } catch {
            await cancel()
            throw error
        }
    }

    public func captureKeyframe() async {
        await recorder.captureKeyframe()
    }

    public func stop() async throws -> RecordingArtifacts {
        do {
            try await stopCaptureSources()
        } catch {
            logger.warning("Capture source did not stop cleanly: \(error.localizedDescription, privacy: .public)")
        }
        let transcript = await transcriber.finishTranscript()
        let artifacts = try await recorder.finish()
        eventContinuation?.yield(.transcript(transcript))
        logger.info("Recording pipeline stopped")
        eventContinuation?.finish()
        eventContinuation = nil
        return artifacts
    }

    public func cancel() async {
        try? await stopCaptureSources()
        await transcriber.cancel()
        await recorder.cancel()
        logger.info("Recording pipeline cancelled")
        eventContinuation?.finish()
        eventContinuation = nil
    }

    private func stopCaptureSources() async throws {
        outputBridge?.invalidate()
        var stopError: Error?
        if let captureStream {
            do {
                try await captureStream.stopCapture()
            } catch {
                stopError = error
            }
        }
        captureStream = nil
        outputBridge = nil

        let webcamCapture = self.webcamCapture
        self.webcamCapture = nil
        await webcamCapture?.stop()

        let microphoneCapture = self.microphoneCapture
        self.microphoneCapture = nil
        await microphoneCapture?.stop()

        let sampleForwarder = self.sampleForwarder
        self.sampleForwarder = nil
        await sampleForwarder?.stop()

        if let stopError {
            throw stopError
        }
    }
}

struct ForwardedSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

final class MediaSampleForwarder: @unchecked Sendable {
    private let videoContinuation: AsyncStream<ForwardedSample>.Continuation
    private let webcamVideoContinuation: AsyncStream<ForwardedSample>.Continuation
    private let systemAudioContinuation: AsyncStream<ForwardedSample>.Continuation
    private let microphoneContinuation: AsyncStream<ForwardedSample>.Continuation
    private let tasks: [Task<Void, Never>]
    private let lock = NSLock()
    private var acceptsSamples = true

    init(
        sink: any MediaSampleSink,
        systemAudioTrack: UInt8 = 0,
        microphoneTrack: UInt8 = 0,
        microphoneTap: (@Sendable (SpeechAudioSample) async -> Void)? = nil
    ) {
        let videoSamples = AsyncStream.makeStream(
            of: ForwardedSample.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        let webcamVideoSamples = AsyncStream.makeStream(
            of: ForwardedSample.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        let systemAudioSamples = AsyncStream.makeStream(
            of: ForwardedSample.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        let microphoneSamples = AsyncStream.makeStream(
            of: ForwardedSample.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        videoContinuation = videoSamples.continuation
        webcamVideoContinuation = webcamVideoSamples.continuation
        systemAudioContinuation = systemAudioSamples.continuation
        microphoneContinuation = microphoneSamples.continuation
        tasks = [
            Task {
                for await sample in videoSamples.stream {
                    guard !Task.isCancelled else { break }
                    await sink.appendVideo(sample.buffer, track: 0)
                }
            },
            Task {
                for await sample in webcamVideoSamples.stream {
                    guard !Task.isCancelled else { break }
                    await sink.appendVideo(sample.buffer, track: 1)
                }
            },
            Task {
                for await sample in systemAudioSamples.stream {
                    guard !Task.isCancelled else { break }
                    await sink.appendAudio(sample.buffer, track: systemAudioTrack)
                }
            },
            Task {
                for await sample in microphoneSamples.stream {
                    guard !Task.isCancelled else { break }
                    await microphoneTap?(SpeechAudioSample(buffer: sample.buffer))
                    await sink.appendAudio(sample.buffer, track: microphoneTrack)
                }
            },
        ]
    }

    func yield(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard lock.withLock({ acceptsSamples }) else { return }
        let sample = ForwardedSample(buffer: sampleBuffer)
        switch outputType {
        case .screen:
            videoContinuation.yield(sample)
        case .audio:
            systemAudioContinuation.yield(sample)
        case .microphone:
            microphoneContinuation.yield(sample)
        @unknown default:
            break
        }
    }

    func yieldWebcam(_ sampleBuffer: CMSampleBuffer) {
        guard lock.withLock({ acceptsSamples }) else { return }
        webcamVideoContinuation.yield(ForwardedSample(buffer: sampleBuffer))
    }

    func yieldMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard lock.withLock({ acceptsSamples }) else { return }
        microphoneContinuation.yield(ForwardedSample(buffer: sampleBuffer))
    }

    func stop() async {
        let shouldStop = lock.withLock {
            guard acceptsSamples else { return false }
            acceptsSamples = false
            return true
        }
        guard shouldStop else { return }

        videoContinuation.finish()
        webcamVideoContinuation.finish()
        systemAudioContinuation.finish()
        microphoneContinuation.finish()
        for task in tasks {
            task.cancel()
        }
        for task in tasks {
            await task.value
        }
    }
}

private enum MicrophoneCaptureError: Error, LocalizedError {
    case microphoneUnavailable
    case cannotAddMicrophone
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            "The selected microphone is unavailable."
        case .cannotAddMicrophone:
            "The selected microphone could not be added to the capture session."
        case .cannotAddOutput:
            "Microphone audio output could not be configured."
        }
    }
}

private final class MicrophoneCaptureSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(
        label: "de.marcusschiesser.contextcast.capture.microphone.session",
        qos: .userInitiated
    )
    private let sampleQueue = DispatchQueue(
        label: "de.marcusschiesser.contextcast.capture.microphone.samples",
        qos: .userInteractive
    )
    private let onSample: @Sendable (CMSampleBuffer) -> Void
    private var audioOutput: AVCaptureAudioDataOutput?

    init(onSample: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onSample = onSample
    }

    func start(microphoneID: String?) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    guard let microphone = CaptureDeviceCatalog.microphone(withID: microphoneID) else {
                        throw MicrophoneCaptureError.microphoneUnavailable
                    }
                    let input = try AVCaptureDeviceInput(device: microphone)
                    let output = AVCaptureAudioDataOutput()
                    output.setSampleBufferDelegate(self, queue: sampleQueue)

                    session.beginConfiguration()
                    session.inputs.forEach(session.removeInput)
                    session.outputs.forEach(session.removeOutput)
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw MicrophoneCaptureError.cannotAddMicrophone
                    }
                    session.addInput(input)
                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw MicrophoneCaptureError.cannotAddOutput
                    }
                    session.addOutput(output)
                    session.commitConfiguration()
                    audioOutput = output
                    session.startRunning()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                audioOutput?.setSampleBufferDelegate(nil, queue: nil)
                if session.isRunning {
                    session.stopRunning()
                }
                audioOutput = nil
                continuation.resume()
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let synchronizationClock = session.synchronizationClock else {
            onSample(sampleBuffer)
            return
        }
        let hostClock = CMClockGetHostTimeClock()
        let synchronizedSample = copySampleBuffer(
            sampleBuffer,
            convertingTimestampsWith: {
                CMSyncConvertTime($0, from: synchronizationClock, to: hostClock)
            }
        ) ?? sampleBuffer
        onSample(synchronizedSample)
    }
}

private enum WebcamCaptureError: Error, LocalizedError {
    case cameraUnavailable
    case cannotAddCamera
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            "The selected webcam is unavailable."
        case .cannotAddCamera:
            "The selected webcam could not be added to the capture session."
        case .cannotAddOutput:
            "The webcam video output could not be configured."
        }
    }
}

private final class WebcamCaptureSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(
        label: "de.marcusschiesser.contextcast.capture.webcam.session",
        qos: .userInitiated
    )
    private let sampleQueue = DispatchQueue(
        label: "de.marcusschiesser.contextcast.capture.webcam.samples",
        qos: .userInteractive
    )
    private let onSample: @Sendable (CMSampleBuffer) -> Void
    private var videoOutput: AVCaptureVideoDataOutput?

    init(onSample: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onSample = onSample
    }

    func start(cameraID: String?, frameRate: Int) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    let camera = cameraID.flatMap(AVCaptureDevice.init(uniqueID:))
                        ?? AVCaptureDevice.default(for: .video)
                    guard let camera else {
                        throw WebcamCaptureError.cameraUnavailable
                    }

                    let input = try AVCaptureDeviceInput(device: camera)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    ]
                    output.setSampleBufferDelegate(self, queue: sampleQueue)

                    session.beginConfiguration()
                    if session.canSetSessionPreset(.hd1280x720) {
                        session.sessionPreset = .hd1280x720
                    }
                    session.inputs.forEach(session.removeInput)
                    session.outputs.forEach(session.removeOutput)
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        throw WebcamCaptureError.cannotAddCamera
                    }
                    session.addInput(input)
                    guard session.canAddOutput(output) else {
                        session.commitConfiguration()
                        throw WebcamCaptureError.cannotAddOutput
                    }
                    session.addOutput(output)
                    session.commitConfiguration()
                    try configureFrameRate(frameRate, for: camera)
                    videoOutput = output
                    session.startRunning()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                videoOutput?.setSampleBufferDelegate(nil, queue: nil)
                if session.isRunning {
                    session.stopRunning()
                }
                videoOutput = nil
                continuation.resume()
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let synchronizationClock = session.synchronizationClock else {
            onSample(sampleBuffer)
            return
        }
        let hostClock = CMClockGetHostTimeClock()
        let synchronizedSample = copySampleBuffer(
            sampleBuffer,
            convertingTimestampsWith: {
                CMSyncConvertTime($0, from: synchronizationClock, to: hostClock)
            }
        ) ?? sampleBuffer
        onSample(synchronizedSample)
    }

    private func configureFrameRate(_ frameRate: Int, for camera: AVCaptureDevice) throws {
        let requestedRate = Double(frameRate)
        guard camera.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= requestedRate && requestedRate <= $0.maxFrameRate
        }) else {
            return
        }
        let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        camera.activeVideoMinFrameDuration = duration
        camera.activeVideoMaxFrameDuration = duration
    }
}

func copySampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    convertingTimestampsWith convert: (CMTime) -> CMTime
) -> CMSampleBuffer? {
    var timingEntryCount = 0
    guard CMSampleBufferGetSampleTimingInfoArray(
        sampleBuffer,
        entryCount: 0,
        arrayToFill: nil,
        entriesNeededOut: &timingEntryCount
    ) == noErr, timingEntryCount > 0 else {
        return nil
    }

    var timingEntries = Array(
        repeating: CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        ),
        count: timingEntryCount
    )
    guard CMSampleBufferGetSampleTimingInfoArray(
        sampleBuffer,
        entryCount: timingEntryCount,
        arrayToFill: &timingEntries,
        entriesNeededOut: nil
    ) == noErr else {
        return nil
    }

    for index in timingEntries.indices {
        if timingEntries[index].presentationTimeStamp.isValid {
            timingEntries[index].presentationTimeStamp = convert(
                timingEntries[index].presentationTimeStamp
            )
        }
        if timingEntries[index].decodeTimeStamp.isValid {
            timingEntries[index].decodeTimeStamp = convert(
                timingEntries[index].decodeTimeStamp
            )
        }
    }

    var synchronizedSample: CMSampleBuffer?
    let status = CMSampleBufferCreateCopyWithNewTiming(
        allocator: kCFAllocatorDefault,
        sampleBuffer: sampleBuffer,
        sampleTimingEntryCount: timingEntryCount,
        sampleTimingArray: &timingEntries,
        sampleBufferOut: &synchronizedSample
    )
    guard status == noErr else { return nil }
    return synchronizedSample
}

public enum PipelineError: Error, LocalizedError, Sendable {
    case selectedSourceUnavailable

    public var errorDescription: String? {
        switch self {
        case .selectedSourceUnavailable:
            "The selected screen or window is no longer available. Choose another source and try again."
        }
    }
}

func isCompleteScreenCaptureFrame(
    _ attachments: [SCStreamFrameInfo: Any]?
) -> Bool {
    guard let rawStatus = attachments?[.status] as? Int,
          let status = SCFrameStatus(rawValue: rawStatus) else {
        return false
    }
    return status == .complete
}

private final class ScreenCaptureOutputBridge: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let videoQueue = DispatchQueue(label: "de.marcusschiesser.contextcast.capture.video", qos: .userInteractive)
    let audioQueue = DispatchQueue(label: "de.marcusschiesser.contextcast.capture.audio", qos: .userInitiated)
    private let onSample: @Sendable (CMSampleBuffer, SCStreamOutputType) -> Void
    private let onFatalError: @Sendable (Error) -> Void
    private let lock = NSLock()
    private var acceptsCallbacks = true

    init(
        onSample: @escaping @Sendable (CMSampleBuffer, SCStreamOutputType) -> Void,
        onFatalError: @escaping @Sendable (Error) -> Void
    ) {
        self.onSample = onSample
        self.onFatalError = onFatalError
    }

    func invalidate() {
        lock.withLock {
            acceptsCallbacks = false
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid, lock.withLock({ acceptsCallbacks }) else { return }
        if outputType == .screen {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]]
            guard isCompleteScreenCaptureFrame(attachments?.first) else { return }
        }
        guard let synchronizationClock = stream.synchronizationClock else {
            onSample(sampleBuffer, outputType)
            return
        }
        let hostClock = CMClockGetHostTimeClock()
        let synchronizedSample = copySampleBuffer(
            sampleBuffer,
            convertingTimestampsWith: {
                CMSyncConvertTime($0, from: synchronizationClock, to: hostClock)
            }
        ) ?? sampleBuffer
        onSample(synchronizedSample, outputType)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard lock.withLock({ acceptsCallbacks }) else { return }
        onFatalError(error)
    }
}
