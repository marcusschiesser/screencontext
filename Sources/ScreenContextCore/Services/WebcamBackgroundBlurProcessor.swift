import CoreImage
import CoreMedia
import CoreVideo
import Vision

/// One instance per camera stream, confined to its serial sample queue.
public final class WebcamBackgroundBlurProcessor {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let personMask: (CVPixelBuffer) throws -> CIImage?
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero

    public convenience init() {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        self.init { pixelBuffer in
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try handler.perform([request])
            return request.results?.first.map { CIImage(cvPixelBuffer: $0.pixelBuffer) }
        }
    }

    init(personMask: @escaping (CVPixelBuffer) throws -> CIImage?) {
        self.personMask = personMask
    }

    /// Retains camera dimensions and timing. If segmentation fails, blur the entire
    /// frame; if rendering cannot allocate a buffer, drop it instead of exposing raw video.
    public func process(sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let source = sampleBuffer.imageBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: source)
        let mask = try? personMask(source)
        let result = Self.composite(image: image, personMask: mask)
        guard let destination = makePixelBuffer(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source)) else {
            return nil
        }
        CVBufferPropagateAttachments(source, destination)
        context.render(result, to: destination)

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: destination,
            formatDescriptionOut: &format
        ) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing) == noErr else {
            return nil
        }
        var output: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: destination,
            formatDescription: format, sampleTiming: &timing,
            sampleBufferOut: &output
        ) == noErr else { return nil }
        return output
    }

    static func composite(image: CIImage, personMask: CIImage?) -> CIImage {
        let extent = image.extent
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(extent.width, extent.height) / 45])
            .cropped(to: extent)
        guard let personMask, !personMask.extent.isEmpty else { return blurred }
        let mask = personMask.transformed(by: CGAffineTransform(
            scaleX: extent.width / personMask.extent.width,
            y: extent.height / personMask.extent.height
        ))
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: mask,
        ]).cropped(to: extent)
    }

    private func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let size = CGSize(width: width, height: height)
        if pool == nil || poolSize != size {
            pool = nil
            poolSize = size
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else {
                return nil
            }
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        let limits = [kCVPixelBufferPoolAllocationThresholdKey as String: 6] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, limits, &buffer) == kCVReturnSuccess else {
            return nil
        }
        return buffer
    }
}
