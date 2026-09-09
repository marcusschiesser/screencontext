import AppKit
import ScreenContextCore
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var store: RecordingSessionStore
    let openRecordings: () -> Void

    var body: some View {
        if store.phase == .finalizing {
            Text("Finalizing Recording…")
        } else {
            Button(action: store.toggleRecording) {
                Text(store.phase.isRecording || store.phase == .preparing ? "Stop Recording" : "Start Recording")
            }
            .disabled(!store.isInitialized || store.recordingActionIsUnavailable)
        }
        Text("⇧⌘O")

        Button("Recordings", action: openRecordings)
            .disabled(store.recordingResults.isEmpty)

        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit ScreenContext") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct RecordingStatusLabel: View {
    let store: RecordingSessionStore

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.phase.isRecording ? "record.circle.fill" : "record.circle")
                .foregroundStyle(store.phase.isRecording ? Color.red : Color.primary)
            if store.phase.isRecording || store.phase == .finalizing {
                Text(store.elapsedSeconds.recordingDuration)
                    .monospacedDigit()
            } else if store.phase == .preparing {
                Text("Preparing…")
            }
        }
        .accessibilityLabel(store.phase.isRecording ? "Stop Recording" : "Start Recording")
    }
}

extension TimeInterval {
    var recordingDuration: String {
        let seconds = max(0, Int(self))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
