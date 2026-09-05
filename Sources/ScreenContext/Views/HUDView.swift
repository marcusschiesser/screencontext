import AppKit
import ScreenContextCore
import SwiftUI

struct HUDView: View {
    @Bindable var store: RecordingSessionStore
    let openSettings: @MainActor () -> Void
    let openRecordings: @MainActor () -> Void
    let hideHUD: @MainActor () -> Void
    let focusWindow: @MainActor (WindowSource) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isGoButtonHovered = false
    @State private var isHideButtonHovered = false

    var body: some View {
        HStack(spacing: 0) {
            hideButton
            dragHandle
            hudDivider
            sourcePicker
            hudDivider
            audioControls
            hudDivider
            webcamControls
            hudDivider
            if let warning = store.hudMessage {
                warningBanner(warning)
                hudDivider
            }
            statusControls
        }
        .padding(.horizontal, 6)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(colorScheme == .light ? 0.38 : 0.035))
                }
        }
        .padding(3)
        .environment(\.locale, store.effectiveLocale)
        .environment(\.layoutDirection, store.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
        .disabled(!store.isInitialized)
        .alert(
            "Recording Couldn’t Be Saved",
            isPresented: Binding(
                get: { store.recordingFailureNotice != nil },
                set: { isPresented in
                    if !isPresented {
                        store.dismissRecordingFailureNotice()
                    }
                }
            ),
            presenting: store.recordingFailureNotice
        ) { notice in
            if let recoveryURL = notice.recoveryURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([recoveryURL])
                    store.dismissRecordingFailureNotice()
                }
            }
            Button("Dismiss", role: .cancel) {
                store.dismissRecordingFailureNotice()
            }
        } message: { notice in
            recordingFailureMessage(for: notice)
        }
    }

    private var hideButton: some View {
        Button(action: hideHUD) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 36)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHideButtonHovered ? 0.09 : 0))
                }
        }
        .buttonStyle(.plain)
        .help("Hide ScreenContext Controls — reopen with ⇧⌘O")
        .accessibilityLabel("Hide ScreenContext Controls")
        .onHover { isHideButtonHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHideButtonHovered)
    }

    private var dragHandle: some View {
        ZStack {
            WindowDragSurface()

            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 4) {
                        Circle()
                            .frame(width: 3.5, height: 3.5)
                        Circle()
                            .frame(width: 3.5, height: 3.5)
                    }
                }
            }
            .foregroundStyle(Color.secondary.opacity(0.72))
            .allowsHitTesting(false)
        }
        .frame(width: 32, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
            .accessibilityLabel("Drag ScreenContext")
    }

    private var hudDivider: some View {
        Divider()
            .frame(height: 40)
            .opacity(0.6)
            .padding(.horizontal, 7)
    }

    private var sourcePicker: some View {
        Menu {
            if store.captureSources.isEmpty {
                Button {
                    store.requestScreenCaptureAccess()
                } label: {
                    Label("Allow Screen Recording…", systemImage: "lock.open")
                }
                Divider()
            }

            Section("Screens") {
                ForEach(store.screens) { screen in
                    captureSourceButton(.display(screen))
                }
            }

            Section("Windows") {
                if store.windows.isEmpty {
                    Text("No windows available")
                } else {
                    ForEach(store.windows) { window in
                        captureSourceButton(.window(window))
                    }
                }
            }

            Divider()
            Button("Refresh Sources") {
                Task { await store.refreshSources() }
            }
        } label: {
            Group {
                if let source = store.selectedCaptureSource {
                    Label {
                        Text(verbatim: source.displayName) // localization: allow-verbatim runtime capture-source name
                    } icon: {
                        Image(systemName: selectedSourceSymbol)
                    }
                } else {
                    Label("Choose a screen or window", systemImage: selectedSourceSymbol)
                }
            }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 178, alignment: .leading)
                .padding(.horizontal, 4)
                .frame(height: 36)
        }
        .menuStyle(.borderlessButton)
        .disabled(store.configurationIsLocked)
        .help("Choose a screen or window to record")
        .accessibilityLabel("Recording source")
    }

    private var selectedSourceSymbol: String {
        switch store.selectedCaptureSource {
        case .display: "display"
        case .window: "macwindow"
        case nil: "rectangle.on.rectangle.slash"
        }
    }

    private func captureSourceButton(_ source: CaptureSource) -> some View {
        Button {
            store.selectCaptureSource(source.id)
            if case let .window(window) = source {
                focusWindow(window)
            }
        } label: {
            if source.id == store.selectedCaptureSource?.id {
                Label(source.displayName, systemImage: "checkmark")
            } else {
                Text(verbatim: source.displayName) // localization: allow-verbatim runtime capture-source name
            }
        }
    }

    private var audioControls: some View {
        HStack(spacing: 1) {
            iconToggle(
                title: "System Audio",
                systemImage: store.capturesSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
                isOn: Binding(
                    get: { store.capturesSystemAudio },
                    set: { enabled in
                        Task { await store.setSystemAudioEnabled(enabled) }
                    }
                )
            )

            iconToggle(
                title: "Microphone",
                systemImage: store.capturesMicrophone ? "mic.fill" : "mic.slash.fill",
                isOn: Binding(
                    get: { store.capturesMicrophone },
                    set: { enabled in
                        Task { await store.setMicrophoneEnabled(enabled) }
                    }
                )
            )

            if store.capturesMicrophone {
                deviceMenu(
                    title: "Microphone",
                    help: "Choose a microphone",
                    icon: "chevron.down",
                    devices: store.microphones,
                    selection: Binding(
                        get: { store.microphoneDeviceID },
                        set: { deviceID in
                            Task { await store.selectMicrophoneDevice(deviceID) }
                        }
                    )
                )
            }
        }
        .disabled(store.configurationIsLocked)
    }

    private var webcamControls: some View {
        HStack(spacing: 1) {
            iconToggle(
                title: "Webcam",
                systemImage: store.capturesWebcam ? "video.fill" : "video.slash.fill",
                isOn: Binding(
                    get: { store.capturesWebcam },
                    set: { enabled in
                        Task { await store.setWebcamEnabled(enabled) }
                    }
                )
            )

            if store.capturesWebcam {
                deviceMenu(
                    title: "Webcam",
                    help: "Choose a webcam",
                    icon: "chevron.down",
                    devices: store.cameras,
                    selection: Binding(
                        get: { store.webcamDeviceID },
                        set: { deviceID in
                            Task { await store.selectWebcamDevice(deviceID) }
                        }
                    )
                )
            }
        }
        .disabled(store.configurationIsLocked)
    }

    private var statusControls: some View {
        HStack(spacing: 5) {
            if !store.recordingResults.isEmpty {
                Button(action: openRecordings) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recordings")
                .accessibilityLabel("Recordings")
            }

            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Settings")
            .accessibilityLabel("Open Settings")

            Button(action: store.toggleRecording) {
                HStack(spacing: 6) {
                    if isRecordingTransitioning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: canStopRecording ? "stop.fill" : "record.circle.fill")
                    }

                    Text(canStopRecording ? "Stop" : "Go")

                    if canStopRecording {
                        Text(store.elapsedSeconds.durationString)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            canStopRecording
                                ? Color.red.opacity(
                                    isGoButtonHovered
                                        ? (colorScheme == .dark ? 0.34 : 0.18)
                                        : (colorScheme == .dark ? 0.24 : 0.12)
                                )
                                : isGoButtonHovered
                                    ? Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.14)
                                    : Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.055)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            canStopRecording
                                ? Color.red.opacity(isGoButtonHovered ? 0.52 : 0.28)
                                : isGoButtonHovered
                                    ? Color.accentColor.opacity(0.42)
                                    : Color.primary.opacity(0.07)
                        )
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                canStopRecording
                    ? Color.red
                    : isGoButtonHovered ? Color.accentColor : Color.primary
            )
            .disabled(store.recordingActionIsUnavailable)
            .disabled(isRecordingTransitioning)
            .keyboardShortcut(.return, modifiers: [])
            .help(canStopRecording ? "Stop recording" : "Start recording")
            .onHover { isGoButtonHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isGoButtonHovered)
        }
    }

    private var canStopRecording: Bool {
        store.phase.isRecording
    }

    private var isRecordingTransitioning: Bool {
        store.phase == .preparing || store.phase == .finalizing
    }

    private func iconToggle(
        title: LocalizedStringKey,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    private func deviceMenu(
        title: String,
        help: LocalizedStringKey,
        icon: String,
        devices: [CaptureDeviceOption],
        selection: Binding<String?>
    ) -> some View {
        Menu {
            ForEach(devices) { device in
                Button {
                    selection.wrappedValue = device.id
                } label: {
                    if selection.wrappedValue == device.id {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 36)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(Text(help))
    }

    private func warningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(verbatim: message) // localization: allow-verbatim runtime error description
                .lineLimit(2)
            Button("Dismiss") { store.clearWarning() }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 280)
        .fixedSize(horizontal: true, vertical: false)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func recordingFailureMessage(for notice: RecordingFailureNotice) -> some View {
        switch notice.kind {
        case .partialRecordingPreserved:
            Text(
                "ScreenContext preserved the partial recording. Show it in Finder to see whether it can be played."
            )
        case .recordingNotSaved:
            Text(
                "No usable recording was produced. Check your recording settings and try again."
            )
        }
    }
}

private struct WindowDragSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

private extension TimeInterval {
    var durationString: String {
        let seconds = max(0, Int(self))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
