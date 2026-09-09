import ScreenContextCore
import SwiftUI

struct CaptureSettingsView: View {
    @Bindable var store: RecordingSessionStore

    let editWebcamLayout: @MainActor () -> Void

    var body: some View {
        Form {
            Section {
                Text("Press \(store.globalShortcut.displayName) to start recording. Press it again to stop.")
                    .foregroundStyle(.secondary)
                if store.phase == .preparing {
                    ProgressView("Preparing…")
                } else if store.phase.isRecording || store.phase == .finalizing {
                    HStack {
                        Text(store.phase.isRecording ? "Stop Recording" : "Finalizing Recording…")
                        Spacer()
                        Text(store.elapsedSeconds.recordingDuration).monospacedDigit()
                    }
                }
            }

            Section("Recording source") {
                Menu {
                    Section("Screens") {
                        ForEach(store.screens) { sourceButton(.display($0)) }
                    }
                    Section("Windows") {
                        if store.windows.isEmpty { Text("No windows available") }
                        ForEach(store.windows) { sourceButton(.window($0)) }
                    }
                } label: {
                    if let source = store.selectedCaptureSource {
                        Text(verbatim: source.displayName) // localization: allow-verbatim runtime capture-source name
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("Choose a screen or window")
                    }
                }
                .accessibilityLabel("Recording source")

                HStack {
                    Button("Refresh Sources") { Task { await store.refreshSources() } }
                    if store.captureSources.isEmpty || store.screenCaptureAccessDenied {
                        Button("Allow Screen Recording…", action: store.requestScreenCaptureAccess)
                    }
                }
            }
            .disabled(store.configurationIsLocked)

            Section("Audio") {
                Toggle("System Audio", isOn: Binding(
                    get: { store.capturesSystemAudio },
                    set: { enabled in Task { await store.setSystemAudioEnabled(enabled) } }
                ))
                Toggle("Microphone", isOn: Binding(
                    get: { store.capturesMicrophone },
                    set: { enabled in Task { await store.setMicrophoneEnabled(enabled) } }
                ))
                if store.capturesMicrophone {
                    Picker("Microphone", selection: Binding(
                        get: { store.microphoneDeviceID },
                        set: { id in Task { await store.selectMicrophoneDevice(id) } }
                    )) {
                        ForEach(store.microphones) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            .disabled(store.configurationIsLocked)

            Section("Webcam") {
                Toggle("Webcam", isOn: Binding(
                    get: { store.capturesWebcam },
                    set: { enabled in Task { await store.setWebcamEnabled(enabled) } }
                ))
                if store.capturesWebcam {
                    Picker("Webcam", selection: Binding(
                        get: { store.webcamDeviceID },
                        set: { id in Task { await store.selectWebcamDevice(id) } }
                    )) {
                        ForEach(store.cameras) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Edit Webcam Layout…", action: editWebcamLayout)
                        .disabled(store.selectedCaptureSource == nil)
                }
            }
            .disabled(store.configurationIsLocked)

            if let message = store.hudMessage {
                Section {
                    Label {
                        Text(verbatim: message) // localization: allow-verbatim runtime error description
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    Button("Dismiss", action: store.clearWarning)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(!store.isInitialized)
        .task {
            guard !store.configurationIsLocked else { return }
            await store.refreshSources()
        }
    }

    private func sourceButton(_ source: CaptureSource) -> some View {
        Button {
            store.selectCaptureSource(source.id)
        } label: {
            if source.id == store.selectedCaptureSourceID {
                Label(source.displayName, systemImage: "checkmark")
            } else {
                Text(verbatim: source.displayName) // localization: allow-verbatim runtime capture-source name
            }
        }
    }
}
