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
    public var globalShortcut: GlobalShortcut

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
        globalShortcut: GlobalShortcut = .defaultShortcut
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
        self.globalShortcut = globalShortcut
    }

    public static let defaults = PreferencesSnapshot()

    private enum CodingKeys: String, CodingKey {
        case selectedCaptureSourceID, lastCaptureSourceKind, capturesSystemAudio, capturesMicrophone
        case microphoneDeviceID, capturesWebcam, webcamDeviceID, webcamLayout, language, globalShortcut
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedCaptureSourceID = try values.decodeIfPresent(CaptureSourceID.self, forKey: .selectedCaptureSourceID)
        lastCaptureSourceKind = try values.decodeIfPresent(CaptureSourceKind.self, forKey: .lastCaptureSourceKind)
        capturesSystemAudio = try values.decodeIfPresent(Bool.self, forKey: .capturesSystemAudio) ?? true
        capturesMicrophone = try values.decodeIfPresent(Bool.self, forKey: .capturesMicrophone) ?? true
        microphoneDeviceID = try values.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        capturesWebcam = try values.decodeIfPresent(Bool.self, forKey: .capturesWebcam) ?? false
        webcamDeviceID = try values.decodeIfPresent(String.self, forKey: .webcamDeviceID)
        webcamLayout = try values.decodeIfPresent(WebcamLayout.self, forKey: .webcamLayout) ?? .defaultLayout
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        // Older preferences only stored an enable switch. Always restore an active shortcut.
        let shortcut = try? values.decode(GlobalShortcut.self, forKey: .globalShortcut)
        if let shortcut, shortcut.isValid {
            globalShortcut = shortcut
        } else {
            globalShortcut = .defaultShortcut
        }
    }

    public var sanitizedForPersistence: PreferencesSnapshot {
        var snapshot = self
        if !snapshot.globalShortcut.isValid {
            snapshot.globalShortcut = .defaultShortcut
        }
        if let selectedCaptureSourceID {
            snapshot.lastCaptureSourceKind = selectedCaptureSourceID.kind
        }
        if snapshot.lastCaptureSourceKind == .window {
            snapshot.selectedCaptureSourceID = nil
        }
        return snapshot
    }
}
