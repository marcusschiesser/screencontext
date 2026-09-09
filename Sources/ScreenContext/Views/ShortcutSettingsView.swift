import ScreenContextCore
import SwiftUI

struct ShortcutSettingsView: View {
    let store: RecordingSessionStore
    let recorder: ShortcutRecorder

    var body: some View {
        Section {
            LabeledContent {
                HStack {
                    Button {
                        if recorder.isRecording {
                            recorder.stop()
                        } else {
                            recorder.start(completion: store.updateGlobalShortcut)
                        }
                    } label: {
                        if recorder.isRecording {
                            Text("Cancel")
                        } else {
                            Text(store.globalShortcut.displayName)
                                .monospaced()
                        }
                    }
                    .accessibilityLabel(recorder.isRecording ? "Cancel" : "Change shortcut")
                    .accessibilityValue(store.globalShortcut.displayName)
                    .help("Click to record a new shortcut.")

                    Button("Reset") {
                        recorder.stop()
                        store.updateGlobalShortcut(.defaultShortcut)
                    }
                    .disabled(store.globalShortcut == .defaultShortcut || recorder.isRecording)
                }
            } label: {
                Text("Global shortcut")
            }

            if recorder.isRecording {
                Text("Press a key with ⌘, ⌃, or ⌥. Press Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(recorder.needsModifier ? Color.orange : .secondary)
            } else {
                Text("Press \(store.globalShortcut.displayName) to start recording. Press it again to stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.shortcutRegistrationFailed {
                Text("This shortcut is unavailable. Choose a different combination.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(!store.isInitialized)
        .onDisappear { recorder.stop() }
    }
}
