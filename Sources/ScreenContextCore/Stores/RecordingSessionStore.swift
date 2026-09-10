import Foundation
import Observation
import OSLog

@MainActor
@Observable
public final class RecordingSessionStore {
    public private(set) var phase: RecordingPhase = .idle {
        didSet {
            overlayStateChanged?()
            logger.info("Recording phase changed to \(self.phase.logName, privacy: .public)")
        }
    }
    public private(set) var captureSources: [CaptureSource] = []
    public private(set) var cameras: [CaptureDeviceOption] = []
    public private(set) var microphones: [CaptureDeviceOption] = []
    public private(set) var warningMessage: String? {
        didSet {
            guard warningMessage != oldValue else { return }
            overlayStateChanged?()
        }
    }
    public private(set) var recordingFailureNotice: RecordingFailureNotice?
    public private(set) var elapsedSeconds: TimeInterval = 0
    public private(set) var isInitialized = false
    public private(set) var screenCaptureAccessDenied = false
    public private(set) var latestRecordingResult: RecordingResult?
    public private(set) var recordingResults: [RecordingResult] = []
    public private(set) var selectedRecordingID: RecordingResult.ID?

    public var lastLocalRecordingURL: URL? { latestRecordingResult?.fileURL }
    public var selectedRecordingResult: RecordingResult? {
        guard let selectedRecordingID else { return latestRecordingResult }
        return recordingResults.first { $0.id == selectedRecordingID }
            ?? latestRecordingResult
    }

    public private(set) var selectedCaptureSourceID: CaptureSourceID? {
        didSet {
            if selectedCaptureSourceID != nil {
                requiresCaptureSourceSelection = false
            }
            persist()
            overlayStateChanged?()
        }
    }
    public var capturesSystemAudio: Bool { didSet { persist() } }
    public var capturesMicrophone: Bool { didSet { persist() } }
    public var microphoneDeviceID: String? { didSet { persist() } }
    public var capturesWebcam: Bool {
        didSet {
            persist()
            overlayStateChanged?()
        }
    }
    public var webcamDeviceID: String? {
        didSet {
            persist()
            overlayStateChanged?()
        }
    }
    public var blursWebcamBackground: Bool {
        didSet {
            persist()
            overlayStateChanged?()
        }
    }
    public var webcamLayout: WebcamLayout {
        didSet {
            persist(debounced: true)
            overlayStateChanged?()
        }
    }
    public var language: AppLanguage {
        didSet {
            persist()
        }
    }
    public private(set) var globalShortcut: GlobalShortcut
    public private(set) var shortcutRegistrationFailed = false
    @ObservationIgnored private let sourceCatalog: any CaptureSourceCatalog
    @ObservationIgnored private let captureAuthorization: any CaptureAuthorization
    @ObservationIgnored private let preferencesStore: any PreferencesStore
    @ObservationIgnored private let recordingHistoryStore: any RecordingHistoryStore
    @ObservationIgnored private let recordingPipeline: any RecordingPipeline
    @ObservationIgnored private let analyticsClient: any AnalyticsClient
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var historyPersistenceTask: Task<Void, Never>?
    @ObservationIgnored private var activeSessionID: UUID?
    @ObservationIgnored private var recordingStartedAt: Date?
    @ObservationIgnored private var pendingRecordingDuration: TimeInterval?
    @ObservationIgnored private var recordingFailureWasCaptured = false
    @ObservationIgnored private var pipelineIsRecording = false
    @ObservationIgnored private var isLoadingPreferences = true
    @ObservationIgnored private var requiresCaptureSourceSelection = false
    @ObservationIgnored private let logger = Logger(
        subsystem: "de.marcusschiesser.screencontext",
        category: "recording-session"
    )

    /// Called synchronously for accepted starts, before preparation changes app focus.
    @ObservationIgnored public var recordingWillStart: (() -> Void)?
    @ObservationIgnored public var recordingResultAvailable: ((RecordingResult) -> Void)?
    @ObservationIgnored public var recordingFailureNoticeAvailable: (() -> Void)?
    @ObservationIgnored public var shortcutPreferenceChanged: ((GlobalShortcut) -> Bool)?
    @ObservationIgnored public var overlayStateChanged: (() -> Void)?
    @ObservationIgnored public var requestScreenRecordingSettings: (() -> Void)?

    public convenience init(
        sourceCatalog: any CaptureSourceCatalog = ScreenCaptureKitSourceCatalog(),
        captureAuthorization: any CaptureAuthorization = SystemCaptureAuthorization(),
        preferencesStore: any PreferencesStore = UserDefaultsPreferencesStore(),
        recordingPipeline: any RecordingPipeline = ScreenCaptureRecordingPipeline(),
        analyticsClient: any AnalyticsClient = NoOpAnalyticsClient()
    ) {
        self.init(
            sourceCatalog: sourceCatalog,
            captureAuthorization: captureAuthorization,
            preferencesStore: preferencesStore,
            recordingHistoryStore: FileRecordingHistoryStore(),
            recordingPipeline: recordingPipeline,
            analyticsClient: analyticsClient
        )
    }

    init(
        sourceCatalog: any CaptureSourceCatalog,
        captureAuthorization: any CaptureAuthorization,
        preferencesStore: any PreferencesStore,
        recordingHistoryStore: any RecordingHistoryStore = VolatileRecordingHistoryStore(),
        recordingPipeline: any RecordingPipeline,
        analyticsClient: any AnalyticsClient = NoOpAnalyticsClient()
    ) {
        self.sourceCatalog = sourceCatalog
        self.captureAuthorization = captureAuthorization
        self.preferencesStore = preferencesStore
        self.recordingHistoryStore = recordingHistoryStore
        self.recordingPipeline = recordingPipeline
        self.analyticsClient = analyticsClient
        let defaults = PreferencesSnapshot.defaults
        selectedCaptureSourceID = defaults.selectedCaptureSourceID
        capturesSystemAudio = defaults.capturesSystemAudio
        capturesMicrophone = defaults.capturesMicrophone
        microphoneDeviceID = defaults.microphoneDeviceID
        capturesWebcam = defaults.capturesWebcam
        webcamDeviceID = defaults.webcamDeviceID
        webcamLayout = defaults.webcamLayout
        blursWebcamBackground = defaults.blursWebcamBackground
        language = defaults.language
        globalShortcut = defaults.globalShortcut
    }

    public var screens: [ScreenSource] {
        captureSources.compactMap {
            if case let .display(screen) = $0 { return screen }
            return nil
        }
    }

    public var windows: [WindowSource] {
        captureSources.compactMap {
            if case let .window(window) = $0 { return window }
            return nil
        }
    }

    public var selectedCaptureSource: CaptureSource? {
        guard let selectedCaptureSourceID else { return nil }
        return captureSources.first(where: { $0.id == selectedCaptureSourceID })
    }

    public var selectedScreen: ScreenSource? {
        guard case let .display(screen) = selectedCaptureSource else { return nil }
        return screen
    }

    public var configurationIsLocked: Bool { phase.locksConfiguration }

    public var recordingActionIsUnavailable: Bool {
        phase == .finalizing
            || (!phase.isRecording && phase != .preparing && selectedCaptureSource == nil)
    }

    public var hudMessage: String? {
        if let warningMessage { return warningMessage }
        if case let .failed(message) = phase { return message }
        return nil
    }

    public var showsWebcamPositioningOverlay: Bool {
        isInitialized && capturesWebcam && !phase.locksConfiguration
    }

    public var effectiveLocale: Locale {
        language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    public var usesRightToLeftLayout: Bool {
        effectiveLocale.language.languageCode?.identifier == "ar"
    }

    public func initialize() async {
        let snapshot = await preferencesStore.load()
        apply(snapshot)
        await restoreRecordingHistory()
        screenCaptureAccessDenied = !(await sourceCatalog.requestAccess())
        await refreshSources()
        await prepareEnabledCapturePermissions()
        isLoadingPreferences = false
        isInitialized = true
        persist()
        if !updateGlobalShortcut(globalShortcut), globalShortcut != .defaultShortcut {
            updateGlobalShortcut(.defaultShortcut)
        }
    }

    @discardableResult
    public func updateGlobalShortcut(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        guard shortcutPreferenceChanged?(shortcut) ?? true else {
            shortcutRegistrationFailed = true
            return false
        }
        shortcutRegistrationFailed = false
        globalShortcut = shortcut
        persist()
        return true
    }

    public func selectRecording(_ id: RecordingResult.ID) {
        guard selectedRecordingID != id,
              recordingResults.contains(where: { $0.id == id }) else { return }
        selectedRecordingID = id
        scheduleRecordingHistoryPersistence()
    }

    @discardableResult
    public func deleteSelectedRecording() async -> Bool {
        guard let deletionTarget = selectedRecordingResult else {
            return false
        }
        let deletionTargetID = deletionTarget.id

        await historyPersistenceTask?.value
        guard let index = recordingResults.firstIndex(where: { $0.id == deletionTargetID }) else {
            return false
        }
        let result = recordingResults[index]

        do {
            try await recordingHistoryStore.delete(recordingHistoryEntry(for: result))
        } catch {
            warningMessage = error.localizedDescription
            logger.error("Could not delete recording: \(error.localizedDescription, privacy: .public)")
            return false
        }

        recordingResults.remove(at: index)
        latestRecordingResult = recordingResults.last
        if recordingResults.isEmpty {
            selectedRecordingID = nil
        } else if index < recordingResults.count {
            selectedRecordingID = recordingResults[index].id
        } else {
            selectedRecordingID = recordingResults.last?.id
        }
        await persistRecordingHistory()
        return true
    }

    public func refreshSources() async {
        do {
            let previousSelection = selectedCaptureSource
            let available = try await sourceCatalog.sources()
            captureSources = available
            let restored: CaptureSource?
            if case let .window(previousWindow) = previousSelection {
                restored = available.first {
                    guard case let .window(candidate) = $0 else { return false }
                    return candidate.matchesRuntimeIdentity(of: previousWindow)
                }
                if restored == nil {
                    requiresCaptureSourceSelection = true
                }
            } else if requiresCaptureSourceSelection {
                restored = nil
            } else {
                restored = sourceCatalog.restoredSource(
                    from: available,
                    preferredID: selectedCaptureSourceID
                )
            }
            selectedCaptureSourceID = restored?.id
        } catch {
            warningMessage = error.localizedDescription
            if selectedCaptureSourceID?.kind == .window {
                requiresCaptureSourceSelection = true
            }
            captureSources = []
            selectedCaptureSourceID = nil
        }
        cameras = CaptureDeviceCatalog.cameras()
        microphones = CaptureDeviceCatalog.microphones()
        if webcamDeviceID == nil || !cameras.contains(where: { $0.id == webcamDeviceID }) {
            webcamDeviceID = cameras.first?.id
        }
        if microphoneDeviceID == nil || !microphones.contains(where: { $0.id == microphoneDeviceID }) {
            microphoneDeviceID = microphones.first?.id
        }
    }

    public func requestScreenCaptureAccess() {
        Task {
            let granted = await sourceCatalog.requestAccess()
            screenCaptureAccessDenied = !granted
            if granted {
                warningMessage = nil
                await refreshSources()
            } else {
                warningMessage = "Allow Screen Recording for ScreenContext, then reopen or refresh sources."
                requestScreenRecordingSettings?()
            }
        }
    }

    public func selectCaptureSource(_ sourceID: CaptureSourceID) {
        guard !configurationIsLocked,
              captureSources.contains(where: { $0.id == sourceID }) else {
            return
        }
        selectedCaptureSourceID = sourceID
        guard capturesSystemAudio else { return }
        Task { [weak self] in
            await self?.setSystemAudioEnabled(true)
        }
    }

    public func setSystemAudioEnabled(_ enabled: Bool) async {
        guard !configurationIsLocked else { return }
        guard enabled else {
            capturesSystemAudio = false
            return
        }
        guard let source = selectedCaptureSource,
              await captureAuthorization.requestSystemAudioAccess(for: source) else {
            capturesSystemAudio = false
            warningMessage = "System Audio permission is unavailable. Enable it in Privacy & Security before recording."
            return
        }
        capturesSystemAudio = true
        warningMessage = nil
    }

    public func setMicrophoneEnabled(_ enabled: Bool) async {
        guard !configurationIsLocked else { return }
        guard enabled else {
            capturesMicrophone = false
            return
        }
        guard await captureAuthorization.requestMicrophoneAccess() else {
            capturesMicrophone = false
            warningMessage = "Microphone permission is unavailable. Enable it in Privacy & Security before recording."
            return
        }
        capturesMicrophone = true
        warningMessage = nil
    }

    public func selectMicrophoneDevice(_ deviceID: String?) async {
        guard !configurationIsLocked else { return }
        if capturesMicrophone, !(await captureAuthorization.requestMicrophoneAccess()) {
            capturesMicrophone = false
            warningMessage = "Microphone permission is unavailable. Enable it in Privacy & Security before recording."
            return
        }
        microphoneDeviceID = deviceID
    }

    public func setWebcamEnabled(_ enabled: Bool) async {
        guard !configurationIsLocked else { return }
        guard enabled else {
            capturesWebcam = false
            return
        }
        guard await captureAuthorization.requestCameraAccess() else {
            capturesWebcam = false
            warningMessage = "Camera permission is unavailable. Enable it in Privacy & Security before recording."
            return
        }
        capturesWebcam = true
        warningMessage = nil
    }

    public func selectWebcamDevice(_ deviceID: String?) async {
        guard !configurationIsLocked else { return }
        if capturesWebcam, !(await captureAuthorization.requestCameraAccess()) {
            capturesWebcam = false
            warningMessage = "Camera permission is unavailable. Enable it in Privacy & Security before recording."
            return
        }
        webcamDeviceID = deviceID
    }

    public func startRecording() {
        guard !phase.locksConfiguration, startTask == nil, stopTask == nil else { return }
        warningMessage = nil
        recordingFailureWasCaptured = false
        guard let source = selectedCaptureSource else {
            captureRecordingFailure(stage: "start", recoveryCategory: "not_applicable")
            fail("No screen or window is available. Check Screen Recording permission and refresh sources.")
            return
        }

        recordingWillStart?()
        let sessionID = UUID()
        activeSessionID = sessionID
        recordingStartedAt = nil
        pendingRecordingDuration = nil
        elapsedSeconds = 0
        phase = .preparing
        logger.info("Recording start requested")
        startTask = Task { [weak self] in
            await self?.runStart(
                source: source,
                sessionID: sessionID
            )
        }
    }

    public func stopRecording() {
        guard stopTask == nil else { return }
        guard phase == .preparing || phase.isRecording else { return }

        logger.info("Recording stop requested")
        pendingRecordingDuration = recordingStartedAt.map { Date().timeIntervalSince($0) }
        let pendingStartTask = startTask
        let wasPreparing = phase == .preparing
        if wasPreparing {
            activeSessionID = nil
        }
        phase = .finalizing
        pendingStartTask?.cancel()
        startTask = nil
        timerTask?.cancel()
        timerTask = nil

        stopTask = Task { [weak self] in
            guard let self else { return }
            if wasPreparing {
                await recordingPipeline.cancel()
            }
            await pendingStartTask?.value
            guard pipelineIsRecording else {
                activeSessionID = nil
                stopTask = nil
                phase = .idle
                elapsedSeconds = 0
                return
            }
            await finishRecording()
        }
    }

    public func toggleRecording() {
        if phase == .preparing || phase.isRecording {
            stopRecording()
        } else if !phase.locksConfiguration {
            startRecording()
        }
    }

    public func cancelRecording() {
        activeSessionID = nil
        startTask?.cancel()
        startTask = nil
        stopTask?.cancel()
        stopTask = nil
        eventTask?.cancel()
        eventTask = nil
        timerTask?.cancel()
        timerTask = nil
        pipelineIsRecording = false
        recordingStartedAt = nil
        pendingRecordingDuration = nil
        Task { await recordingPipeline.cancel() }
        phase = .idle
        elapsedSeconds = 0
    }

    public func updateWebcamPosition(_ position: NormalizedWebcamPosition) {
        guard !configurationIsLocked else { return }
        webcamLayout.position = position
    }

    public func updateWebcamSize(_ size: WebcamSize, position: NormalizedWebcamPosition) {
        guard !configurationIsLocked else { return }
        var updatedLayout = webcamLayout
        updatedLayout.size = size
        updatedLayout.position = position
        webcamLayout = updatedLayout
    }

    public func clearWarning() {
        warningMessage = nil
    }

    public func dismissRecordingFailureNotice() {
        recordingFailureNotice = nil
    }

    public func handleFatalSystemEvent(_ message: String) {
        guard phase == .preparing || phase.isRecording else { return }
        logger.error("Recording failed: \(message, privacy: .public)")
        captureRecordingFailure(stage: "finalization", recoveryCategory: "system_event")
        warningMessage = message
        stopRecording()
    }

    public func handleOptionalInputLoss(_ name: String) {
        guard phase.locksConfiguration else { return }
        warningMessage = "\(name) disconnected. The recording is continuing without it."
    }

    private func runStart(
        source: CaptureSource,
        sessionID: UUID
    ) async {
        do {
            try Task.checkCancellation()
            let configuration = RecordingConfiguration(
                source: source,
                capturesSystemAudio: capturesSystemAudio,
                capturesMicrophone: capturesMicrophone,
                microphoneDeviceID: microphoneDeviceID,
                capturesWebcam: capturesWebcam,
                webcamDeviceID: webcamDeviceID,
                webcamLayout: webcamLayout,
                blursWebcamBackground: blursWebcamBackground
            )
            let events = try await recordingPipeline.start(configuration: configuration)
            pipelineIsRecording = true
            try Task.checkCancellation()
            guard activeSessionID == sessionID else { throw CancellationError() }

            startTask = nil
            let startedAt = Date()
            recordingStartedAt = startedAt
            phase = .recording(startedAt: startedAt)
            analyticsClient.capture(.recordingStarted(
                sourceKind: source.id.kind,
                systemAudioEnabled: capturesSystemAudio,
                microphoneEnabled: capturesMicrophone,
                webcamEnabled: capturesWebcam
            ))
            startElapsedTimer(sessionID: sessionID, startedAt: startedAt)
            eventTask = Task { [weak self] in
                for await event in events {
                    guard let self,
                          !Task.isCancelled,
                          activeSessionID == sessionID else { return }
                    handle(event)
                }
            }
        } catch is CancellationError {
            pipelineIsRecording = false
            recordingStartedAt = nil
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            await recordingPipeline.cancel()
            startTask = nil
            phase = .idle
        } catch {
            guard activeSessionID == sessionID else { return }
            activeSessionID = nil
            startTask = nil
            pipelineIsRecording = false
            recordingStartedAt = nil
            await recordingPipeline.cancel()
            captureRecordingFailure(stage: "start", recoveryCategory: "not_applicable")
            fail(error.localizedDescription)
        }
    }

    private func finishRecording() async {
        let artifacts: RecordingArtifacts
        do {
            artifacts = try await recordingPipeline.stop()
            await eventTask?.value
            eventTask = nil
        } catch is CancellationError {
            activeSessionID = nil
            pipelineIsRecording = false
            recordingStartedAt = nil
            eventTask?.cancel()
            eventTask = nil
            stopTask = nil
            phase = .idle
            return
        } catch {
            activeSessionID = nil
            pipelineIsRecording = false
            recordingStartedAt = nil
            eventTask?.cancel()
            eventTask = nil
            stopTask = nil
            let recoveryError = error as? RecordingRecoveryError
            let diagnosticDescription = recoveryError?.diagnosticDescription
                ?? String(reflecting: error)
            logger.error(
                "Recording finalization failed: \(diagnosticDescription, privacy: .public)"
            )
            recordingFailureNotice = RecordingFailureNotice(
                kind: recoveryError == nil
                    ? .recordingNotSaved
                    : .partialRecordingPreserved,
                recoveryURL: recoveryError?.recoveryURL
            )
            captureRecordingFailure(
                stage: "finalization",
                recoveryCategory: recoveryError == nil
                    ? "recording_not_saved"
                    : "partial_recording_preserved"
            )
            warningMessage = error.localizedDescription
            phase = .failed(message: error.localizedDescription)
            recordingFailureNoticeAvailable?()
            return
        }

        activeSessionID = nil
        pipelineIsRecording = false
        let result = RecordingResult(
            fileURL: artifacts.recordingURL
        )
        let duration = pendingRecordingDuration
            ?? recordingStartedAt.map { Date().timeIntervalSince($0) }
            ?? elapsedSeconds
        if !recordingFailureWasCaptured {
            analyticsClient.capture(.recordingCompleted(
                duration: duration
            ))
        }
        recordingStartedAt = nil
        pendingRecordingDuration = nil
        latestRecordingResult = result
        recordingResults.removeAll { $0.id == result.id }
        recordingResults.append(result)
        selectedRecordingID = result.id
        await persistRecordingHistory()
        elapsedSeconds = 0
        phase = .idle
        stopTask = nil
        recordingResultAvailable?(result)
        logger.info("Local recording finalized")
    }

    private func restoreRecordingHistory() async {
        do {
            let history = try await recordingHistoryStore.load()
            recordingResults = history.recordings.map { entry in
                RecordingResult(
                    id: entry.id,
                    fileURL: entry.fileURL,
                    recordedAt: entry.recordedAt
                )
            }
            latestRecordingResult = recordingResults.last
            let validIDs = Set(recordingResults.map(\.id))
            if let persistedID = history.selectedRecordingID,
               validIDs.contains(persistedID) {
                selectedRecordingID = persistedID
            } else {
                selectedRecordingID = latestRecordingResult?.id
            }
        } catch {
            logger.error("Could not load recording history: \(error.localizedDescription, privacy: .public)")
            recordingResults = []
            latestRecordingResult = nil
            selectedRecordingID = nil
        }
    }

    private func scheduleRecordingHistoryPersistence() {
        let previousTask = historyPersistenceTask
        let snapshot = recordingHistorySnapshot
        historyPersistenceTask = Task { [recordingHistoryStore, logger] in
            await previousTask?.value
            do {
                try await recordingHistoryStore.save(snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Could not save recording history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persistRecordingHistory() async {
        await historyPersistenceTask?.value
        historyPersistenceTask = nil
        do {
            try await recordingHistoryStore.save(recordingHistorySnapshot)
        } catch {
            logger.error("Could not save recording history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var recordingHistorySnapshot: RecordingHistorySnapshot {
        RecordingHistorySnapshot(
            recordings: recordingResults.map { recordingHistoryEntry(for: $0) },
            selectedRecordingID: selectedRecordingID
        )
    }

    private func recordingHistoryEntry(for result: RecordingResult) -> RecordingHistoryEntry {
        RecordingHistoryEntry(
            id: result.id,
            fileURL: result.fileURL,
            recordedAt: result.recordedAt
        )
    }

    private func prepareEnabledCapturePermissions() async {
        if capturesSystemAudio, selectedCaptureSource != nil {
            await setSystemAudioEnabled(true)
        }
        if capturesMicrophone { await setMicrophoneEnabled(true) }
        if capturesWebcam { await setWebcamEnabled(true) }
    }

    private func handle(_ event: RecordingPipelineEvent) {
        switch event {
        case let .optionalInputLost(name):
            warningMessage = "\(name) disconnected. The recording is continuing without it."
        case let .fatal(message):
            handleFatalSystemEvent(message)
        }
    }

    private func startElapsedTimer(sessionID: UUID, startedAt: Date) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, activeSessionID == sessionID else { return }
                elapsedSeconds = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func fail(_ message: String) {
        activeSessionID = nil
        elapsedSeconds = 0
        phase = .failed(message: message)
    }

    private func captureRecordingFailure(stage: String, recoveryCategory: String) {
        guard !recordingFailureWasCaptured else { return }
        recordingFailureWasCaptured = true
        analyticsClient.capture(.recordingFailed(
            stage: stage,
            recoveryCategory: recoveryCategory
        ))
    }

    private func apply(_ snapshot: PreferencesSnapshot) {
        let lastSourceKind = snapshot.lastCaptureSourceKind
            ?? snapshot.selectedCaptureSourceID?.kind
        requiresCaptureSourceSelection = lastSourceKind == .window
        selectedCaptureSourceID = requiresCaptureSourceSelection
            ? nil
            : snapshot.selectedCaptureSourceID
        capturesSystemAudio = snapshot.capturesSystemAudio
        capturesMicrophone = snapshot.capturesMicrophone
        microphoneDeviceID = snapshot.microphoneDeviceID
        capturesWebcam = snapshot.capturesWebcam
        webcamDeviceID = snapshot.webcamDeviceID
        webcamLayout = snapshot.webcamLayout
        blursWebcamBackground = snapshot.blursWebcamBackground
        language = snapshot.language
        globalShortcut = snapshot.globalShortcut
    }

    private func persist(debounced: Bool = false) {
        guard !isLoadingPreferences else { return }
        let snapshot = PreferencesSnapshot(
            selectedCaptureSourceID: selectedCaptureSourceID?.kind == .display
                ? selectedCaptureSourceID
                : nil,
            lastCaptureSourceKind: selectedCaptureSourceID?.kind
                ?? (requiresCaptureSourceSelection ? .window : nil),
            capturesSystemAudio: capturesSystemAudio,
            capturesMicrophone: capturesMicrophone,
            microphoneDeviceID: microphoneDeviceID,
            capturesWebcam: capturesWebcam,
            webcamDeviceID: webcamDeviceID,
            webcamLayout: webcamLayout,
            blursWebcamBackground: blursWebcamBackground,
            language: language,
            globalShortcut: globalShortcut
        )
        persistenceTask?.cancel()
        persistenceTask = Task { [preferencesStore] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }
            await preferencesStore.save(snapshot.sanitizedForPersistence)
        }
    }
}

private extension RecordingPhase {
    var logName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .recording: "recording"
        case .finalizing: "finalizing"
        case .failed: "failed"
        }
    }
}
