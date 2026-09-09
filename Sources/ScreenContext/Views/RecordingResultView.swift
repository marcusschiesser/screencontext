import AppKit
import AVKit
import ScreenContextCore
import SwiftUI

struct RecordingResultView: View {
    @Bindable var store: RecordingSessionStore
    let fallbackResult: RecordingResult
    let mediaHeight: CGFloat
    let analytics: AnalyticsConsentController
    let contextReturnController: RecordingContextReturnController
    let contextReturned: @MainActor (Locale) -> Void
    let dismiss: @MainActor () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var copyToastMessage: String?
    @State private var copyToastDismissTask: Task<Void, Never>?
    @State private var isConfirmingDeletion = false
    @State private var isDeletingRecording = false
    @State private var destinationAlert: RecordingContextDestinationAlert?
    @State private var isReturningToApplication = false

    var body: some View {
        NavigationSplitView {
            recordingSidebar
                .disabled(isReturningToApplication)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            recordingDetail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 860)
        .overlay(alignment: .top) {
            if let copyToastMessage {
                Label(copyToastMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onDisappear {
            copyToastDismissTask?.cancel()
        }
        .confirmationDialog(
            "Delete Recording?",
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete Recording", role: .destructive) {
                Task {
                    isDeletingRecording = true
                    let didDelete = await store.deleteSelectedRecording()
                    isDeletingRecording = false
                    if didDelete, store.recordingResults.isEmpty {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("This permanently deletes the recording.")
        }
        .alert(item: $destinationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("Done"))
            )
        }
        .environment(\.locale, locale)
    }

    private var recordingSidebar: some View {
        List(selection: recordingSelection) {
            Section("Recordings") {
                ForEach(store.recordingResults.reversed()) { recording in
                    RecordingSidebarRow(result: recording)
                        .tag(recording.id)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Recordings")
    }

    private var recordingSelection: Binding<RecordingResult.ID?> {
        Binding(
            get: { store.selectedRecordingID },
            set: { id in
                guard let id else { return }
                store.selectRecording(id)
            }
        )
    }

    private var recordingDetail: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                recordingHeader

                RecordingPlayerView(fileURL: result.fileURL)
                    .frame(width: 572, height: mediaHeight)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.10),
                                lineWidth: 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        copyButton(
                            accessibilityLabel: "Copy video",
                            help: "Copy the local video file"
                        ) {
                            copyVideoToPasteboard(result.fileURL)
                        }
                        .padding(10)
                    }
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12),
                        radius: 16,
                        y: 8
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Label("Recording context", systemImage: "text.quote")
                        .font(.headline)

                    ReadOnlyContextTextView(
                        text: result.context,
                        accessibilityLabel: String(localized: "Recording context", locale: locale)
                    )
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        copyButton(accessibilityLabel: "Copy context", help: "Copy context") {
                            copyContextToPasteboard()
                        }
                        .padding(8)
                    }
                    if let application = contextReturnController.destination(for: result.id) {
                        HStack {
                            Button {
                                copyAndReturn(to: application)
                            } label: {
                                Label(copyAndReturnTitle(for: application), systemImage: "arrow.uturn.backward")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .disabled(isReturningToApplication)
                            .accessibilityLabel(copyAndReturnTitle(for: application))
                            .keyboardShortcut("c", modifiers: [.command, .shift])
                            .help("Copy context and switch back to the original app. Press ⌘V there to paste.")

                            Spacer(minLength: 8)

                            Text("Paste with ⌘V")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                }
                .padding(14)
                .frame(height: 180)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(colorScheme == .light ? 0.28 : 0.025))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 20)

            Divider()

            recordingActions
        }
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var recordingHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(
                    result.recordedAt,
                    format: .dateTime
                        .year()
                        .month(.wide)
                        .day()
                )
                .font(.title2.weight(.semibold))

                Label {
                    Text(result.recordedAt, format: .dateTime.hour().minute())
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

        }
    }

    private var recordingActions: some View {
        HStack {
            Button(role: .destructive) {
                isConfirmingDeletion = true
            } label: {
                Label("Delete Recording", systemImage: "trash")
            }
            .disabled(isDeletingRecording || isReturningToApplication)

            Spacer()
            Button("Done", action: dismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(.bar)
    }

    private var result: RecordingResult {
        store.selectedRecordingResult ?? fallbackResult
    }

    private var locale: Locale { store.effectiveLocale }

    private func copyVideoToPasteboard(_ fileURL: URL) {
        let item = NSPasteboardItem()
        guard item.setString(fileURL.absoluteString, forType: .fileURL) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return }

        analytics.capture(.videoCopied)
        showCopyToast(String(localized: "Video copied", locale: locale))
    }

    @discardableResult
    private func copyContextToPasteboard(showConfirmation: Bool = true) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(result.context, forType: .string) else {
            destinationAlert = RecordingContextDestinationAlert(
                title: String(localized: "Couldn’t Copy Context", locale: locale),
                message: String(localized: "Try copying the context again.", locale: locale)
            )
            return false
        }

        analytics.capture(.contextCopied)
        if showConfirmation {
            showCopyToast(String(localized: "Context copied", locale: locale))
        }
        return true
    }

    private func copyAndReturnTitle(for application: NSRunningApplication) -> String {
        String(
            format: String(localized: "Copy & Return to %@", locale: locale),
            locale: locale,
            application.localizedName ?? application.bundleIdentifier ?? ""
        )
    }

    private func copyAndReturn(to application: NSRunningApplication) {
        guard !isReturningToApplication,
              copyContextToPasteboard(showConfirmation: false) else { return }
        isReturningToApplication = true
        Task { @MainActor in
            let didActivate = await contextReturnController.activate(application)
            isReturningToApplication = false
            if didActivate {
                contextReturned(locale)
            } else {
                destinationAlert = RecordingContextDestinationAlert(
                    title: String(localized: "Context copied", locale: locale),
                    message: String(
                        localized: "Couldn’t return to the original app. Switch to your destination and press ⌘V to paste.",
                        locale: locale
                    )
                )
            }
        }
    }

    private func showCopyToast(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )

        copyToastDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            copyToastMessage = message
        }
        copyToastDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            withAnimation(.easeIn(duration: 0.15)) {
                copyToastMessage = nil
            }
        }
    }

    private func copyButton(
        accessibilityLabel: LocalizedStringKey,
        help: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel(Text(accessibilityLabel))
        .help(Text(help))
    }
}

private struct RecordingContextDestinationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct RecordingSidebarRow: View {
    let result: RecordingResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(
                    result.recordedAt,
                    format: .dateTime
                        .year()
                        .month(.abbreviated)
                        .day()
                )
                .fontWeight(.medium)
                .lineLimit(1)

                Text(result.recordedAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordingPlayerView: NSViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = HoverControlsPlayerView()
        playerView.videoGravity = .resizeAspect
        playerView.player = context.coordinator.player
        context.coordinator.loadAndPlay(fileURL)
        return playerView
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        guard context.coordinator.currentURL != fileURL else { return }
        context.coordinator.loadAndPlay(fileURL)
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        coordinator.player.replaceCurrentItem(with: nil)
        playerView.player = nil
    }

    final class Coordinator {
        let player = AVPlayer()
        private(set) var currentURL: URL?

        func loadAndPlay(_ fileURL: URL) {
            currentURL = fileURL
            player.replaceCurrentItem(with: AVPlayerItem(url: fileURL))
            player.play()
        }
    }
}

private final class HoverControlsPlayerView: AVPlayerView {
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        controlsStyle = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        controlsStyle = .none
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        controlsStyle = .minimal
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        controlsStyle = .none
        super.mouseExited(with: event)
    }
}
