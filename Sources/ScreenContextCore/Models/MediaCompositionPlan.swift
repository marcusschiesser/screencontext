import CoreGraphics
import Foundation

public struct MediaCompositionPlan: Equatable, Sendable {
    public let outputSize: CGSize
    public let webcamPlacement: WebcamPlacement?
    public let videoTracks: Set<UInt8>
    public let audioTracks: Set<UInt8>

    public init(
        configuration: RecordingConfiguration,
        profile: OutputProfile,
        cameraSize: CGSize = CGSize(width: 1280, height: 720)
    ) {
        outputSize = CGSize(width: profile.width, height: profile.height)
        videoTracks = configuration.capturesWebcam ? [0, 1] : [0]
        var audioTracks = Set<UInt8>()
        if configuration.capturesSystemAudio {
            audioTracks.insert(
                MediaTrackLayout.systemAudioTrack(
                    capturesMicrophone: configuration.capturesMicrophone
                )
            )
        }
        if configuration.capturesMicrophone {
            audioTracks.insert(MediaTrackLayout.microphoneTrack)
        }
        self.audioTracks = audioTracks
        webcamPlacement = configuration.capturesWebcam
            ? WebcamLayoutEngine.placement(
                canvasSize: outputSize,
                cameraSize: cameraSize,
                layout: configuration.webcamLayout
            )
            : nil
    }
}

enum MediaTrackLayout {
    static let microphoneTrack: UInt8 = 0

    static func systemAudioTrack(capturesMicrophone: Bool) -> UInt8 {
        capturesMicrophone ? 1 : 0
    }
}
