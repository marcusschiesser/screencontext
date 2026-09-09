import AppKit
import SwiftUI

/// Persists beyond the result window without becoming the user's paste destination.
@MainActor
final class PasteReminderPanelController {
    private let panel: NSPanel
    private var dismissalTask: Task<Void, Never>?

    init() {
        panel = PasteReminderPanel(
            contentRect: .zero,
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

    func show(title: String, locale: Locale, on screen: NSScreen?) {
        dismissalTask?.cancel()
        guard let screen = screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let instruction = String(localized: "Press ⌘V to paste.", locale: locale)
        let width = min(360, screen.visibleFrame.width - 32)
        let hostingView = NSHostingView(rootView: PasteReminderView(
            title: title,
            instruction: instruction
        )
        .frame(width: width)
        .environment(\.locale, locale)
        .environment(
            \.layoutDirection,
            locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
        ))
        panel.title = title
        panel.contentView = hostingView
        let height = ceil(hostingView.fittingSize.height)
        panel.setFrame(NSRect(
            x: screen.visibleFrame.midX - width / 2,
            y: screen.visibleFrame.maxY - height - 24,
            width: width,
            height: height
        ), display: true)
        panel.orderFrontRegardless()
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(title). \(instruction)",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
        dismissalTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            self?.panel.orderOut(nil)
        }
    }
}

private final class PasteReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct PasteReminderView: View {
    let title: String
    let instruction: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(instruction)
                    .font(.callout)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(4)
    }
}
