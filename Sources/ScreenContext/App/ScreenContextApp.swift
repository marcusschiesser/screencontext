import ScreenContextCore
import SwiftUI

@main
struct ScreenContextApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: appDelegate.store,
                openHUD: appDelegate.showHUD,
                hideHUD: appDelegate.hideHUD,
                openRecordings: appDelegate.showRecordings
            )
            .environment(\.locale, appDelegate.store.effectiveLocale)
            .environment(
                \.layoutDirection,
                appDelegate.store.usesRightToLeftLayout ? .rightToLeft : .leftToRight
            )
        } label: {
            Image(systemName: appDelegate.store.phase.isRecording ? "record.circle.fill" : "record.circle")
        }

        Settings {
            SettingsView(store: appDelegate.store, analytics: appDelegate.analytics)
        }
        .defaultLaunchBehavior(.suppressed)
    }
}
