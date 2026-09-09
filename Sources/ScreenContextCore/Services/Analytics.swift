import Foundation
import Observation

public enum AnalyticsProperty: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case double(Double)
}

public struct AnalyticsEvent: Equatable, Sendable {
    public let name: String
    public let properties: [String: AnalyticsProperty]

    public init(name: String, properties: [String: AnalyticsProperty] = [:]) {
        self.name = name
        self.properties = properties
    }

    public static let appLaunched = AnalyticsEvent(name: "app_launched")
    public static let settingsOpened = AnalyticsEvent(name: "settings_opened")
    public static let analyticsEnabled = AnalyticsEvent(name: "analytics_enabled")
    public static let videoCopied = AnalyticsEvent(name: "video_copied")
    public static let contextCopied = AnalyticsEvent(name: "context_copied")

    public static func recordingStarted(
        sourceKind: CaptureSourceKind,
        systemAudioEnabled: Bool,
        microphoneEnabled: Bool,
        webcamEnabled: Bool
    ) -> AnalyticsEvent {
        AnalyticsEvent(name: "recording_started", properties: [
            "source_kind": .string(sourceKind.rawValue),
            "system_audio_enabled": .bool(systemAudioEnabled),
            "microphone_enabled": .bool(microphoneEnabled),
            "webcam_enabled": .bool(webcamEnabled),
        ])
    }

    public static func recordingCompleted(
        duration: TimeInterval
    ) -> AnalyticsEvent {
        AnalyticsEvent(name: "recording_completed", properties: [
            "duration_seconds": .double(max(0, duration)),
        ])
    }

    public static func recordingFailed(
        stage: String,
        recoveryCategory: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(name: "recording_failed", properties: [
            "stage": .string(stage),
            "recovery_category": .string(recoveryCategory),
        ])
    }
}

@MainActor
public protocol AnalyticsClient: AnyObject {
    func capture(_ event: AnalyticsEvent)
    func optIn()
    func optOut()
    func flush()
}

@MainActor
public final class NoOpAnalyticsClient: AnalyticsClient {
    public init() {}
    public func capture(_ event: AnalyticsEvent) {}
    public func optIn() {}
    public func optOut() {}
    public func flush() {}
}

public enum AnalyticsToken {
    public static func normalized(_ value: String?) -> String? {
        guard let token = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              !token.contains("$(") else {
            return nil
        }
        return token
    }
}

@MainActor
@Observable
public final class AnalyticsConsentController {
    public static let preferenceKey = "ContextCast.AnalyticsEnabled"

    public private(set) var isEnabled: Bool

    @ObservationIgnored private let client: any AnalyticsClient
    @ObservationIgnored private let defaults: UserDefaults

    public init(
        client: any AnalyticsClient = NoOpAnalyticsClient(),
        defaults: UserDefaults = .standard
    ) {
        let enabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
        self.client = client
        self.defaults = defaults
        isEnabled = enabled
        synchronizeClient()
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
        if enabled {
            client.optIn()
            client.capture(.analyticsEnabled)
        } else {
            client.optOut()
        }
    }

    public func capture(_ event: AnalyticsEvent) {
        guard isEnabled else { return }
        client.capture(event)
    }

    public func flush() {
        client.flush()
    }

    private func synchronizeClient() {
        if isEnabled {
            client.optIn()
        } else {
            client.optOut()
        }
    }
}
