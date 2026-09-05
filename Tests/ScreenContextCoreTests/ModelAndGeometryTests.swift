import CoreGraphics
import XCTest
@testable import ScreenContextCore

final class ModelAndGeometryTests: XCTestCase {
    func testSourceRestorationUsesOnlyPersistentDisplayIDs() async throws {
        let primary = makeScreen(id: 1, isPrimary: true)
        let secondary = makeScreen(id: 2, origin: CGPoint(x: -1920, y: 0))
        let window = makeWindow(id: 12)
        let sources: [CaptureSource] = [.display(primary), .display(secondary), .window(window)]
        let catalog = StaticSourceCatalog(values: sources)

        let restoredDisplay = catalog.restoredSource(from: sources, preferredID: .display(2))
        XCTAssertEqual(restoredDisplay?.id, .display(2))
        let rejectedWindow = catalog.restoredSource(from: sources, preferredID: .window(12))
        XCTAssertEqual(rejectedWindow?.id, .display(1))
        XCTAssertNil(catalog.restoredSource(
            from: [.window(window)],
            preferredID: .window(12)
        ))
    }

    func testOutputProfilePreservesAspectCapsAt4KAndUsesEvenDimensions() {
        let fiveK = makeScreen(id: 1, width: 5120, height: 2880)
        let profile = OutputProfile.make(for: fiveK)
        XCTAssertEqual(profile.width, 3840)
        XCTAssertEqual(profile.height, 2160)
        XCTAssertEqual(profile.videoBitRate, 6_000_000)
        XCTAssertEqual(profile.width % 2, 0)
        XCTAssertEqual(profile.height % 2, 0)

        let belowFullHD = OutputProfile.make(
            for: makeScreen(id: 2, width: 1440, height: 900)
        )
        XCTAssertEqual(belowFullHD.videoBitRate, 4_500_000)
    }

    func testWindowOutputProfileUsesWindowPixelDimensions() {
        let window = makeWindow(id: 9, width: 2561, height: 1441)
        let profile = OutputProfile.make(for: .window(window))

        XCTAssertEqual(profile.width, 2560)
        XCTAssertEqual(profile.height, 1440)
        XCTAssertEqual(profile.videoBitRate, 6_000_000)
    }

    func testLiveFilterGeometryDeterminesWindowOutputProfile() {
        let dimensions = ScreenCaptureKitContentFilterFactory.pixelDimensions(
            contentRect: CGRect(x: 40, y: 80, width: 1400, height: 900),
            pointPixelScale: 2
        )
        let profile = OutputProfile.make(
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height
        )

        XCTAssertEqual(dimensions.width, 2800)
        XCTAssertEqual(dimensions.height, 1800)
        XCTAssertEqual(profile.width, 2800)
        XCTAssertEqual(profile.height, 1800)
    }

    func testRuntimeWindowIdentityRejectsReusedWindowID() {
        let selected = makeWindow(id: 12, title: "Roadmap", applicationName: "Notes")
        let reusedID = makeWindow(id: 12, title: "Inbox", applicationName: "Notes")

        XCTAssertFalse(reusedID.matchesRuntimeIdentity(of: selected))
        XCTAssertTrue(selected.matchesRuntimeIdentity(of: selected))
    }

    func testScreenCaptureWindowFrameConvertsToAppKitCoordinates() {
        let converted = ScreenCaptureKitSourceCatalog.appKitFrame(
            fromScreenCaptureFrame: CGRect(x: -1200, y: 920, width: 800, height: 500),
            primaryDisplayMaxY: 1080
        )

        XCTAssertEqual(converted, CGRect(x: -1200, y: -340, width: 800, height: 500))
    }

    func testWebcamGeometryClampsEveryMaskAndSizeAtEdges() {
        let canvases = [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 2560, height: 1440),
            CGSize(width: 1512, height: 982),
        ]
        for canvas in canvases {
            for mask in WebcamMask.allCases {
                for size in [WebcamSize.small, .medium, .large, .extraLarge] {
                    let layout = WebcamLayout(
                        mask: mask,
                        size: size,
                        position: NormalizedWebcamPosition(x: 1, y: 1)
                    )
                    let placement = WebcamLayoutEngine.placement(
                        canvasSize: canvas,
                        cameraSize: CGSize(width: 1280, height: 720),
                        layout: layout
                    )
                    XCTAssertGreaterThan(placement.frame.width, 0)
                    XCTAssertGreaterThan(placement.frame.height, 0)
                    XCTAssertGreaterThanOrEqual(placement.frame.minX, 0)
                    XCTAssertGreaterThanOrEqual(placement.frame.minY, 0)
                    XCTAssertLessThanOrEqual(placement.frame.maxX, canvas.width + 0.001)
                    XCTAssertLessThanOrEqual(placement.frame.maxY, canvas.height + 0.001)
                    if mask == .circle || mask == .square {
                        XCTAssertEqual(
                            placement.frame.width,
                            placement.frame.height,
                            accuracy: 0.001
                        )
                    }
                    if mask == .circle {
                        XCTAssertEqual(
                            placement.cornerRadius,
                            placement.frame.width / 2,
                            accuracy: 0.001
                        )
                    }
                }
            }
        }
    }

    func testWebcamGeometrySupportsContinuousClampedSizes() {
        let canvas = CGSize(width: 1920, height: 1080)
        let camera = CGSize(width: 1280, height: 720)
        let custom = WebcamLayoutEngine.placement(
            canvasSize: canvas,
            cameraSize: camera,
            layout: WebcamLayout(size: WebcamSize(percentage: 31.5))
        )
        let minimum = WebcamLayoutEngine.placement(
            canvasSize: canvas,
            cameraSize: camera,
            layout: WebcamLayout(size: WebcamSize(percentage: -10))
        )
        let maximum = WebcamLayoutEngine.placement(
            canvasSize: canvas,
            cameraSize: camera,
            layout: WebcamLayout(size: WebcamSize(percentage: 90))
        )

        XCTAssertEqual(WebcamSize(percentage: -10), .small)
        XCTAssertEqual(WebcamSize(percentage: 90), .extraLarge)
        XCTAssertGreaterThan(custom.frame.width, minimum.frame.width)
        XCTAssertLessThan(custom.frame.width, maximum.frame.width)
    }

    func testNormalizedPlacementIsIndependentOfDisplayOriginAndScale() {
        let negativeOrigin = makeScreen(
            id: 2,
            width: 3024,
            height: 1964,
            origin: CGPoint(x: -1512, y: 120),
            scale: 2
        )
        let positiveOrigin = makeScreen(
            id: 3,
            width: 3024,
            height: 1964,
            origin: CGPoint(x: 2560, y: -400),
            scale: 1
        )
        let layout = WebcamLayout(
            mask: .rounded,
            size: .large,
            position: NormalizedWebcamPosition(x: 0.2, y: 0.3)
        )
        let first = WebcamLayoutEngine.placement(
            canvasSize: CGSize(width: negativeOrigin.pixelWidth, height: negativeOrigin.pixelHeight),
            cameraSize: CGSize(width: 1280, height: 720),
            layout: layout
        )
        let second = WebcamLayoutEngine.placement(
            canvasSize: CGSize(width: positiveOrigin.pixelWidth, height: positiveOrigin.pixelHeight),
            cameraSize: CGSize(width: 1280, height: 720),
            layout: layout
        )
        XCTAssertEqual(first, second)
    }

    func testSyntheticCompositionPlanIncludesRequestedTracksAndSharedPlacement() throws {
        let screen = makeScreen(id: 1)
        let layout = WebcamLayout(
            mask: .circle,
            size: .medium,
            position: NormalizedWebcamPosition(x: 0.25, y: 0.75)
        )
        let configuration = RecordingConfiguration(
            source: .display(screen),
            capturesSystemAudio: true,
            capturesMicrophone: true,
            microphoneDeviceID: "mic",
            capturesWebcam: true,
            webcamDeviceID: "camera",
            webcamLayout: layout
        )
        let profile = OutputProfile.make(for: screen)
        let plan = MediaCompositionPlan(configuration: configuration, profile: profile)
        XCTAssertEqual(plan.outputSize, CGSize(width: profile.width, height: profile.height))
        XCTAssertEqual(plan.videoTracks, [0, 1])
        XCTAssertEqual(plan.audioTracks, [0, 1])
        XCTAssertEqual(
            plan.webcamPlacement,
            WebcamLayoutEngine.placement(
                canvasSize: plan.outputSize,
                cameraSize: CGSize(width: 1280, height: 720),
                layout: layout
            )
        )
    }

    func testEveryValidRecordingStateTransition() {
        let now = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(RecordingStateMachine.transition(from: .idle, event: .prepare), .preparing)
        XCTAssertEqual(RecordingStateMachine.transition(from: .preparing, event: .begin(now)), .recording(startedAt: now))
        XCTAssertEqual(RecordingStateMachine.transition(from: .recording(startedAt: now), event: .stop), .finalizing)
        XCTAssertEqual(RecordingStateMachine.transition(from: .finalizing, event: .finish), .idle)
        XCTAssertEqual(RecordingStateMachine.transition(from: .idle, event: .fail("error")), .failed(message: "error"))
        XCTAssertEqual(RecordingStateMachine.transition(from: .failed(message: "error"), event: .reset), .idle)
        XCTAssertNil(RecordingStateMachine.transition(from: .idle, event: .begin(now)))
    }

    func testElapsedTimerIsVisibleOnlyWhileRecording() {
        XCTAssertFalse(RecordingPhase.preparing.showsElapsedTimer)
        XCTAssertTrue(RecordingPhase.recording(startedAt: Date()).showsElapsedTimer)
        XCTAssertFalse(RecordingPhase.finalizing.showsElapsedTimer)
    }
}

private actor StaticSourceCatalog: CaptureSourceCatalog {
    let values: [CaptureSource]
    init(values: [CaptureSource]) { self.values = values }
    func sources() -> [CaptureSource] { values }
}

func makeScreen(
    id: UInt32,
    width: Int = 1920,
    height: Int = 1080,
    origin: CGPoint = .zero,
    scale: Double = 1,
    isPrimary: Bool = false
) -> ScreenSource {
    ScreenSource(
        displayID: id,
        name: "Display \(id)",
        pixelWidth: width,
        pixelHeight: height,
        frame: CGRect(
            origin: origin,
            size: CGSize(width: Double(width) / scale, height: Double(height) / scale)
        ),
        backingScaleFactor: scale,
        isPrimary: isPrimary
    )
}

func makeWindow(
    id: UInt32,
    title: String = "Document",
    applicationName: String = "Example",
    width: Int = 1280,
    height: Int = 720,
    origin: CGPoint = CGPoint(x: 120, y: 80),
    scale: Double = 2
) -> WindowSource {
    WindowSource(
        windowID: id,
        title: title,
        applicationName: applicationName,
        applicationBundleIdentifier: "com.example.app",
        processIdentifier: 123,
        pixelWidth: width,
        pixelHeight: height,
        frame: CGRect(
            origin: origin,
            size: CGSize(width: Double(width) / scale, height: Double(height) / scale)
        ),
        backingScaleFactor: scale
    )
}
