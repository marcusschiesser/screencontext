import CoreImage
import CoreMedia
import CoreVideo
import XCTest
@testable import ScreenContextCore

final class WebcamBackgroundBlurTests: XCTestCase {
    func testKeepsForegroundSharpAndBlursBackgroundWithScaledMask() throws {
        let sample = try makeStripedSample()
        // Vision masks are smaller than the camera frame. Keep its left half sharp.
        let maskBounds = CGRect(x: 0, y: 0, width: 64, height: 36)
        let mask = CIImage(color: .white)
            .cropped(to: CGRect(x: 0, y: 0, width: 32, height: 36))
            .composited(over: CIImage(color: .black).cropped(to: maskBounds))
        let processor = WebcamBackgroundBlurProcessor { _ in mask }
        let output = try XCTUnwrap(processor.process(sampleBuffer: sample))
        let source = try XCTUnwrap(sample.imageBuffer)
        let result = try XCTUnwrap(output.imageBuffer)

        XCTAssertLessThan(meanDifference(source, result, columns: 16..<110), 2)
        XCTAssertGreaterThan(meanDifference(source, result, columns: 145..<240), 40)
        XCTAssertEqual(CVPixelBufferGetWidth(result), 256)
        XCTAssertEqual(CVPixelBufferGetHeight(result), 144)
        XCTAssertEqual(output.presentationTimeStamp, sample.presentationTimeStamp)
        XCTAssertEqual(output.duration, sample.duration)
        XCTAssertEqual(output.decodeTimeStamp, sample.decodeTimeStamp)
        // Processing must not overwrite the camera's buffer.
        XCTAssertEqual(channel(source, x: 16, y: 50), 0)
        XCTAssertEqual(channel(source, x: 20, y: 50), 255)
    }

    func testMissingOrFailedSegmentationBlursEntireFrame() throws {
        enum SegmentationFailure: Error { case unavailable }
        let sample = try makeStripedSample()
        let processors = [
            WebcamBackgroundBlurProcessor { _ in nil },
            WebcamBackgroundBlurProcessor { _ in throw SegmentationFailure.unavailable },
        ]
        for processor in processors {
            let output = try XCTUnwrap(processor.process(sampleBuffer: sample))
            XCTAssertGreaterThan(meanDifference(
                try XCTUnwrap(sample.imageBuffer), try XCTUnwrap(output.imageBuffer), columns: 16..<240
            ), 40)
        }
    }

    func testOlderPreferencesDefaultToUnblurredAndEnabledSettingRoundTrips() throws {
        let legacy = try JSONDecoder().decode(PreferencesSnapshot.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.blursWebcamBackground)
        let enabled = PreferencesSnapshot(blursWebcamBackground: true)
        XCTAssertEqual(try JSONDecoder().decode(
            PreferencesSnapshot.self, from: JSONEncoder().encode(enabled)
        ), enabled)
    }

    private func makeStripedSample() throws -> CMSampleBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 256, 144,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
            &buffer
        ), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<144 {
            for x in 0..<256 {
                let value: UInt8 = (x / 4).isMultiple(of: 2) ? 0 : 255
                let offset = y * stride + x * 4
                base[offset] = value
                base[offset + 1] = value
                base[offset + 2] = value
                base[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels, formatDescriptionOut: &format
        ), noErr)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: 90, timescale: 30),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixels,
            formatDescription: try XCTUnwrap(format), sampleTiming: &timing,
            sampleBufferOut: &sample
        ), noErr)
        return try XCTUnwrap(sample)
    }

    private func meanDifference(_ lhs: CVPixelBuffer, _ rhs: CVPixelBuffer, columns: Range<Int>) -> Double {
        columns.reduce(0.0) { total, x in
            total + Double(abs(Int(channel(lhs, x: x, y: 50)) - Int(channel(rhs, x: x, y: 50))))
        } / Double(columns.count)
    }

    private func channel(_ buffer: CVPixelBuffer, x: Int, y: Int) -> UInt8 {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        return base[y * CVPixelBufferGetBytesPerRow(buffer) + x * 4]
    }
}
