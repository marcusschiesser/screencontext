import AppKit
import ScreenContextCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: RecordingSessionStore
    @Bindable var analytics: AnalyticsConsentController
    let shortcutRecorder: ShortcutRecorder
    let editWebcamLayout: @MainActor () -> Void

    var body: some View {
        TabView {
            CaptureSettingsView(
                store: store,
                shortcutRecorder: shortcutRecorder,
                editWebcamLayout: editWebcamLayout
            )
                .tabItem {
                    Label("Recordings", systemImage: "record.circle")
                }

            GeneralSettingsView(store: store)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 620, height: 600)
        .padding()
        .environment(\.locale, store.effectiveLocale)
        .environment(\.layoutDirection, store.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
        .alert(
            "Recording Couldn’t Be Saved",
            isPresented: Binding(
                get: { store.recordingFailureNotice != nil },
                set: { if !$0 { store.dismissRecordingFailureNotice() } }
            ),
            presenting: store.recordingFailureNotice
        ) { notice in
            if let recoveryURL = notice.recoveryURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([recoveryURL])
                    store.dismissRecordingFailureNotice()
                }
            }
            Button("Dismiss", role: .cancel) { store.dismissRecordingFailureNotice() }
        } message: { notice in
            if notice.kind == .partialRecordingPreserved {
                Text("ScreenContext preserved the partial recording. Show it in Finder to see whether it can be played.")
            } else {
                Text("No usable recording was produced. Check your recording settings and try again.")
            }
        }
        .onAppear {
            analytics.capture(.settingsOpened)
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var store: RecordingSessionStore

    var body: some View {
        Form {
            Picker("Language", selection: $store.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            Section {
                HStack {
                    Link(destination: AppLinks.privacyPolicy) { Text("Privacy Policy") }
                    Spacer()
                    Link(destination: AppLinks.support) { Text("Support") }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private extension AppLanguage {
    var title: LocalizedStringKey {
        switch self {
        case .system: "Follow System"
        case .english: "English"
        case .arabic: "العربية"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .russian: "Русский"
        case .turkish: "Türkçe"
        case .vietnamese: "Tiếng Việt"
        case .portugueseBrazil: "Português (Brasil)"
        case .chineseSimplified: "简体中文"
        case .chineseTraditional: "繁體中文"
        }
    }
}
