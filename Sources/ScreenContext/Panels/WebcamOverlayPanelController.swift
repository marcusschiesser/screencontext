@preconcurrency import AppKit
@preconcurrency import AVFoundation
import ScreenContextCore
import SwiftUI

@MainActor
final class WebcamOverlayPanelController {
    private static let shapePickerSize = CGSize(width: 224, height: 36)
    private static let shapePickerSpacing: CGFloat = 3

    private let store: RecordingSessionStore
    private let panel: WebcamOverlayPanel
    private let shapePanel: WebcamOverlayPanel
    private let contentView: WebcamOverlayContentView
    private let previewSession = WebcamPreviewSession()
    private var geometryTask: Task<Void, Never>?
    private var isPresented = false

    init(store: RecordingSessionStore, finishEditing: @escaping @MainActor () -> Void) {
        self.store = store
        panel = WebcamOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        shapePanel = WebcamOverlayPanel(
            contentRect: CGRect(origin: .zero, size: Self.shapePickerSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = WebcamOverlayContentView()
        panel.contentView = contentView
        let shapeHostingView = NSHostingView(
            rootView: WebcamShapePicker(store: store, finishEditing: finishEditing)
        )
        shapeHostingView.wantsLayer = true
        shapeHostingView.layer?.backgroundColor = NSColor.clear.cgColor
        shapeHostingView.layer?.isOpaque = false
        shapePanel.contentView = shapeHostingView

        for overlayPanel in [panel, shapePanel] {
            overlayPanel.isOpaque = false
            overlayPanel.backgroundColor = .clear
            overlayPanel.hasShadow = false
            overlayPanel.level = .floating
            overlayPanel.hidesOnDeactivate = false
            overlayPanel.isReleasedWhenClosed = false
            overlayPanel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
            ]
        }
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true

        contentView.onDrag = { [weak store] center, canvasSize in
            store?.updateWebcamPosition(
                WebcamLayoutEngine.normalizedPosition(
                    forTopLeftOrigin: center,
                    canvasSize: canvasSize
                )
            )
        }
        contentView.onResize = { [weak store] size, center, canvasSize in
            store?.updateWebcamSize(
                size,
                position: WebcamLayoutEngine.normalizedPosition(
                    forTopLeftOrigin: center,
                    canvasSize: canvasSize
                )
            )
        }
    }

    func show() {
        isPresented = true
        synchronize()
    }

    func hide() {
        isPresented = false
        dismissOverlay()
    }

    func synchronize() {
        if store.configurationIsLocked { isPresented = false }
        guard isPresented, store.showsWebcamPositioningOverlay else {
            dismissOverlay()
            return
        }

        guard let source = store.selectedCaptureSource else {
            stopGeometryTracking()
            panel.orderOut(nil)
            shapePanel.orderOut(nil)
            previewSession.stopAndWait()
            return
        }

        previewSession.start(cameraID: store.webcamDeviceID)
        if case .window = source {
            startGeometryTracking()
        } else {
            stopGeometryTracking()
        }
        synchronizeGeometry()
    }

    private func dismissOverlay() {
        stopGeometryTracking()
        contentView.setHovered(false)
        panel.orderOut(nil)
        shapePanel.orderOut(nil)
        previewSession.stopAndWait()
    }

    private func synchronizeGeometry() {
        guard store.showsWebcamPositioningOverlay,
              let source = store.selectedCaptureSource,
              let canvasFrame = canvasFrame(for: source) else {
            panel.orderOut(nil)
            shapePanel.orderOut(nil)
            return
        }

        let canvasSize = canvasFrame.size
        let placement = WebcamLayoutEngine.placement(
            canvasSize: canvasSize,
            cameraSize: CGSize(width: 1280, height: 720),
            layout: store.webcamLayout
        )
        let appKitFrame = CGRect(
            x: canvasFrame.minX + placement.frame.minX,
            y: canvasFrame.minY + canvasSize.height - placement.frame.maxY,
            width: placement.frame.width,
            height: placement.frame.height
        )
        if panel.frame != appKitFrame {
            panel.setFrame(appKitFrame, display: true)
        }
        let shapePickerFrame = shapePickerFrame(near: appKitFrame, inside: canvasFrame)
        if shapePanel.frame != shapePickerFrame {
            shapePanel.setFrame(shapePickerFrame, display: true)
        }
        contentView.update(
            canvasFrame: canvasFrame,
            cornerRadius: placement.cornerRadius,
            mask: store.webcamLayout.mask,
            size: store.webcamLayout.size,
            captureSession: previewSession.session
        )
        contentView.setPreviewAccessibilityLabel(
            String(
                localized: "Webcam overlay; drag to move or drag its border to resize",
                locale: store.effectiveLocale
            )
        )
        panel.orderFrontRegardless()
        shapePanel.orderFrontRegardless()
    }

    private func canvasFrame(for source: CaptureSource) -> CGRect? {
        switch source {
        case let .display(screen):
            return screen.frame
        case let .window(window):
            return liveAppKitFrame(forWindowID: window.windowID)
        }
    }

    private func liveAppKitFrame(forWindowID windowID: UInt32) -> CGRect? {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow, .excludeDesktopElements],
            CGWindowID(windowID)
        ) as? [[String: Any]],
              let info = windowInfo.first,
              info[kCGWindowIsOnscreen as String] as? Bool != false,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let screenCaptureFrame = CGRect(
                dictionaryRepresentation: bounds as CFDictionary
              ),
              let primaryDisplayMaxY = NSScreen.screens.first(where: {
                guard let number = $0.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber else { return false }
                return number.uint32Value == CGMainDisplayID()
              })?.frame.maxY else {
            return nil
        }

        return ScreenCaptureKitSourceCatalog.appKitFrame(
            fromScreenCaptureFrame: screenCaptureFrame,
            primaryDisplayMaxY: primaryDisplayMaxY
        )
    }

    private func startGeometryTracking() {
        guard geometryTask == nil else { return }
        geometryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.synchronizeGeometry()
            }
        }
    }

    private func stopGeometryTracking() {
        geometryTask?.cancel()
        geometryTask = nil
    }

    private func shapePickerFrame(near previewFrame: CGRect, inside canvasFrame: CGRect) -> CGRect {
        let size = Self.shapePickerSize
        let maximumX = max(canvasFrame.minX, canvasFrame.maxX - size.width)
        let x = min(max(previewFrame.minX, canvasFrame.minX), maximumX)
        var y = previewFrame.maxY + Self.shapePickerSpacing
        if y + size.height > canvasFrame.maxY {
            y = previewFrame.minY - Self.shapePickerSpacing - size.height
        }
        let maximumY = max(canvasFrame.minY, canvasFrame.maxY - size.height)
        y = min(max(y, canvasFrame.minY), maximumY)
        return CGRect(
            x: x,
            y: y,
            width: size.width,
            height: size.height
        )
    }
}

private struct WebcamShapePicker: View {
    @Bindable var store: RecordingSessionStore
    let finishEditing: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("Webcam shape", selection: maskSelection) {
                ForEach(WebcamMask.allCases) { mask in
                    Label(mask.title, systemImage: mask.symbolName)
                        .labelStyle(.iconOnly)
                        .tag(mask)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Choose webcam shape")
            .accessibilityLabel("Webcam shape")
            Button("Done", action: finishEditing)
        }
        .controlSize(.small)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .environment(\.locale, store.effectiveLocale)
        .environment(\.layoutDirection, store.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
    }

    private var maskSelection: Binding<WebcamMask> {
        Binding(
            get: { store.webcamLayout.mask },
            set: { mask in
                var layout = store.webcamLayout
                layout.mask = mask
                store.webcamLayout = layout
            }
        )
    }
}

private extension WebcamMask {
    var title: LocalizedStringKey {
        switch self {
        case .rectangle: "Rectangle"
        case .rounded: "Rounded"
        case .square: "Square"
        case .circle: "Circle"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle: "rectangle"
        case .rounded: "rectangle.roundedtop"
        case .square: "square"
        case .circle: "circle"
        }
    }
}

private final class WebcamOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class WebcamOverlayContentView: NSView {
    var onDrag: ((CGPoint, CGSize) -> Void)?
    var onResize: ((WebcamSize, CGPoint, CGSize) -> Void)?
    private(set) var isDragging = false
    private let previewView = CameraLayerView()
    private var dragOffset = CGPoint.zero
    private var resizeHandle: ResizeHandle?
    private var resizeStartFrame = CGRect.zero
    private var resizeStartSize = WebcamSize.medium
    private var currentSize = WebcamSize.medium
    private var canvasFrame = CGRect.zero
    private var isHovered = false
    private var pointerTrackingArea: NSTrackingArea?
    private let resizeHitWidth: CGFloat = 10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(previewView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .activeAlways,
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate,
                .enabledDuringMouseDrag,
                .inVisibleRect,
            ],
            owner: self
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        setHovered(false)
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateBorderAppearance()
        let point = convert(event.locationInWindow, from: nil)
        if let handle = resizeHandle(at: point) {
            resizeHandle = handle
            resizeStartFrame = window?.frame ?? .zero
            resizeStartSize = currentSize
            updateCursor(at: point)
            return
        }
        guard let windowFrame = window?.frame else { return }
        let mouseLocation = NSEvent.mouseLocation
        dragOffset = CGPoint(
            x: mouseLocation.x - windowFrame.midX,
            y: mouseLocation.y - windowFrame.midY
        )
        updateCursor(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
        if let resizeHandle {
            resize(with: resizeHandle, to: NSEvent.mouseLocation)
            return
        }
        let mouseLocation = NSEvent.mouseLocation
        let centerInScreen = CGPoint(
            x: mouseLocation.x - dragOffset.x,
            y: mouseLocation.y - dragOffset.y
        )
        onDrag?(topLeftCenter(forScreenCenter: centerInScreen), canvasFrame.size)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        isDragging = false
        resizeHandle = nil
        setHovered(bounds.contains(point))
        updateBorderAppearance()
        updateCursor(at: point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !bounds.isEmpty else { return }
        addCursorRect(bounds.insetBy(dx: resizeHitWidth, dy: resizeHitWidth), cursor: .openHand)
        for handle in ResizeHandle.allCases {
            addCursorRect(cursorRect(for: handle), cursor: handle.cursor)
        }
    }

    func update(
        canvasFrame: CGRect,
        cornerRadius: CGFloat,
        mask: WebcamMask,
        size: WebcamSize,
        captureSession: AVCaptureSession
    ) {
        self.canvasFrame = canvasFrame
        currentSize = size
        previewView.frame = bounds
        previewView.previewLayer.session = captureSession
        previewView.layer?.cornerRadius = cornerRadius
        previewView.layer?.masksToBounds = true
        previewView.layer?.shadowOpacity = 0
        previewView.setAccessibilityLabel("Webcam overlay; drag to move or drag its border to resize")
        previewView.needsDisplay = true
        updateBorderAppearance()
        window?.invalidateCursorRects(for: self)
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        updateBorderAppearance()
    }

    func setPreviewAccessibilityLabel(_ label: String) {
        previewView.setAccessibilityLabel(label)
    }

    private func updateBorderAppearance() {
        let isHighlighted = isHovered || isDragging
        previewView.layer?.borderWidth = isHighlighted ? 4 : 2
        previewView.layer?.borderColor = isHighlighted
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.72).cgColor
    }

    private func updateCursor(at point: CGPoint) {
        if let resizeHandle {
            resizeHandle.cursor.set()
        } else if isDragging {
            NSCursor.closedHand.set()
        } else if let handle = resizeHandle(at: point) {
            handle.cursor.set()
        } else if bounds.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func resizeHandle(at point: CGPoint) -> ResizeHandle? {
        guard bounds.contains(point) else { return nil }
        let hitWidth = min(resizeHitWidth, min(bounds.width, bounds.height) / 2)
        let isLeft = point.x <= bounds.minX + hitWidth
        let isRight = point.x >= bounds.maxX - hitWidth
        let isBottom = point.y <= bounds.minY + hitWidth
        let isTop = point.y >= bounds.maxY - hitWidth

        switch (isLeft, isRight, isBottom, isTop) {
        case (true, _, true, _): return .bottomLeft
        case (true, _, _, true): return .topLeft
        case (_, true, true, _): return .bottomRight
        case (_, true, _, true): return .topRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .bottom
        case (_, _, _, true): return .top
        default: return nil
        }
    }

    private func resize(with handle: ResizeHandle, to point: CGPoint) {
        guard resizeStartFrame.width > 0, resizeStartFrame.height > 0 else { return }
        let horizontalScale: CGFloat?
        if handle.isLeft {
            horizontalScale = (resizeStartFrame.maxX - point.x) / resizeStartFrame.width
        } else if handle.isRight {
            horizontalScale = (point.x - resizeStartFrame.minX) / resizeStartFrame.width
        } else {
            horizontalScale = nil
        }

        let verticalScale: CGFloat?
        if handle.isBottom {
            verticalScale = (resizeStartFrame.maxY - point.y) / resizeStartFrame.height
        } else if handle.isTop {
            verticalScale = (point.y - resizeStartFrame.minY) / resizeStartFrame.height
        } else {
            verticalScale = nil
        }

        let requestedScale: CGFloat
        if let horizontalScale, let verticalScale {
            requestedScale = abs(horizontalScale - 1) >= abs(verticalScale - 1)
                ? horizontalScale
                : verticalScale
        } else {
            requestedScale = horizontalScale ?? verticalScale ?? 1
        }
        let requestedSize = WebcamSize(
            percentage: resizeStartSize.percentage * Double(max(requestedScale, 0))
        )
        let scale = CGFloat(requestedSize.percentage / resizeStartSize.percentage)
        let newSize = CGSize(
            width: resizeStartFrame.width * scale,
            height: resizeStartFrame.height * scale
        )
        let origin = CGPoint(
            x: handle.isLeft
                ? resizeStartFrame.maxX - newSize.width
                : handle.isRight
                    ? resizeStartFrame.minX
                    : resizeStartFrame.midX - newSize.width / 2,
            y: handle.isBottom
                ? resizeStartFrame.maxY - newSize.height
                : handle.isTop
                    ? resizeStartFrame.minY
                    : resizeStartFrame.midY - newSize.height / 2
        )
        let resizedFrame = CGRect(origin: origin, size: newSize)
        onResize?(
            requestedSize,
            topLeftCenter(forScreenCenter: CGPoint(x: resizedFrame.midX, y: resizedFrame.midY)),
            canvasFrame.size
        )
    }

    private func topLeftCenter(forScreenCenter center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x - canvasFrame.minX,
            y: canvasFrame.maxY - center.y
        )
    }

    private func cursorRect(for handle: ResizeHandle) -> CGRect {
        let hitWidth = min(resizeHitWidth, min(bounds.width, bounds.height) / 2)
        switch handle {
        case .left:
            return CGRect(
                x: bounds.minX,
                y: bounds.minY + hitWidth,
                width: hitWidth,
                height: max(0, bounds.height - 2 * hitWidth)
            )
        case .right:
            return CGRect(
                x: bounds.maxX - hitWidth,
                y: bounds.minY + hitWidth,
                width: hitWidth,
                height: max(0, bounds.height - 2 * hitWidth)
            )
        case .bottom:
            return CGRect(
                x: bounds.minX + hitWidth,
                y: bounds.minY,
                width: max(0, bounds.width - 2 * hitWidth),
                height: hitWidth
            )
        case .top:
            return CGRect(
                x: bounds.minX + hitWidth,
                y: bounds.maxY - hitWidth,
                width: max(0, bounds.width - 2 * hitWidth),
                height: hitWidth
            )
        case .bottomLeft:
            return CGRect(x: bounds.minX, y: bounds.minY, width: hitWidth, height: hitWidth)
        case .bottomRight:
            return CGRect(x: bounds.maxX - hitWidth, y: bounds.minY, width: hitWidth, height: hitWidth)
        case .topLeft:
            return CGRect(x: bounds.minX, y: bounds.maxY - hitWidth, width: hitWidth, height: hitWidth)
        case .topRight:
            return CGRect(
                x: bounds.maxX - hitWidth,
                y: bounds.maxY - hitWidth,
                width: hitWidth,
                height: hitWidth
            )
        }
    }
}

private enum ResizeHandle: CaseIterable {
    case left
    case right
    case bottom
    case top
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight

    var isLeft: Bool { self == .left || self == .bottomLeft || self == .topLeft }
    var isRight: Bool { self == .right || self == .bottomRight || self == .topRight }
    var isBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    var isTop: Bool { self == .top || self == .topLeft || self == .topRight }

    var cursor: NSCursor {
        let position: NSCursor.FrameResizePosition = switch self {
        case .left: .left
        case .right: .right
        case .bottom: .bottom
        case .top: .top
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        case .topLeft: .topLeft
        case .topRight: .topRight
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

}

private final class CameraLayerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

private final class WebcamPreviewSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "de.marcusschiesser.screencontext.webcam-preview", qos: .userInitiated)
    private var activeCameraID: String?

    func start(cameraID: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            if activeCameraID != cameraID || session.inputs.isEmpty {
                configure(cameraID: cameraID)
            }
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stopAndWait() {
        queue.sync {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configure(cameraID: String?) {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        session.inputs.forEach(session.removeInput)
        defer { session.commitConfiguration() }
        guard let camera = cameraID.flatMap(AVCaptureDevice.init(uniqueID:))
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            return
        }
        session.addInput(input)
        activeCameraID = camera.uniqueID
    }
}
