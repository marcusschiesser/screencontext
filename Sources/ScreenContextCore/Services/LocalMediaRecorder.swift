@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
@preconcurrency import CoreImage
import Foundation
import HaishinKit
import ImageIO
import OSLog
import UniformTypeIdentifiers

public actor LocalMediaRecorder: MediaSampleSink {
    private let logger = Logger(
        subsystem: "de.marcusschiesser.contextcast",
        category: "recorder"
    )
    private var mixer: MediaMixer?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var profile: OutputProfile?
    private var expectsAudio = false
    private var acceptsOutput = false
    private var pendingVideo: [CMSampleBuffer] = []
    private var pendingAudio: [CMSampleBuffer] = []
    private var lastVideoTime = CMTime.invalid
    private var lastAudioTime = CMTime.invalid
    private var writerError: (any Error)?
    private let keyframeWriter = KeyframeWriter()
    private var writerSessionStartTime = CMTime.invalid
    private var lastMixedVideoSample: CMSampleBuffer?
    private var pendingKeyframeCount = 0
    private var keyframeWriteTasks: [Task<RecordingKeyframe?, Never>] = []
    private var reservedKeyframeURLs: Set<URL> = []
    private var capturedStartKeyframe = false
    private var hasReceivedScreenFrame = false

    public nonisolated let videoTrackId: UInt8? = UInt8.max
    public nonisolated let audioTrackId: UInt8? = UInt8.max

    public init() {}

    public func start(
        profile: OutputProfile,
        capturesAudio: Bool,
        webcamEnabled: Bool,
        webcamLayout: WebcamLayout
    ) async throws {
        await cancel()

        let mixer = MediaMixer(
            captureSessionMode: .manual,
            multiTrackAudioMixingEnabled: true
        )
        await mixer.setSessionPreset(.hd1280x720)
        await mixer.setVideoMixerSettings(
            VideoMixerSettings(mode: .offscreen, mainTrack: 0)
        )
        await mixer.setAudioMixerSettings(
            AudioMixerSettings(
                sampleRate: 48_000,
                channels: 2,
                mainTrack: 0,
                tracks: [
                    0: AudioMixerTrackSettings(),
                    1: AudioMixerTrackSettings(),
                ]
            )
        )
        try await mixer.setFrameRate(Double(profile.frameRate))
        try await configureRecordingScreen(
            mixer: mixer,
            profile: profile,
            webcamEnabled: webcamEnabled,
            layout: webcamLayout
        )

        let outputURL = try Self.makeOutputURL()
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
            throw error
        }
        // Fragmented MP4 writing failed inside MovieHeaderMaker at fragment boundaries
        // for otherwise healthy long-running captures. Let AVAssetWriter finalize the
        // movie atomically when recording stops instead.
        writer.movieFragmentInterval = .invalid

        self.mixer = mixer
        self.writer = writer
        self.outputURL = outputURL
        self.profile = profile
        expectsAudio = capturesAudio
        acceptsOutput = true
        pendingVideo = []
        pendingAudio = []
        lastVideoTime = .invalid
        lastAudioTime = .invalid
        writerError = nil
        writerSessionStartTime = .invalid
        lastMixedVideoSample = nil
        pendingKeyframeCount = 0
        keyframeWriteTasks = []
        reservedKeyframeURLs = []
        capturedStartKeyframe = false
        hasReceivedScreenFrame = false
        try addVideoInput(sourceFormatHint: nil)
        if capturesAudio {
            try addAudioInput(sourceFormatHint: nil)
        }
        await mixer.addOutput(self)
        await mixer.startRunning()
        logger.info("Local recording started at \(outputURL.path, privacy: .private)")
    }

    public func appendVideo(_ sampleBuffer: CMSampleBuffer, track: UInt8) async {
        await mixer?.append(sampleBuffer, track: track)
        if track == 0 {
            hasReceivedScreenFrame = true
        }
    }

    public func appendAudio(_ sampleBuffer: CMSampleBuffer, track: UInt8) async {
        await mixer?.append(sampleBuffer, track: track)
    }

    public func captureKeyframe() {
        guard acceptsOutput else { return }
        pendingKeyframeCount += 1
    }

    public func finish() async throws -> RecordingArtifacts {
        guard let mixer, let writer, let outputURL else {
            throw LocalRecordingError.notRecording
        }
        await mixer.removeOutput(self)
        await mixer.stopRunning()
        try? await Task.sleep(for: .milliseconds(100))
        self.mixer = nil
        acceptsOutput = false

        do {
            if writer.status == .unknown {
                try beginWritingIfPossible(allowMissingAudio: true)
            }
            if let writerError {
                throw writerError
            }
            guard writer.status == .writing else {
                throw LocalRecordingError.failedToFinish(writer.error)
            }
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw LocalRecordingError.failedToFinish(writer.error)
            }

            if let lastMixedVideoSample {
                capturePendingKeyframes(from: lastMixedVideoSample)
                let stopTimestamp = recordingDuration(through: lastMixedVideoSample)
                captureKeyframe(from: lastMixedVideoSample, timestamp: stopTimestamp)
            }
            let finalizedKeyframes = await finishKeyframeWrites()
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                throw LocalRecordingError.emptyRecording
            }
            resetWriterState()
            logger.info("Local recording finalized at \(outputURL.path, privacy: .private)")
            return RecordingArtifacts(
                recordingURL: outputURL,
                keyframes: finalizedKeyframes
            )
        } catch {
            let diagnosticDescription = String(reflecting: writer.error ?? error)
            logger.error(
                "Local recording finalization failed: \(diagnosticDescription, privacy: .public)"
            )
            if hasReceivedScreenFrame,
               let recoveryURL = await preserveFailedRecording(
                   writer: writer,
                   outputURL: outputURL
               ) {
                throw RecordingRecoveryError(
                    recoveryURL: recoveryURL,
                    diagnosticDescription: diagnosticDescription
                )
            }
            await discardRecording(writer: writer, outputURL: outputURL)
            throw error
        }
    }

    public func cancel() async {
        let mixer = self.mixer
        let writer = self.writer
        let outputURL = self.outputURL
        self.mixer = nil
        acceptsOutput = false

        if let mixer {
            await mixer.stopRunning()
            await mixer.removeOutput(self)
        }
        writer?.cancelWriting()
        await cancelKeyframeWrites()
        resetWriterState()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
        }
    }

    static func makeOutputURL(
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = RecordingStorage.recordingsDirectory(fileManager: fileManager)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now
        )
        let timestamp = String(
            format: "%04d-%02d-%02d %02d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
        let baseName = "ScreenContext \(timestamp)"
        var recordingDirectory = directory.appendingPathComponent(
            baseName,
            isDirectory: true
        )
        var suffix = 2
        while fileManager.fileExists(atPath: recordingDirectory.path) {
            recordingDirectory = directory.appendingPathComponent(
                "\(baseName) \(suffix)",
                isDirectory: true
            )
            suffix += 1
        }
        try fileManager.createDirectory(
            at: recordingDirectory,
            withIntermediateDirectories: false
        )
        return recordingDirectory.appendingPathComponent("recording.mp4")
    }

    private func appendMixedVideo(_ sampleBuffer: CMSampleBuffer) {
        guard acceptsOutput, writerError == nil, hasReceivedScreenFrame else { return }
        lastMixedVideoSample = sampleBuffer
        do {
            if videoInput == nil {
                try addVideoInput(sourceFormatHint: sampleBuffer.formatDescription)
            }
            if writer?.status == .unknown {
                pendingVideo.append(sampleBuffer)
                try beginWritingIfPossible(allowMissingAudio: false)
            } else {
                try append(sampleBuffer, to: videoInput, lastTime: &lastVideoTime)
            }
        } catch {
            writerError = error
        }
        capturePendingKeyframes(from: sampleBuffer)
    }

    private func appendMixedAudio(_ sampleBuffer: CMSampleBuffer) {
        guard acceptsOutput, expectsAudio, writerError == nil else { return }
        do {
            if audioInput == nil {
                try addAudioInput(sourceFormatHint: sampleBuffer.formatDescription)
            }
            if writer?.status == .unknown {
                pendingAudio.append(sampleBuffer)
                try beginWritingIfPossible(allowMissingAudio: false)
            } else {
                try append(sampleBuffer, to: audioInput, lastTime: &lastAudioTime)
            }
        } catch {
            writerError = error
        }
    }

    private func addVideoInput(sourceFormatHint: CMFormatDescription?) throws {
        guard let writer, let profile else { throw LocalRecordingError.notRecording }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: profile.width,
            AVVideoHeightKey: profile.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: profile.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: profile.frameRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw LocalRecordingError.unsupportedVideoSettings
        }
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: settings,
            sourceFormatHint: sourceFormatHint
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw LocalRecordingError.cannotAddVideoInput }
        writer.add(input)
        videoInput = input
    }

    private func addAudioInput(sourceFormatHint: CMFormatDescription?) throws {
        guard let writer, let profile else { throw LocalRecordingError.notRecording }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: profile.audioBitRate,
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
            throw LocalRecordingError.unsupportedAudioSettings
        }
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: settings,
            sourceFormatHint: sourceFormatHint
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw LocalRecordingError.cannotAddAudioInput }
        writer.add(input)
        audioInput = input
    }

    private func beginWritingIfPossible(allowMissingAudio: Bool) throws {
        guard let writer, writer.status == .unknown, videoInput != nil else { return }
        guard !expectsAudio || audioInput != nil || allowMissingAudio else { return }
        guard let firstVideo = pendingVideo.first else { return }

        guard writer.startWriting() else {
            throw LocalRecordingError.failedToStart(writer.error)
        }
        let firstTime = pendingAudio.first.map {
            CMTimeMinimum(firstVideo.presentationTimeStamp, $0.presentationTimeStamp)
        } ?? firstVideo.presentationTimeStamp
        writerSessionStartTime = firstTime
        writer.startSession(atSourceTime: firstTime)
        if !capturedStartKeyframe {
            capturedStartKeyframe = true
            captureKeyframe(
                from: firstVideo,
                timestamp: recordingDuration(through: firstVideo)
            )
        }

        let video = pendingVideo
        let audio = pendingAudio
        pendingVideo = []
        pendingAudio = []
        for sample in video.sorted(by: { $0.presentationTimeStamp < $1.presentationTimeStamp }) {
            try append(sample, to: videoInput, lastTime: &lastVideoTime)
        }
        for sample in audio.sorted(by: { $0.presentationTimeStamp < $1.presentationTimeStamp }) {
            try append(sample, to: audioInput, lastTime: &lastAudioTime)
        }
    }

    private func append(
        _ sampleBuffer: CMSampleBuffer,
        to input: AVAssetWriterInput?,
        lastTime: inout CMTime
    ) throws {
        guard let input else { return }
        let time = sampleBuffer.presentationTimeStamp
        guard time.isValid, !lastTime.isValid || time > lastTime else { return }
        guard input.isReadyForMoreMediaData else { return }
        guard input.append(sampleBuffer) else {
            throw LocalRecordingError.failedToAppend(writer?.error)
        }
        lastTime = time
    }

    private func resetWriterState() {
        writer = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        profile = nil
        expectsAudio = false
        acceptsOutput = false
        pendingVideo = []
        pendingAudio = []
        lastVideoTime = .invalid
        lastAudioTime = .invalid
        writerError = nil
        writerSessionStartTime = .invalid
        lastMixedVideoSample = nil
        pendingKeyframeCount = 0
        keyframeWriteTasks = []
        reservedKeyframeURLs = []
        capturedStartKeyframe = false
        hasReceivedScreenFrame = false
    }

    private func capturePendingKeyframes(from sampleBuffer: CMSampleBuffer) {
        guard writerSessionStartTime.isValid else { return }
        let count = pendingKeyframeCount
        pendingKeyframeCount = 0
        let timestamp = recordingDuration(through: sampleBuffer)
        for _ in 0..<count {
            captureKeyframe(from: sampleBuffer, timestamp: timestamp)
        }
    }

    private func captureKeyframe(
        from sampleBuffer: CMSampleBuffer,
        timestamp: TimeInterval
    ) {
        guard let imageBuffer = sampleBuffer.imageBuffer,
              let outputURL else {
            return
        }
        let fileURL = makeKeyframeURL(
            timestamp: timestamp,
            directory: outputURL.deletingLastPathComponent()
        )
        let pixelBuffer = KeyframePixelBuffer(value: imageBuffer)
        let task = Task { [keyframeWriter] in
            await keyframeWriter.write(
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                fileURL: fileURL
            )
        }
        keyframeWriteTasks.append(task)
    }

    private func makeKeyframeURL(timestamp: TimeInterval, directory: URL) -> URL {
        let wholeSeconds = Int(max(0, timestamp).rounded(.down))
        let baseName = String(format: "frame-%04d", wholeSeconds)
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension("png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path)
            || reservedKeyframeURLs.contains(candidate) {
            candidate = directory
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension("png")
            suffix += 1
        }
        reservedKeyframeURLs.insert(candidate)
        return candidate
    }

    private func finishKeyframeWrites() async -> [RecordingKeyframe] {
        let tasks = keyframeWriteTasks
        keyframeWriteTasks = []
        var finalizedKeyframes: [RecordingKeyframe] = []
        finalizedKeyframes.reserveCapacity(tasks.count)
        for task in tasks {
            if let keyframe = await task.value {
                finalizedKeyframes.append(keyframe)
            }
        }
        return finalizedKeyframes
    }

    private func cancelKeyframeWrites() async {
        let tasks = keyframeWriteTasks
        keyframeWriteTasks = []
        tasks.forEach { $0.cancel() }
        for task in tasks {
            _ = await task.value
        }
    }

    private func discardRecording(
        writer: AVAssetWriter,
        outputURL: URL
    ) async {
        writer.cancelWriting()
        await cancelKeyframeWrites()
        resetWriterState()
        try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
    }

    private func preserveFailedRecording(
        writer: AVAssetWriter,
        outputURL: URL,
        fileManager: FileManager = .default
    ) async -> URL? {
        writer.cancelWriting()
        _ = await finishKeyframeWrites()

        let recordingDirectory = outputURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: recordingDirectory.path) else {
            resetWriterState()
            return nil
        }

        let recoveryDirectory = RecordingStorage.recordingsDirectory(fileManager: fileManager)
            .appendingPathComponent("Recovery", isDirectory: true)
        var destination = recoveryDirectory.appendingPathComponent(
            recordingDirectory.lastPathComponent,
            isDirectory: true
        )
        var suffix = 2
        do {
            try fileManager.createDirectory(
                at: recoveryDirectory,
                withIntermediateDirectories: true
            )
            while fileManager.fileExists(atPath: destination.path) {
                destination = recoveryDirectory.appendingPathComponent(
                    "\(recordingDirectory.lastPathComponent) \(suffix)",
                    isDirectory: true
                )
                suffix += 1
            }
            try fileManager.moveItem(at: recordingDirectory, to: destination)
            logger.info(
                "Preserved failed recording at \(destination.path, privacy: .private)"
            )
        } catch {
            logger.error(
                "Could not move failed recording into Recovery: \(error.localizedDescription, privacy: .public)"
            )
            destination = recordingDirectory
        }
        resetWriterState()
        return fileManager.fileExists(atPath: destination.path) ? destination : nil
    }

    private func recordingDuration(through sampleBuffer: CMSampleBuffer) -> TimeInterval {
        guard writerSessionStartTime.isValid,
              sampleBuffer.presentationTimeStamp.isValid else {
            return 0
        }
        let duration = CMTimeSubtract(
            sampleBuffer.presentationTimeStamp,
            writerSessionStartTime
        ).seconds
        return duration.isFinite ? max(0, duration) : 0
    }
}

private struct KeyframePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

private actor KeyframeWriter {
    private let imageContext = CIContext()
    private let logger = Logger(
        subsystem: "de.marcusschiesser.contextcast",
        category: "keyframes"
    )

    func write(
        pixelBuffer: KeyframePixelBuffer,
        timestamp: TimeInterval,
        fileURL: URL
    ) -> RecordingKeyframe? {
        guard !Task.isCancelled else { return nil }
        let image = CIImage(cvPixelBuffer: pixelBuffer.value)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            logger.warning("Could not render a recording keyframe")
            return nil
        }
        guard !Task.isCancelled else { return nil }
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            logger.warning("Could not create a recording keyframe image destination")
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            logger.warning("Could not write a recording keyframe")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        guard !Task.isCancelled else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return RecordingKeyframe(timestamp: timestamp, fileURL: fileURL)
    }
}

public enum LocalRecordingError: Error, LocalizedError, Sendable {
    case notRecording
    case unsupportedVideoSettings
    case unsupportedAudioSettings
    case cannotAddVideoInput
    case cannotAddAudioInput
    case failedToStart((any Error)?)
    case failedToAppend((any Error)?)
    case failedToFinish((any Error)?)
    case emptyRecording

    public var errorDescription: String? {
        switch self {
        case .notRecording:
            "No local recording is active."
        case .unsupportedVideoSettings:
            "The selected display size cannot be encoded."
        case .unsupportedAudioSettings:
            "The selected audio format cannot be encoded."
        case .cannotAddVideoInput:
            "The video track could not be added to the local recording."
        case .cannotAddAudioInput:
            "The audio track could not be added to the local recording."
        case .failedToStart:
            "The local recording could not start writing."
        case .failedToAppend:
            "The local recording could not write a media sample."
        case .failedToFinish:
            "The local recording could not be finalized."
        case .emptyRecording:
            "The local recording did not contain any video frames."
        }
    }
}

public struct RecordingRecoveryError: Error, LocalizedError, Sendable {
    public let recoveryURL: URL
    public let diagnosticDescription: String

    public init(recoveryURL: URL, diagnosticDescription: String) {
        self.recoveryURL = recoveryURL
        self.diagnosticDescription = diagnosticDescription
    }

    public var errorDescription: String? {
        "The recording could not be completed, but its partial files were preserved."
    }
}

extension LocalMediaRecorder: MediaMixerOutput {
    public nonisolated func mixer(_ mixer: MediaMixer, didOutput sampleBuffer: CMSampleBuffer) {
        Task { await appendMixedVideo(sampleBuffer) }
    }

    public nonisolated func mixer(
        _ mixer: MediaMixer,
        didOutput buffer: AVAudioPCMBuffer,
        when: AVAudioTime
    ) {
        guard let sampleBuffer = makeAudioSampleBuffer(buffer, when: when) else { return }
        Task { await appendMixedAudio(sampleBuffer) }
    }

    public func selectTrack(_ id: UInt8?, mediaType: CMFormatDescription.MediaType) {}
}

private func makeAudioSampleBuffer(
    _ buffer: AVAudioPCMBuffer,
    when: AVAudioTime
) -> CMSampleBuffer? {
    let presentationTime: CMTime
    if when.isHostTimeValid {
        presentationTime = CMTime(
            seconds: AVAudioTime.seconds(forHostTime: when.hostTime),
            preferredTimescale: 1_000_000_000
        )
    } else if when.isSampleTimeValid {
        presentationTime = CMTime(
            seconds: Double(when.sampleTime) / when.sampleRate,
            preferredTimescale: 1_000_000_000
        )
    } else {
        return nil
    }
    var sampleBuffer: CMSampleBuffer?
    var status = CMAudioSampleBufferCreateWithPacketDescriptions(
        allocator: nil,
        dataBuffer: nil,
        dataReady: false,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: buffer.format.formatDescription,
        sampleCount: Int(buffer.frameLength),
        presentationTimeStamp: presentationTime,
        packetDescriptions: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sampleBuffer else { return nil }
    status = CMSampleBufferSetDataBufferFromAudioBufferList(
        sampleBuffer,
        blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0,
        bufferList: buffer.audioBufferList
    )
    return status == noErr ? sampleBuffer : nil
}

@ScreenActor
private func configureRecordingScreen(
    mixer: MediaMixer,
    profile: OutputProfile,
    webcamEnabled: Bool,
    layout: WebcamLayout
) async throws {
    let screen = mixer.screen
    screen.size = CGSize(width: profile.width, height: profile.height)
    screen.backgroundColor = CGColor(gray: 0, alpha: 1)

    guard webcamEnabled else { return }
    let placement = WebcamLayoutEngine.placement(
        canvasSize: screen.size,
        cameraSize: CGSize(width: 1280, height: 720),
        layout: layout
    )
    let webcam = VideoTrackScreenObject()
    try await waitForHaishinKitVideoDefaults(webcam)
    webcam.track = 1
    webcam.size = placement.frame.size
    webcam.horizontalAlignment = .left
    webcam.verticalAlignment = .top
    webcam.layoutMargin = NSEdgeInsets(
        top: placement.frame.minY,
        left: placement.frame.minX,
        bottom: 0,
        right: 0
    )
    webcam.videoGravity = .resizeAspectFill
    webcam.cornerRadius = placement.cornerRadius
    try screen.addChild(webcam)
}

@ScreenActor
private func waitForHaishinKitVideoDefaults(
    _ webcam: VideoTrackScreenObject
) async throws {
    while true {
        switch webcam.horizontalAlignment {
        case .center:
            return
        case .left, .right:
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}
