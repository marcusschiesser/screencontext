import AppKit
import AVFoundation
import ScreenContextCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: "de.marcusschiesser.screencontext",
        category: "application"
    )
    let analytics: AnalyticsConsentController
    let store: RecordingSessionStore
    let shortcutRecorder = ShortcutRecorder()
    private let contextReturnController = RecordingContextReturnController()
    private var overlayController: WebcamOverlayPanelController?
    private var feedbackController: RecordingFeedbackPanelController?
    private var recordingResultController: RecordingResultPanelController?
    private var shortcutController: GlobalShortcutController?
    private lazy var clickMonitor = MouseClickMonitor { [weak self] in
        self?.store.captureClickKeyframe()
    }
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        // The launch release never initializes a telemetry SDK, even if a local
        // analytics token or a previously enabled preference is present.
        let analyticsClient = NoOpAnalyticsClient()
        analytics = AnalyticsConsentController(client: analyticsClient)
        analytics.setEnabled(false)
        store = RecordingSessionStore(analyticsClient: analyticsClient)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ScreenContext launched")
        analytics.capture(.appLaunched)
        NSApp.setActivationPolicy(.regular)
        contextReturnController.startObserving()
        overlayController = WebcamOverlayPanelController(store: store) { [weak self] in
            self?.overlayController?.hide()
            self?.openSettings()
        }
        let feedbackController = RecordingFeedbackPanelController(store: store)
        let recordingResultController = RecordingResultPanelController(
            store: store,
            analytics: analytics,
            contextReturnController: contextReturnController
        )
        self.feedbackController = feedbackController
        self.recordingResultController = recordingResultController
        shortcutController = GlobalShortcutController { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.store.isInitialized else { return }
                guard !self.shortcutRecorder.capture(self.store.globalShortcut) else { return }
                self.store.toggleRecording()
            }
        }

        store.overlayStateChanged = { [weak self] in
            guard let self else { return }
            self.overlayController?.synchronize()
            self.feedbackController?.synchronize()
            clickMonitor.setActive(store.phase.isRecording)
        }
        store.shortcutPreferenceChanged = { [weak self] shortcut in
            self?.shortcutController?.register(shortcut) ?? false
        }
        store.recordingWillStart = { [weak self] in
            self?.contextReturnController.captureDestination()
        }
        store.recordingResultAvailable = { [weak self] result in
            guard let self else { return }
            contextReturnController.recordingCompleted(
                result,
                retaining: Set(store.recordingResults.map(\.id))
            )
            self.recordingResultController?.present(result)
        }
        store.recordingFailureNoticeAvailable = { [weak self] in
            self?.openSettings()
        }
        store.requestScreenRecordingSettings = {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            ) else {
                return
            }
            NSWorkspace.shared.open(url)
        }
        observeSystemEvents()

        Task {
            await store.initialize()
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("ScreenContext terminating")
        clickMonitor.stop()
        shortcutRecorder.stop()
        contextReturnController.stopObserving()
        store.cancelRecording()
        analytics.flush()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showRecordings() {
        recordingResultController?.presentSelectedRecording()
    }

    func editWebcamLayout() {
        guard store.showsWebcamPositioningOverlay, let source = store.selectedCaptureSource else { return }
        // The Settings button is the entry point; hide that window to reveal the capture canvas.
        NSApp.keyWindow?.orderOut(nil)
        overlayController?.show()
        if case let .window(window) = source {
            CaptureWindowFocusController.focus(window) { [weak self] in
                self?.overlayController?.synchronize()
            }
        }
    }

    func openSettings() {
        overlayController?.hide()
        logger.info("Opening Settings")
        presentSettings()
    }

    private func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let applicationMenu = NSApp.mainMenu?.items.first?.submenu,
           let settingsItemIndex = applicationMenu.items.firstIndex(where: {
               $0.keyEquivalent == ","
                   && $0.keyEquivalentModifierMask.contains(.command)
           }) {
            applicationMenu.performActionForItem(at: settingsItemIndex)
            return
        }

        logger.warning("The SwiftUI Settings menu command was unavailable; trying the responder chain")
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            logger.error("ScreenContext could not present its Settings scene")
        }
    }

    private func observeSystemEvents() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.store.handleFatalSystemEvent(
                        "Recording stopped because the Mac went to sleep."
                    )
                }
            }
        )
        workspaceObservers.append(
            NotificationCenter.default.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let deviceID = (notification.object as? AVCaptureDevice)?.uniqueID else {
                    return
                }
                Task { @MainActor in
                    guard let self else { return }
                    if deviceID == self.store.webcamDeviceID {
                        self.store.handleOptionalInputLoss("Webcam")
                    } else if deviceID == self.store.microphoneDeviceID {
                        self.store.handleOptionalInputLoss("Microphone")
                    }
                }
            }
        )
    }
}
