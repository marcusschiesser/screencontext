@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import CoreVideo
import Foundation
import ScreenContextCore
import XCTest

final class LongRecordingIntegrationTests: XCTestCase {
    func testLongRecordingWithAllInputsFinalizesPlayableMP4() async throws {
        let recordingsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "screencontext-integration-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }
        let recorder = LocalMediaRecorder(recordingsDirectory: recordingsDirectory)
        try await recorder.start(
            profile: OutputProfile(
                width: 640,
                height: 360,
                videoBitRate: 1_000_000,
                frameRate: 30,
                audioBitRate: 128_000
            ),
            capturesAudio: true,
            webcamEnabled: true,
            webcamLayout: .defaultLayout
        )

        let frameRate = 30
        let durationSeconds = 22
        let audioFramesPerVideoFrame: AVAudioFrameCount = 1_600
        let baseSeconds = ProcessInfo.processInfo.systemUptime
        let audioFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        )

        do {
            for frame in 0..<(frameRate * durationSeconds) {
                let timestamp = CMTime(
                    seconds: baseSeconds + Double(frame) / Double(frameRate),
                    preferredTimescale: 1_000_000_000
                )
                let video = try makeVideoSampleBuffer(presentationTimeStamp: timestamp)
                await recorder.appendVideo(video, track: 0)
                await recorder.appendVideo(video, track: 1)

                let audio = try makeAudioSampleBuffer(
                    format: audioFormat,
                    frameCount: audioFramesPerVideoFrame,
                    presentationTimeStamp: timestamp
                )
                await recorder.appendAudio(audio, track: 0)
                await recorder.appendAudio(audio, track: 1)
                try await Task.sleep(for: .milliseconds(34))
            }
            try await Task.sleep(for: .milliseconds(500))

            let artifacts = try await recorder.finish()
            XCTAssertEqual(
                artifacts.recordingURL.deletingLastPathComponent()
                    .deletingLastPathComponent().standardizedFileURL,
                recordingsDirectory.standardizedFileURL
            )
            let asset = AVURLAsset(url: artifacts.recordingURL)
            let duration = try await asset.load(.duration).seconds
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            XCTAssertGreaterThan(duration, 20)
            XCTAssertEqual(videoTracks.count, 1)
            XCTAssertEqual(audioTracks.count, 1)
        } catch {
            await recorder.cancel()
            throw error
        }
    }
}

private func makeVideoSampleBuffer(
    presentationTimeStamp: CMTime
) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault,
        640,
        360,
        kCVPixelFormatType_32BGRA,
        nil,
        &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess, let pixelBuffer else {
        throw NSError(domain: "ScreenContextIntegrationTests", code: Int(pixelStatus))
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
        memset(baseAddress, 0x80, CVPixelBufferGetDataSize(pixelBuffer))
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

    var formatDescription: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else {
        throw NSError(domain: "ScreenContextIntegrationTests", code: Int(formatStatus))
    }
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: presentationTimeStamp,
        decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else {
        throw NSError(domain: "ScreenContextIntegrationTests", code: Int(sampleStatus))
    }
    return sampleBuffer
}

private func makeAudioSampleBuffer(
    format: AVAudioFormat,
    frameCount: AVAudioFrameCount,
    presentationTimeStamp: CMTime
) throws -> CMSampleBuffer {
    let buffer = try XCTUnwrap(
        AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    )
    buffer.frameLength = frameCount
    for channel in 0..<Int(format.channelCount) {
        guard let samples = buffer.floatChannelData?[channel] else { continue }
        for frame in 0..<Int(frameCount) {
            samples[frame] = Float(0.2 * sin(2 * .pi * 440 * Double(frame) / 48_000))
        }
    }

    var sampleBuffer: CMSampleBuffer?
    var status = CMAudioSampleBufferCreateWithPacketDescriptions(
        allocator: nil,
        dataBuffer: nil,
        dataReady: false,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: format.formatDescription,
        sampleCount: Int(frameCount),
        presentationTimeStamp: presentationTimeStamp,
        packetDescriptions: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sampleBuffer else {
        throw NSError(domain: "ScreenContextIntegrationTests", code: Int(status))
    }
    status = CMSampleBufferSetDataBufferFromAudioBufferList(
        sampleBuffer,
        blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0,
        bufferList: buffer.audioBufferList
    )
    guard status == noErr else {
        throw NSError(domain: "ScreenContextIntegrationTests", code: Int(status))
    }
    return sampleBuffer
}
