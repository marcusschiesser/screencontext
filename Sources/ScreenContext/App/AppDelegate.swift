import AppKit
import AVFoundation
import ScreenContextCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: "de.marcusschiesser.contextcast",
        category: "application"
    )
    let analytics: AnalyticsConsentController
    let store: RecordingSessionStore
    private var hudController: HUDPanelController?
    private var recordingResultController: RecordingResultPanelController?
    private var overlayController: WebcamOverlayPanelController?
    private var shortcutController: GlobalShortcutController?
    private lazy var clickMonitor = MouseClickMonitor { [weak self] in
        self?.store.captureClickKeyframe()
    }
    private var workspaceObservers: [NSObjectProtocol] = []

    override init() {
        let analyticsClient: any AnalyticsClient
        if let projectToken = AnalyticsToken.normalized(
            Bundle.main.object(forInfoDictionaryKey: "POSTHOG_PROJECT_TOKEN") as? String
        ) {
            analyticsClient = PostHogAnalyticsClient(projectToken: projectToken)
        } else {
            Logger(
                subsystem: "de.marcusschiesser.contextcast",
                category: "analytics"
            ).warning("PostHog project token is missing; analytics are disabled")
            analyticsClient = NoOpAnalyticsClient()
        }
        analytics = AnalyticsConsentController(client: analyticsClient)
        store = RecordingSessionStore(analyticsClient: analyticsClient)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ScreenContext launched")
        analytics.capture(.appLaunched)
        NSApp.setActivationPolicy(.regular)
        let hudController = HUDPanelController(
            store: store,
            openSettings: { [weak self] in
                self?.openSettings()
            },
            openRecordings: { [weak self] in
                self?.showRecordings()
            },
            hideControls: { [weak self] in
                self?.hideHUD()
            },
            focusWindow: { [weak self] window in
                self?.focus(window)
            }
        )
        let overlayController = WebcamOverlayPanelController(store: store)
        let recordingResultController = RecordingResultPanelController(
            store: store,
            parent: hudController,
            analytics: analytics
        )
        self.hudController = hudController
        self.overlayController = overlayController
        self.recordingResultController = recordingResultController
        shortcutController = GlobalShortcutController { [weak self] in
            DispatchQueue.main.async { self?.showHUD() }
        }

        store.overlayStateChanged = { [weak self] in
            self?.overlayController?.synchronize()
            self?.hudController?.synchronizeWidth()
            guard let self else { return }
            clickMonitor.setActive(store.phase.isRecording)
        }
        store.shortcutPreferenceChanged = { [weak self] enabled in
            self?.shortcutController?.setEnabled(enabled)
        }
        store.recordingResultAvailable = { [weak recordingResultController] result in
            recordingResultController?.present(result)
        }
        store.recordingFailureNoticeAvailable = { [weak self] in
            self?.showHUD()
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
            showHUD()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHUD()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("ScreenContext terminating")
        clickMonitor.stop()
        store.cancelRecording()
        analytics.flush()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showHUD() {
        hudController?.show()
        overlayController?.show()
    }

    func hideHUD() {
        hudController?.hide()
        overlayController?.hide()
    }

    func showRecordings() {
        recordingResultController?.presentSelectedRecording()
    }

    private func focus(_ window: WindowSource) {
        CaptureWindowFocusController.focus(window) { [weak self] in
            self?.overlayController?.synchronize()
        }
    }

    func openSettings() {
        logger.info("Opening Settings from the HUD")
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
