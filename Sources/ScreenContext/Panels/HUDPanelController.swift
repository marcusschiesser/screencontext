import AppKit
import ScreenContextCore
import SwiftUI

@MainActor
final class HUDPanelController: NSObject, NSWindowDelegate {
    private static let height: CGFloat = 58

    private let panel: FloatingHUDPanel

    init(
        store: RecordingSessionStore,
        openSettings: @escaping @MainActor () -> Void,
        openRecordings: @escaping @MainActor () -> Void,
        hideControls: @escaping @MainActor () -> Void,
        focusWindow: @escaping @MainActor (WindowSource) -> Void
    ) {
        panel = FloatingHUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: Self.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.delegate = self
        panel.title = "ScreenContext"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(
            rootView: HUDView(
                store: store,
                openSettings: openSettings,
                openRecordings: openRecordings,
                hideHUD: hideControls,
                focusWindow: focusWindow
            )
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        resizeToFit(animated: false)
        positionAtTopCenter()
    }

    func show() {
        resizeToFit(animated: false)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func synchronizeWidth(animated: Bool = true) {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.resizeToFit(animated: animated)
        }
    }

    private func resizeToFit(animated: Bool) {
        panel.contentView?.layoutSubtreeIfNeeded()
        let targetWidth = ceil(panel.contentView?.fittingSize.width ?? panel.frame.width)
        guard abs(panel.frame.width - targetWidth) > 0.5 else { return }

        var frame = panel.frame
        let centerX = frame.midX
        frame.size.width = targetWidth
        frame.origin.x = centerX - targetWidth / 2
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }

    func presentSheet(_ sheet: NSWindow) {
        show()
        guard sheet.sheetParent == nil else { return }
        panel.beginSheet(sheet)
    }

    func dismissSheet(_ sheet: NSWindow) {
        guard sheet.sheetParent === panel else { return }
        panel.endSheet(sheet)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 24
        )
        panel.setFrameOrigin(origin)
    }
}

private final class FloatingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
