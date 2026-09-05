import AppKit
import ScreenContextCore
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var store: RecordingSessionStore
    let openHUD: () -> Void
    let hideHUD: () -> Void
    let openRecordings: () -> Void

    var body: some View {
        Button("Open ScreenContext", action: openHUD)
            .keyboardShortcut("o")
        Button("Hide Controls", action: hideHUD)
        Button("Recordings", action: openRecordings)
            .disabled(store.recordingResults.isEmpty)

        if store.phase == .preparing || store.phase.isRecording {
            Button("Stop Recording", action: store.stopRecording)
        } else if store.phase == .finalizing {
            Text("Finalizing Recording…")
        }

        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit ScreenContext") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
