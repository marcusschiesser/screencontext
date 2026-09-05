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
    public static let transcriptCopied = AnalyticsEvent(name: "transcript_copied")

    public static func recordingStarted(
        sourceKind: CaptureSourceKind,
        systemAudioEnabled: Bool,
        microphoneEnabled: Bool,
        webcamEnabled: Bool,
        transcriptionLanguage: String
    ) -> AnalyticsEvent {
        AnalyticsEvent(name: "recording_started", properties: [
            "source_kind": .string(sourceKind.rawValue),
            "system_audio_enabled": .bool(systemAudioEnabled),
            "microphone_enabled": .bool(microphoneEnabled),
            "webcam_enabled": .bool(webcamEnabled),
            "transcription_language": .string(transcriptionLanguage),
        ])
    }

    public static func recordingCompleted(
        duration: TimeInterval,
        keyframeCount: Int,
        transcriptionRequested: Bool,
        transcriptionAvailable: Bool
    ) -> AnalyticsEvent {
        AnalyticsEvent(name: "recording_completed", properties: [
            "duration_seconds": .double(max(0, duration)),
            "keyframe_count": .integer(keyframeCount),
            "transcription_requested": .bool(transcriptionRequested),
            "transcription_available": .bool(transcriptionAvailable),
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
    public let templates: TemplateAnalyticsTracker

    @ObservationIgnored private let client: any AnalyticsClient
    @ObservationIgnored private let defaults: UserDefaults

    public init(
        client: any AnalyticsClient = NoOpAnalyticsClient(),
        defaults: UserDefaults = .standard,
        templateUpdateDelay: Duration = .seconds(2)
    ) {
        let enabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
        self.client = client
        self.defaults = defaults
        isEnabled = enabled
        templates = TemplateAnalyticsTracker(
            client: client,
            isEnabled: enabled,
            updateDelay: templateUpdateDelay
        )
        synchronizeClient()
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
        templates.setEnabled(enabled)
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
        templates.flushPendingUpdate()
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

@MainActor
public final class TemplateAnalyticsTracker {
    private struct Snapshot: Equatable {
        let id: String
        let name: String
        let body: String

        init(_ template: ScreenContextTemplate) {
            id = template.id
            name = template.name
            body = template.body
        }
    }

    private let client: any AnalyticsClient
    private let updateDelay: Duration
    private var isEnabled: Bool
    private var pendingUpdate: Snapshot?
    private var pendingUpdateTask: Task<Void, Never>?
    private var lastSentUpdates: [String: Snapshot] = [:]

    public init(
        client: any AnalyticsClient,
        isEnabled: Bool = true,
        updateDelay: Duration = .seconds(2)
    ) {
        self.client = client
        self.isEnabled = isEnabled
        self.updateDelay = updateDelay
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            cancelPendingUpdate()
        }
    }

    public func created(_ template: ScreenContextTemplate) {
        captureTemplate("template_created", template: template)
    }

    public func scheduleUpdated(_ template: ScreenContextTemplate) {
        guard isEnabled else { return }
        let snapshot = Snapshot(template)
        guard lastSentUpdates[template.id] != snapshot else {
            cancelPendingUpdate()
            return
        }
        pendingUpdateTask?.cancel()
        pendingUpdate = snapshot
        pendingUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.updateDelay)
            } catch {
                return
            }
            self.flushPendingUpdate()
        }
    }

    public func flushPendingUpdate() {
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        guard isEnabled, let snapshot = pendingUpdate else {
            pendingUpdate = nil
            return
        }
        pendingUpdate = nil
        guard lastSentUpdates[snapshot.id] != snapshot else { return }
        lastSentUpdates[snapshot.id] = snapshot
        captureTemplate("template_updated", snapshot: snapshot)
    }

    public func cancelPendingUpdate() {
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        pendingUpdate = nil
    }

    public func deleted(_ template: ScreenContextTemplate) {
        guard isEnabled else { return }
        if pendingUpdate?.id == template.id {
            cancelPendingUpdate()
        }
        captureTemplate("template_deleted", template: template)
        lastSentUpdates.removeValue(forKey: template.id)
    }

    public func selected(_ template: ScreenContextTemplate) {
        captureTemplateReference("template_selected", template: template)
    }

    public func used(_ template: ScreenContextTemplate) {
        captureTemplateReference("template_used", template: template)
    }

    public func restoredBundledTemplates(count: Int) {
        guard isEnabled, count > 0 else { return }
        client.capture(AnalyticsEvent(
            name: "bundled_templates_restored",
            properties: ["restored_count": .integer(count)]
        ))
    }

    private func captureTemplate(_ name: String, template: ScreenContextTemplate) {
        captureTemplate(name, snapshot: Snapshot(template))
    }

    private func captureTemplate(_ name: String, snapshot: Snapshot) {
        guard isEnabled else { return }
        client.capture(AnalyticsEvent(name: name, properties: [
            "template_id": .string(snapshot.id),
            "origin": .string(Self.origin(for: snapshot.id)),
            "template_name": .string(snapshot.name),
            "template_body": .string(snapshot.body),
            "body_length": .integer(snapshot.body.count),
            "placeholder_count": .integer(Self.placeholderCount(in: snapshot.body)),
        ]))
    }

    private func captureTemplateReference(_ name: String, template: ScreenContextTemplate) {
        guard isEnabled else { return }
        client.capture(AnalyticsEvent(name: name, properties: [
            "template_id": .string(template.id),
            "template_name": .string(template.name),
            "origin": .string(Self.origin(for: template.id)),
        ]))
    }

    private static func origin(for id: String) -> String {
        id.hasPrefix("builtin.") ? "bundled" : "user"
    }

    private static func placeholderCount(in body: String) -> Int {
        ScreenContextTemplateFormatter.placeholders.reduce(into: 0) { count, placeholder in
            count += body.components(separatedBy: placeholder).count - 1
        }
    }
}
