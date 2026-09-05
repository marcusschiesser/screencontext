import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case english = "en"
    case arabic = "ar"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case russian = "ru"
    case turkish = "tr"
    case vietnamese = "vi"
    case portugueseBrazil = "pt-BR"
    case chineseSimplified = "zh-CN"
    case chineseTraditional = "zh-TW"

    public var id: String { rawValue }
    public var localeIdentifier: String? { self == .system ? nil : rawValue }

    public func transcriptionLocale(
        using systemLocale: Locale = .autoupdatingCurrent
    ) -> TranscriptionLocale {
        guard let localeIdentifier else { return TranscriptionLocale(systemLocale) }
        return TranscriptionLocale(identifier: localeIdentifier)
    }
}

public struct PreferencesSnapshot: Codable, Equatable, Sendable {
    public var selectedCaptureSourceID: CaptureSourceID?
    public var lastCaptureSourceKind: CaptureSourceKind?
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool
    public var microphoneDeviceID: String?
    public var capturesWebcam: Bool
    public var webcamDeviceID: String?
    public var webcamLayout: WebcamLayout
    public var language: AppLanguage
    public var globalShortcutEnabled: Bool

    public init(
        selectedCaptureSourceID: CaptureSourceID? = nil,
        lastCaptureSourceKind: CaptureSourceKind? = nil,
        capturesSystemAudio: Bool = true,
        capturesMicrophone: Bool = true,
        microphoneDeviceID: String? = nil,
        capturesWebcam: Bool = false,
        webcamDeviceID: String? = nil,
        webcamLayout: WebcamLayout = .defaultLayout,
        language: AppLanguage = .system,
        globalShortcutEnabled: Bool = true
    ) {
        self.selectedCaptureSourceID = selectedCaptureSourceID
        self.lastCaptureSourceKind = lastCaptureSourceKind
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.microphoneDeviceID = microphoneDeviceID
        self.capturesWebcam = capturesWebcam
        self.webcamDeviceID = webcamDeviceID
        self.webcamLayout = webcamLayout
        self.language = language
        self.globalShortcutEnabled = globalShortcutEnabled
    }

    public static let defaults = PreferencesSnapshot()

    public var sanitizedForPersistence: PreferencesSnapshot {
        var snapshot = self
        if let selectedCaptureSourceID {
            snapshot.lastCaptureSourceKind = selectedCaptureSourceID.kind
        }
        if snapshot.lastCaptureSourceKind == .window {
            snapshot.selectedCaptureSourceID = nil
        }
        return snapshot
    }
}
