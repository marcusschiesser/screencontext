@preconcurrency import AVFoundation
import CoreImage
import ScreenContextCore

struct WebcamPreviewFrame: Sendable {
    let image: CGImage
    let generation: UUID
}

/// Session configuration and image processing are confined to one serial queue.
final class WebcamPreviewSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "de.marcusschiesser.screencontext.webcam-preview", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var backgroundBlur = WebcamBackgroundBlurProcessor()
    private var activeCameraID: String?
    private var blursBackground = false
    private var generation = UUID()
    private var acceptsFrames = false
    private let continuation: AsyncStream<WebcamPreviewFrame>.Continuation
    let frames: AsyncStream<WebcamPreviewFrame>

    override init() {
        let stream = AsyncStream.makeStream(of: WebcamPreviewFrame.self, bufferingPolicy: .bufferingNewest(1))
        frames = stream.stream
        continuation = stream.continuation
        super.init()
    }

    deinit {
        continuation.finish()
    }

    func start(cameraID: String?, blursBackground: Bool, generation: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.blursBackground = blursBackground
            self.generation = generation
            backgroundBlur = WebcamBackgroundBlurProcessor()
            if activeCameraID != cameraID || session.inputs.isEmpty {
                configure(cameraID: cameraID)
            }
            acceptsFrames = true
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stopAndWait() {
        queue.sync {
            acceptsFrames = false
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configure(cameraID: String?) {
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        defer { session.commitConfiguration() }
        guard let camera = cameraID.flatMap(AVCaptureDevice.init(uniqueID:))
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        activeCameraID = cameraID
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard acceptsFrames else { return }
        autoreleasepool {
            let renderedSample = blursBackground ? backgroundBlur.process(sampleBuffer: sampleBuffer) : sampleBuffer
            guard let pixelBuffer = renderedSample?.imageBuffer else { return }
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            guard let rendered = context.createCGImage(image, from: image.extent) else { return }
            continuation.yield(WebcamPreviewFrame(image: rendered, generation: generation))
        }
    }
}
