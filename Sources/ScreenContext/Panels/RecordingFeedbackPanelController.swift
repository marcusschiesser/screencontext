import AppKit
import ScreenContextCore
import SwiftUI

/// A transient, nonactivating surface; recording state remains owned by the store.
@MainActor
final class RecordingFeedbackPanelController {
    private let store: RecordingSessionStore
    private let panel: NSPanel
    private var previousPhase = RecordingPhase.idle
    private var previousWarning: String?
    private var dismissalTask: Task<Void, Never>?

    init(store: RecordingSessionStore) {
        self.store = store
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func synchronize() {
        let wasFinalizing = previousPhase == .finalizing
        let phaseChanged = store.phase != previousPhase
        let warningChanged = store.hudMessage != previousWarning
        previousPhase = store.phase
        previousWarning = store.hudMessage
        guard phaseChanged || warningChanged else { return }

        dismissalTask?.cancel()
        if store.phase == .idle && store.hudMessage == nil {
            if wasFinalizing {
                scheduleDismissal()
            } else {
                panel.orderOut(nil)
            }
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - panel.frame.width / 2,
            y: screen.visibleFrame.maxY - panel.frame.height - 24
        ))
        panel.contentView = NSHostingView(rootView: RecordingFeedbackView(
            phase: store.phase,
            message: store.hudMessage,
            locale: store.effectiveLocale,
            isRightToLeft: store.usesRightToLeftLayout
        ))
        panel.orderFrontRegardless()
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        // Preparation/finalization remain visible until the actual phase changes.
        guard store.phase != .preparing, store.phase != .finalizing else { return }
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private var announcement: String {
        if let warning = store.hudMessage { return warning }
        switch store.phase {
        case .preparing: return String(localized: "Preparing…", locale: store.effectiveLocale)
        case .recording: return String(localized: "Recording started", locale: store.effectiveLocale)
        case .finalizing: return String(localized: "Recording stopped", locale: store.effectiveLocale)
        default: return ""
        }
    }
}

private struct RecordingFeedbackView: View {
    let phase: RecordingPhase
    let message: String?
    let locale: Locale
    let isRightToLeft: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(phase.isRecording ? Color.red : Color.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                if let warning = message {
                    Text(verbatim: warning) // localization: allow-verbatim runtime error description
                        .font(.callout)
                        .lineLimit(3)
                } else {
                    Text(title).font(.headline)
                    if phase == .finalizing {
                        Text("Finalizing Recording…")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Press ⇧⌘O to start recording. Press it again to stop.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(4)
        .environment(\.locale, locale)
        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
    }

    private var title: LocalizedStringKey {
        switch phase {
        case .preparing: "Preparing…"
        case .recording: "Recording started"
        case .finalizing: "Recording stopped"
        default: "Recording"
        }
    }

    private var symbol: String {
        if message != nil { return "exclamationmark.triangle" }
        return switch phase {
        case .preparing: "hourglass"
        case .recording: "record.circle.fill"
        default: "stop.circle"
        }
    }
}
