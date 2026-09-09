import ScreenContextCore
import SwiftUI

@main
struct ScreenContextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: appDelegate.store,
                openRecordings: appDelegate.showRecordings,
                openSettings: appDelegate.openSettings
            )
            .environment(\.locale, appDelegate.store.effectiveLocale)
            .environment(
                \.layoutDirection,
                appDelegate.store.usesRightToLeftLayout ? .rightToLeft : .leftToRight
            )
        } label: {
            RecordingStatusLabel(store: appDelegate.store)
        }

        Settings {
            SettingsView(
                store: appDelegate.store,
                analytics: appDelegate.analytics,
                shortcutRecorder: appDelegate.shortcutRecorder,
                editWebcamLayout: appDelegate.editWebcamLayout
            )
            .background(WindowAccessor(onWindowAttached: appDelegate.registerSettingsWindow))
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
