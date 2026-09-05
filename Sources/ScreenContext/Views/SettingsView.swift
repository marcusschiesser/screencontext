import ScreenContextCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: RecordingSessionStore
    @Bindable var analytics: AnalyticsConsentController
    @AppStorage(ScreenContextTemplatePreferenceKey.library)
    private var templateLibraryData = Data()

    var body: some View {
        TabView {
            GeneralSettingsView(store: store, analytics: analytics)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ScreenContextTemplateSettingsView(
                libraryData: $templateLibraryData,
                analytics: analytics.templates
            )
            .tabItem {
                Label("Recording context", systemImage: "text.quote")
            }
        }
        .frame(width: 580, height: 440)
        .padding()
        .environment(\.locale, store.effectiveLocale)
        .environment(\.layoutDirection, store.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
        .onAppear {
            analytics.capture(.settingsOpened)
        }
        .onDisappear {
            analytics.templates.flushPendingUpdate()
        }
    }
}

private struct GeneralSettingsView: View {
    @Bindable var store: RecordingSessionStore
    @Bindable var analytics: AnalyticsConsentController

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $store.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }

                transcriptionModelStatus
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable global shortcut ⇧⌘O", isOn: $store.globalShortcutEnabled)

                Text("The shortcut restores the floating controls from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Share usage analytics", isOn: Binding(
                    get: { analytics.isEnabled },
                    set: { analytics.setEnabled($0) }
                ))
                Text("Turning this off stops future collection but does not delete events already received.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: store.language) {
            await store.refreshTranscriptionModelAvailability()
        }
    }

    @ViewBuilder
    private var transcriptionModelStatus: some View {
        switch store.transcriptionModelAvailability {
        case .checking:
            ProgressView("Checking transcription model…")
        case .available:
            Label("The transcription model is ready.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .downloadable:
            HStack {
                Text("Transcription requires a downloaded speech model.")
                Spacer()
                Button("Install Model") {
                    Task { await store.installTranscriptionModel() }
                }
            }
        case .installing:
            ProgressView("Installing transcription model…")
        case .unsupported:
            Text("No downloadable transcription model is available for this language.")
                .foregroundStyle(.secondary)
        case .automaticInstallationUnavailable:
            Text("Automatic model installation requires macOS 26 or later.")
                .foregroundStyle(.secondary)
        }
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
