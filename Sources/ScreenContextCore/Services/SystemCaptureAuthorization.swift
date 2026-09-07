@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

public actor SystemCaptureAuthorization: CaptureAuthorization {
    private let bundleIdentifier: String
    private var systemAudioIsPrepared = false

    public init(bundleIdentifier: String = "de.marcusschiesser.screencontext") {
        self.bundleIdentifier = bundleIdentifier
    }

    public func requestCameraAccess() async -> Bool {
        await requestAccess(for: .video)
    }

    public func requestMicrophoneAccess() async -> Bool {
        await requestAccess(for: .audio)
    }

    public func requestSystemAudioAccess(for source: CaptureSource) async -> Bool {
        if systemAudioIsPrepared { return true }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            let resolvedTarget = try ScreenCaptureKitContentFilterFactory.resolve(
                for: source,
                in: content,
                excludingBundleIdentifier: bundleIdentifier
            )
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.queueDepth = 1
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.showsCursor = false
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2

            let output = SystemAudioPermissionProbeOutput()
            let stream = SCStream(
                filter: resolvedTarget.filter,
                configuration: configuration,
                delegate: nil
            )
            try stream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: output.queue
            )
            do {
                try await stream.startCapture()
                try? await Task.sleep(for: .milliseconds(150))
                try await stream.stopCapture()
                systemAudioIsPrepared = true
                return true
            } catch {
                try? await stream.stopCapture()
                return false
            }
        } catch {
            return false
        }
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }
}

private final class SystemAudioPermissionProbeOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(
        label: "de.marcusschiesser.screencontext.permission.system-audio",
        qos: .userInitiated
    )

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {}
}
