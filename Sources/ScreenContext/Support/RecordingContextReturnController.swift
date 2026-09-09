import AppKit
import Observation
import ScreenContextCore

/// Keeps live application references only; destinations must not survive an app restart.
@MainActor
@Observable
final class RecordingContextReturnController {
    private var destinations: [RecordingResult.ID: NSRunningApplication] = [:]
    @ObservationIgnored private var lastExternalApplication: NSRunningApplication?
    @ObservationIgnored private var pendingApplication: NSRunningApplication?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    func startObserving() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.rememberExternalApplication(application)
            }
        }
    }

    func stopObserving() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    func captureDestination() {
        // Read synchronously before preparation can bring ScreenContext forward.
        // Settings/menu starts use the last external app instead of ScreenContext.
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        pendingApplication = lastExternalApplication
    }

    func recordingCompleted(_ result: RecordingResult, retaining recordingIDs: Set<UUID>) {
        destinations = destinations.filter { recordingIDs.contains($0.key) }
        destinations[result.id] = pendingApplication
        pendingApplication = nil
    }

    func destination(for recordingID: RecordingResult.ID) -> NSRunningApplication? {
        destinations[recordingID]
    }

    func activate(_ application: NSRunningApplication) async -> Bool {
        // Never relaunch an app or resolve its PID again: the original process
        // may have exited, and its previous editor/window would be gone.
        guard !application.isTerminated else { return false }
        // An accessibility/keyboard action can reach a background result window.
        // Establish our activation before transferring it, as in capture focus.
        NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<25 {
            if NSApp.isActive { break }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
        guard !Task.isCancelled, !application.isTerminated else { return false }
        application.unhide()
        NSApp.yieldActivation(to: application)
        if !application.activate(from: .current, options: []) {
            guard application.activate(options: []) else { return false }
        }
        for _ in 0..<50 {
            if application.isActive { return true }
            guard !application.isTerminated, !Task.isCancelled else { return false }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return false
            }
        }
        return application.isActive
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular else { return }
        lastExternalApplication = application
    }
}
