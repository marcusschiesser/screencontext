@preconcurrency import AVFoundation
import Carbon
@preconcurrency import CoreMedia
import CoreVideo
import Foundation
import HaishinKit
@preconcurrency import ScreenCaptureKit
import XCTest
@testable import ScreenContextCore

final class PersistenceAndStoreTests: XCTestCase {
    func testFileRecordingHistoryRoundTripPreservesRecordingsAndSelection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("screencontext-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstDirectory = root.appendingPathComponent("ScreenContext 2026-09-01 10-00-00")
        let secondDirectory = root.appendingPathComponent("ScreenContext 2026-09-01 11-00-00")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let firstVideo = firstDirectory.appendingPathComponent("recording.mp4")
        let secondVideo = secondDirectory.appendingPathComponent("recording.mp4")
        try Data([1]).write(to: firstVideo)
        try Data([2]).write(to: secondVideo)
        let firstID = UUID()
        let secondID = UUID()
        let firstRecordedAt = Date(timeIntervalSince1970: 1_788_255_600)
        let secondRecordedAt = Date(timeIntervalSince1970: 1_788_259_200)
        let expected = RecordingHistorySnapshot(
            recordings: [
                RecordingHistoryEntry(
                    id: firstID,
                    fileURL: firstVideo,
                    recordedAt: firstRecordedAt
                ),
                RecordingHistoryEntry(
                    id: secondID,
                    fileURL: secondVideo,
                    recordedAt: secondRecordedAt
                ),
            ],
            selectedRecordingID: firstID
        )
        let store = FileRecordingHistoryStore(recordingsDirectory: root)

        try await store.save(expected)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, expected)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("recording-history.json").path
        ))
    }

    func testFileRecordingHistoryDiscoversExistingRecording() async throws {
        for suffix in ["", "-2"] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("screencontext-discovery-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let recordingDirectory = root.appendingPathComponent("ScreenContext 2026-09-01 12-00-00\(suffix)")
            try FileManager.default.createDirectory(
                at: recordingDirectory,
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: recordingDirectory.appendingPathComponent("recording.mp4"))

            let store = FileRecordingHistoryStore(recordingsDirectory: root)
            let loaded = try await store.load()

            XCTAssertEqual(loaded.recordings.count, 1)
            XCTAssertEqual(loaded.selectedRecordingID, loaded.recordings.first?.id)
            let recordedAt = try XCTUnwrap(loaded.recordings.first?.recordedAt)
            let components = Calendar(identifier: .gregorian).dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: recordedAt
            )
            XCTAssertEqual(components.year, 2026)
            XCTAssertEqual(components.month, 9)
            XCTAssertEqual(components.day, 1)
            XCTAssertEqual(components.hour, 12)
            XCTAssertEqual(components.minute, 0)
            XCTAssertEqual(components.second, 0)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("recording-history.json").path
            ))
        }
    }

    func testFileRecordingHistoryDeleteRemovesRecordingDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("screencontext-delete-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("ScreenContext 2026-09-01 13-00-00")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let videoURL = directory.appendingPathComponent("recording.mp4")
        try Data([1]).write(to: videoURL)
        let entry = RecordingHistoryEntry(
            id: UUID(),
            fileURL: videoURL,
            recordedAt: Date(timeIntervalSince1970: 1_788_266_400)
        )
        let store = FileRecordingHistoryStore(recordingsDirectory: root)
        try await store.save(RecordingHistorySnapshot(
            recordings: [entry],
            selectedRecordingID: entry.id
        ))

        try await store.delete(entry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let loadedSnapshot = try await store.load()
        XCTAssertTrue(loadedSnapshot.recordings.isEmpty)
    }

    func testPreferencesRoundTripContainsOnlyRecordingSettings() throws {
        let snapshot = PreferencesSnapshot(
            selectedCaptureSourceID: .display(42),
            capturesSystemAudio: true,
            capturesMicrophone: false,
            microphoneDeviceID: "mic",
            capturesWebcam: true,
            webcamDeviceID: "camera",
            webcamLayout: WebcamLayout(mask: .circle, size: .large),
            language: .english,
            globalShortcut: GlobalShortcut(
                keyCode: UInt16(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey), keyDisplayName: "R"
            )
        )
        let data = try JSONEncoder().encode(snapshot)
        let source = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("rtmp"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("streamKey"))
        XCTAssertEqual(try JSONDecoder().decode(PreferencesSnapshot.self, from: data), snapshot)
    }

    func testLegacyShortcutToggleMigratesWithoutLosingOtherPreferences() throws {
        for wasEnabled in [false, true] {
            let original = PreferencesSnapshot(capturesMicrophone: false, language: .german)
            let data = try JSONEncoder().encode(original)
            var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            legacy.removeValue(forKey: "globalShortcut")
            legacy["globalShortcutEnabled"] = wasEnabled
            let restored = try JSONDecoder().decode(
                PreferencesSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)
            )
            XCTAssertEqual(restored.globalShortcut, .defaultShortcut)
            XCTAssertEqual(restored.language, .german)
            XCTAssertFalse(restored.capturesMicrophone)
            let saved = try JSONEncoder().encode(restored)
            XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("globalShortcutEnabled"))
        }
    }

    func testInvalidSavedShortcutFallsBackToDefault() throws {
        let snapshot = PreferencesSnapshot(globalShortcut: GlobalShortcut(
            keyCode: UInt16(kVK_ANSI_R), modifiers: 0, keyDisplayName: "R"
        ))
        let restored = try JSONDecoder().decode(
            PreferencesSnapshot.self, from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(restored.globalShortcut, .defaultShortcut)
    }

    @MainActor
    func testUnavailableShortcutPreservesPreviousPreference() async {
        let store = makeStore(pipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL()))
        await store.initialize()
        let shortcut = GlobalShortcut(
            keyCode: UInt16(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey), keyDisplayName: "R"
        )
        store.shortcutPreferenceChanged = { _ in false }
        XCTAssertFalse(store.updateGlobalShortcut(shortcut))
        XCTAssertEqual(store.globalShortcut, .defaultShortcut)
        XCTAssertTrue(store.shortcutRegistrationFailed)

        store.shortcutPreferenceChanged = { _ in true }
        XCTAssertTrue(store.updateGlobalShortcut(shortcut))
        XCTAssertEqual(store.globalShortcut, shortcut)
        XCTAssertFalse(store.shortcutRegistrationFailed)
    }

    @MainActor
    func testCustomShortcutIsSavedAndRegisteredAfterRelaunch() async {
        let preferences = InMemoryPreferences(snapshot: PreferencesSnapshot(
            capturesSystemAudio: false, capturesMicrophone: false
        ))
        func newStore() -> RecordingSessionStore {
            RecordingSessionStore(
                sourceCatalog: TestSourceCatalog(screens: [makeScreen(id: 1, isPrimary: true)]),
                captureAuthorization: PermittedCaptureAuthorization(),
                preferencesStore: preferences,
                recordingPipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL())
            )
        }
        let store = newStore()
        await store.initialize()
        let shortcut = GlobalShortcut(
            keyCode: UInt16(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey), keyDisplayName: "R"
        )
        XCTAssertTrue(store.updateGlobalShortcut(shortcut))
        for _ in 0..<100 {
            if await preferences.load().globalShortcut == shortcut { break }
            await Task.yield()
        }
        let saved = await preferences.load()
        XCTAssertEqual(saved.globalShortcut, shortcut)
        let relaunched = newStore()
        var registered: GlobalShortcut?
        relaunched.shortcutPreferenceChanged = { registered = $0; return true }
        await relaunched.initialize()
        XCTAssertEqual(relaunched.globalShortcut, shortcut)
        XCTAssertEqual(registered, shortcut)
    }

    func testWindowIdentifierIsRemovedBeforePersistence() {
        let sanitized = PreferencesSnapshot(
            selectedCaptureSourceID: .window(42)
        ).sanitizedForPersistence

        XCTAssertNil(sanitized.selectedCaptureSourceID)
        XCTAssertEqual(sanitized.lastCaptureSourceKind, .window)
    }

    @MainActor
    func testPersistedWindowRequiresExplicitSelectionBeforeRecording() async {
        let pipeline = TestRecordingPipeline(outputURL: temporaryRecordingURL())
        let window = makeWindow(id: 42, title: "Roadmap", applicationName: "Notes")
        let preferences = InMemoryPreferences(snapshot: PreferencesSnapshot(
            selectedCaptureSourceID: .window(42),
            capturesSystemAudio: false,
            capturesMicrophone: false
        ))
        let store = RecordingSessionStore(
            sourceCatalog: TestSourceCatalog(
                screens: [makeScreen(id: 1, isPrimary: true)],
                windows: [window]
            ),
            captureAuthorization: PermittedCaptureAuthorization(),
            preferencesStore: preferences,
            recordingPipeline: pipeline
        )

        await store.initialize()
        XCTAssertNil(store.selectedCaptureSource)
        XCTAssertTrue(store.recordingActionIsUnavailable)

        store.selectCaptureSource(.window(42))
        XCTAssertEqual(store.selectedCaptureSource?.id, .window(42))
        XCTAssertFalse(store.recordingActionIsUnavailable)
        try? await Task.sleep(for: .milliseconds(20))
        let persisted = await preferences.load()
        XCTAssertNil(persisted.selectedCaptureSourceID)
        XCTAssertEqual(persisted.lastCaptureSourceKind, .window)
        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)
        let configuration = await pipeline.configurationValue()
        XCTAssertEqual(configuration?.source.id, .window(42))
        store.cancelRecording()
    }

    func testWebcamSizeDecodesLegacyIntegerRepresentation() throws {
        let data = Data(#"{"mask":"rounded","size":32,"position":{"x":0.5,"y":0.5}}"#.utf8)
        let layout = try JSONDecoder().decode(WebcamLayout.self, from: data)
        XCTAssertEqual(layout.size.percentage, 32)
    }

    @MainActor
    func testRecordingDestinationIsCapturedOnceBeforePreparation() async {
        let pipeline = TestRecordingPipeline(outputURL: temporaryRecordingURL())
        let store = makeStore(pipeline: pipeline)
        await store.initialize()
        var phasesAtCapture: [RecordingPhase] = []
        store.recordingWillStart = { phasesAtCapture.append(store.phase) }

        store.startRecording()
        XCTAssertEqual(phasesAtCapture, [.idle])
        // Repeated starts during preparation/recording must not replace the destination.
        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)
        store.startRecording()
        XCTAssertEqual(phasesAtCapture, [.idle])

        store.cancelRecording()
    }

    @MainActor
    func testCompletedRecordingIsSavedLocally() async throws {
        let fileURL = temporaryRecordingURL()
        try Data(repeating: 5, count: 32).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pipeline = TestRecordingPipeline(outputURL: fileURL)
        let store = makeStore(pipeline: pipeline)
        await store.initialize()
        var presentedResult: RecordingResult?
        store.recordingResultAvailable = { presentedResult = $0 }

        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)
        store.stopRecording()
        let didFinish = await waitUntilOnMainActor {
            store.phase == .idle && presentedResult != nil
        }
        XCTAssertTrue(didFinish)
        XCTAssertEqual(store.lastLocalRecordingURL, fileURL)
        XCTAssertEqual(presentedResult?.fileURL, fileURL)
        let startCount = await pipeline.startCountValue()
        XCTAssertEqual(startCount, 1)
    }

    @MainActor
    func testFailedFinalizationSurfacesPreservedRecordingNotice() async {
        let recoveryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screencontext-recovery-\(UUID().uuidString)", isDirectory: true)
        let pipeline = RecoverableFailureRecordingPipeline(recoveryURL: recoveryURL)
        let store = makeStore(pipeline: pipeline)
        await store.initialize()
        var noticeWasPresented = false
        store.recordingFailureNoticeAvailable = { noticeWasPresented = true }

        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)
        store.stopRecording()
        let didFail = await waitUntilOnMainActor {
            if case .failed = store.phase { return true }
            return false
        }

        XCTAssertTrue(didFail)
        XCTAssertTrue(noticeWasPresented)
        XCTAssertEqual(store.recordingFailureNotice?.kind, .partialRecordingPreserved)
        XCTAssertEqual(store.recordingFailureNotice?.recoveryURL, recoveryURL)

        store.dismissRecordingFailureNotice()
        XCTAssertNil(store.recordingFailureNotice)
    }

    @MainActor
    func testRecordingAnalyticsEmitsSuccessfulStartAndCompletionExactlyOnce() async {
        let analytics = StoreAnalyticsSpy()
        let pipeline = TestRecordingPipeline(
            outputURL: temporaryRecordingURL()
        )
        let store = makeStore(pipeline: pipeline, analyticsClient: analytics)
        await store.initialize()

        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)
        store.stopRecording()
        let didComplete = await waitUntilOnMainActor { store.phase == .idle }
        XCTAssertTrue(didComplete)

        XCTAssertEqual(analytics.events.map(\.name), ["recording_started", "recording_completed"])
        XCTAssertEqual(analytics.events[0].properties["source_kind"], .string("display"))
        XCTAssertEqual(analytics.events[0].properties["microphone_enabled"], .bool(false))
        XCTAssertEqual(store.phase, .idle)
    }

    @MainActor
    func testRecordingAnalyticsEmitsStartFailureExactlyOnce() async {
        let analytics = StoreAnalyticsSpy()
        let store = makeStore(
            pipeline: FailingStartRecordingPipeline(),
            analyticsClient: analytics
        )
        await store.initialize()

        store.startRecording()
        let didFail = await waitUntilOnMainActor {
            if case .failed = store.phase { return true }
            return false
        }
        XCTAssertTrue(didFail)

        let failures = analytics.events.filter { $0.name == "recording_failed" }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.properties["stage"], .string("start"))
        XCTAssertEqual(failures.first?.properties["recovery_category"], .string("not_applicable"))
    }

    @MainActor
    func testRecordingAnalyticsEmitsMissingSourceFailureExactlyOnce() async {
        let analytics = StoreAnalyticsSpy()
        let store = RecordingSessionStore(
            sourceCatalog: TestSourceCatalog(screens: []),
            captureAuthorization: PermittedCaptureAuthorization(),
            preferencesStore: InMemoryPreferences(snapshot: .defaults),
            recordingPipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL()),
            analyticsClient: analytics
        )
        await store.initialize()

        store.startRecording()

        let failures = analytics.events.filter { $0.name == "recording_failed" }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.properties["stage"], .string("start"))
        XCTAssertEqual(
            Set(failures.first?.properties.keys.map { $0 } ?? []),
            ["stage", "recovery_category"]
        )
        if case .failed = store.phase {
            // Expected state is unchanged by analytics.
        } else {
            XCTFail("Expected missing source to keep the existing failed transition")
        }
    }

    @MainActor
    func testRecordingAnalyticsEmitsEachFinalizationRecoveryCategoryExactlyOnce() async {
        for (pipeline, expectedCategory) in [
            (RecoverableFailureRecordingPipeline(recoveryURL: temporaryRecordingURL()) as any RecordingPipeline, "partial_recording_preserved"),
            (NonRecoverableFailureRecordingPipeline() as any RecordingPipeline, "recording_not_saved"),
        ] {
            let analytics = StoreAnalyticsSpy()
            let store = makeStore(pipeline: pipeline, analyticsClient: analytics)
            await store.initialize()

            store.startRecording()
            let didStart = await waitUntilOnMainActor { store.phase.isRecording }
            XCTAssertTrue(didStart)
            store.stopRecording()
            let didFail = await waitUntilOnMainActor {
                if case .failed = store.phase { return true }
                return false
            }
            XCTAssertTrue(didFail)

            let failures = analytics.events.filter { $0.name == "recording_failed" }
            XCTAssertEqual(failures.count, 1)
            XCTAssertEqual(failures.first?.properties["stage"], .string("finalization"))
            XCTAssertEqual(failures.first?.properties["recovery_category"], .string(expectedCategory))
        }
    }

    @MainActor
    func testFatalSystemEventAndFailedStopEmitOneFailureWithoutChangingFailedState() async {
        let analytics = StoreAnalyticsSpy()
        let store = makeStore(
            pipeline: RecoverableFailureRecordingPipeline(recoveryURL: temporaryRecordingURL()),
            analyticsClient: analytics
        )
        await store.initialize()
        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)

        store.handleFatalSystemEvent("Synthetic sleep")
        let didFail = await waitUntilOnMainActor {
            if case .failed = store.phase { return true }
            return false
        }
        XCTAssertTrue(didFail)

        let failures = analytics.events.filter { $0.name == "recording_failed" }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.properties["recovery_category"], .string("system_event"))
    }

    @MainActor
    func testFatalSystemEventWithPreservedRecordingDoesNotEmitCompletion() async {
        let analytics = StoreAnalyticsSpy()
        let store = makeStore(
            pipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL()),
            analyticsClient: analytics
        )
        await store.initialize()
        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)

        store.handleFatalSystemEvent("Synthetic sleep")
        let didFinalize = await waitUntilOnMainActor { store.phase == .idle }
        XCTAssertTrue(didFinalize)

        XCTAssertEqual(
            analytics.events.map(\.name),
            ["recording_started", "recording_failed"]
        )
        XCTAssertEqual(
            analytics.events.last?.properties["recovery_category"],
            .string("system_event")
        )
        XCTAssertNotNil(store.latestRecordingResult)
    }

    @MainActor
    func testRecordingHistoryRestoresAndPersistsSidebarSelection() async throws {
        let firstURL = temporaryRecordingURL()
        let secondURL = temporaryRecordingURL()
        let firstID = UUID()
        let secondID = UUID()
        let historyStore = TestRecordingHistoryStore(snapshot: RecordingHistorySnapshot(
            recordings: [
                RecordingHistoryEntry(
                    id: firstID,
                    fileURL: firstURL,
                    recordedAt: Date(timeIntervalSince1970: 1)
                ),
                RecordingHistoryEntry(
                    id: secondID,
                    fileURL: secondURL,
                    recordedAt: Date(timeIntervalSince1970: 2)
                ),
            ],
            selectedRecordingID: secondID
        ))
        let store = makeStore(
            pipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL()),
            recordingHistoryStore: historyStore
        )

        await store.initialize()
        XCTAssertEqual(store.latestRecordingResult?.id, secondID)
        XCTAssertEqual(store.selectedRecordingResult?.id, secondID)

        store.selectRecording(firstID)
        XCTAssertEqual(store.selectedRecordingResult?.id, firstID)
        let persistedPrevious = await waitUntil {
            await historyStore.snapshotValue().selectedRecordingID == firstID
        }
        XCTAssertTrue(persistedPrevious)

        store.selectRecording(secondID)
        XCTAssertEqual(store.selectedRecordingResult?.id, secondID)
        let persistedNext = await waitUntil {
            await historyStore.snapshotValue().selectedRecordingID == secondID
        }
        XCTAssertTrue(persistedNext)
    }

    @MainActor
    func testDeletingSelectedRecordingRemovesArtifactsAndSelectsAdjacentRecording() async {
        let first = recordingHistoryEntry(id: UUID(), timestamp: 1)
        let selected = recordingHistoryEntry(id: UUID(), timestamp: 2)
        let next = recordingHistoryEntry(id: UUID(), timestamp: 3)
        let historyStore = TestRecordingHistoryStore(snapshot: RecordingHistorySnapshot(
            recordings: [first, selected, next],
            selectedRecordingID: selected.id
        ))
        let store = makeStore(
            pipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL()),
            recordingHistoryStore: historyStore
        )
        await store.initialize()

        let didDelete = await store.deleteSelectedRecording()
        let deletedIDs = await historyStore.deletedIDsValue()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(deletedIDs, [selected.id])
        XCTAssertEqual(store.recordingResults.map(\.id), [first.id, next.id])
        XCTAssertEqual(store.selectedRecordingID, next.id)
        XCTAssertEqual(store.latestRecordingResult?.id, next.id)
        let persisted = await historyStore.snapshotValue()
        XCTAssertEqual(persisted.recordings.map(\.id), [first.id, next.id])
        XCTAssertEqual(persisted.selectedRecordingID, next.id)
    }

    @MainActor
    func testDeletingOnlyRecordingClearsHistoryAndSelection() async {
        let only = recordingHistoryEntry(id: UUID(), timestamp: 1)
        let historyStore = TestRecordingHistoryStore(snapshot: RecordingHistorySnapshot(
            recordings: [only],
            selectedRecordingID: only.id
        ))
        let store = makeStore(
            pipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL()),
            recordingHistoryStore: historyStore
        )
        await store.initialize()

        let didDelete = await store.deleteSelectedRecording()
        XCTAssertTrue(didDelete)
        XCTAssertTrue(store.recordingResults.isEmpty)
        XCTAssertNil(store.selectedRecordingID)
        XCTAssertNil(store.latestRecordingResult)
    }

    @MainActor
    func testDeletionKeepsConfirmedTargetWhenSelectionChangesDuringPersistence() async {
        let first = recordingHistoryEntry(id: UUID(), timestamp: 1)
        let second = recordingHistoryEntry(id: UUID(), timestamp: 2)
        let historyStore = SuspendingRecordingHistoryStore(snapshot: RecordingHistorySnapshot(
            recordings: [first, second],
            selectedRecordingID: second.id
        ))
        let store = makeStore(
            pipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL()),
            recordingHistoryStore: historyStore
        )
        await store.initialize()
        await historyStore.suspendNextSave()
        store.selectRecording(first.id)

        let changeSelection = Task { @MainActor in
            await historyStore.waitUntilSaveStarts()
            store.selectRecording(second.id)
            await historyStore.resumeSave()
        }
        let didDelete = await store.deleteSelectedRecording()
        await changeSelection.value
        let deletedIDs = await historyStore.deletedIDsValue()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(deletedIDs, [first.id])
        XCTAssertEqual(store.recordingResults.map(\.id), [second.id])
        XCTAssertEqual(store.selectedRecordingID, second.id)
    }

    @MainActor
    func testCompletedRecordingIsAppendedToPersistedHistory() async throws {
        let fileURL = temporaryRecordingURL()
        let historyStore = TestRecordingHistoryStore()
        let pipeline = TestRecordingPipeline(
            outputURL: fileURL
        )
        let store = makeStore(pipeline: pipeline, recordingHistoryStore: historyStore)
        await store.initialize()

        store.startRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)
        store.stopRecording()
        let didPersist = await waitUntil {
            await historyStore.snapshotValue().recordings.count == 1
        }

        XCTAssertTrue(didPersist)
        let persisted = await historyStore.snapshotValue()
        XCTAssertEqual(persisted.recordings.first?.fileURL, fileURL)
        XCTAssertEqual(persisted.selectedRecordingID, persisted.recordings.first?.id)
    }

    @MainActor
    func testPresentedRecordingResultDoesNotChangeWhenNextRecordingStarts() async throws {
        let fileURL = temporaryRecordingURL()
        try Data(repeating: 5, count: 32).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let pipeline = TestRecordingPipeline(outputURL: fileURL)
        let store = makeStore(pipeline: pipeline)
        await store.initialize()
        var presentedResult: RecordingResult?
        store.recordingResultAvailable = { presentedResult = $0 }

        store.startRecording()
        let firstDidStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(firstDidStart)
        store.stopRecording()
        let firstDidFinish = await waitUntilOnMainActor { presentedResult != nil }
        XCTAssertTrue(firstDidFinish)
        let firstResult = try XCTUnwrap(presentedResult)
        let firstContext = firstResult.context

        store.startRecording()
        let secondDidStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(secondDidStart)
        XCTAssertEqual(firstResult.fileURL, fileURL)
        XCTAssertEqual(firstResult.context, firstContext)
        store.cancelRecording()
    }

    @MainActor
    func testRecordingToggleStopsAndPresentsLatestResultOnce() async {
        let pipeline = TestRecordingPipeline(outputURL: temporaryRecordingURL())
        let store = makeStore(pipeline: pipeline)
        await store.initialize()
        var presentedResults: [RecordingResult] = []
        store.recordingResultAvailable = { presentedResults.append($0) }

        store.toggleRecording()
        let didStart = await waitUntilOnMainActor { store.phase.isRecording }
        XCTAssertTrue(didStart)
        XCTAssertTrue(store.configurationIsLocked)
        store.toggleRecording()
        XCTAssertEqual(store.phase, .finalizing)
        store.toggleRecording() // Repeated input during finalization must not start a new session.
        let didFinish = await waitUntilOnMainActor { store.phase == .idle }
        XCTAssertTrue(didFinish)
        XCTAssertEqual(presentedResults.count, 1)
        XCTAssertEqual(presentedResults.first?.id, store.latestRecordingResult?.id)
        XCTAssertEqual(store.selectedRecordingID, store.latestRecordingResult?.id)
        XCTAssertFalse(store.configurationIsLocked)
    }

    @MainActor
    func testRecordingToggleDuringPreparationCancelsRecording() async {
        let pipeline = BlockingStartPipeline(outputURL: temporaryRecordingURL())
        let store = makeStore(pipeline: pipeline)
        await store.initialize()

        store.toggleRecording()
        let didPrepare = await waitUntilOnMainActor { store.phase == .preparing }
        XCTAssertTrue(didPrepare)
        store.toggleRecording()
        await pipeline.releaseStart()
        let didCancel = await waitUntilOnMainActor { store.phase == .idle }
        XCTAssertTrue(didCancel)
        let cancelCount = await pipeline.cancelCountValue()
        XCTAssertEqual(cancelCount, 1)
    }

    @MainActor
    func testEnabledCaptureInputsRequestPermissionDuringInitialization() async {
        let authorization = RecordingCaptureAuthorization()
        let store = RecordingSessionStore(
            sourceCatalog: TestSourceCatalog(screens: [makeScreen(id: 1, isPrimary: true)]),
            captureAuthorization: authorization,
            preferencesStore: InMemoryPreferences(snapshot: PreferencesSnapshot(
                capturesSystemAudio: true,
                capturesMicrophone: true,
                capturesWebcam: true
            )),
            recordingPipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL())
        )
        await store.initialize()
        let counts = await authorization.counts()
        XCTAssertEqual(counts.camera, 1)
        XCTAssertEqual(counts.microphone, 1)
        XCTAssertEqual(counts.systemAudio, 1)
    }

    @MainActor
    func testWebcamDraggingDoesNotReregisterGlobalShortcut() async {
        let store = makeStore(
            pipeline: TestRecordingPipeline(outputURL: temporaryRecordingURL())
        )
        await store.initialize()
        var shortcutUpdates = 0
        store.shortcutPreferenceChanged = { _ in
            shortcutUpdates += 1
            return true
        }

        for step in 0..<40 {
            store.updateWebcamPosition(NormalizedWebcamPosition(x: Double(step) / 40, y: 0.5))
        }
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(shortcutUpdates, 0)
        store.updateGlobalShortcut(GlobalShortcut(
            keyCode: UInt16(kVK_ANSI_R), modifiers: UInt32(cmdKey | shiftKey), keyDisplayName: "R"
        ))
        XCTAssertEqual(shortcutUpdates, 1)
    }

    func testMicrophoneDrivesMainAudioTrackWhenSystemAudioIsAlsoCaptured() async throws {
        XCTAssertEqual(MediaTrackLayout.microphoneTrack, 0)
        XCTAssertEqual(MediaTrackLayout.systemAudioTrack(capturesMicrophone: false), 0)
        XCTAssertEqual(MediaTrackLayout.systemAudioTrack(capturesMicrophone: true), 1)

        let sink = RecordingMediaSink()
        let forwarder = MediaSampleForwarder(sink: sink, systemAudioTrack: 1, microphoneTrack: 0)
        let sampleBuffer = try makeVideoSampleBuffer()
        forwarder.yield(sampleBuffer, outputType: .audio)
        forwarder.yieldMicrophone(sampleBuffer)
        let receivedAudio = await waitUntil { await sink.audioTracks().sorted() == [0, 1] }
        XCTAssertTrue(receivedAudio)
        await forwarder.stop()
    }

    func testStoppedSampleForwarderRejectsFramesFromPreviousSession() async throws {
        let sink = RecordingMediaSink()
        let firstSession = MediaSampleForwarder(sink: sink)
        let sampleBuffer = try makeVideoSampleBuffer()
        firstSession.yield(sampleBuffer, outputType: .screen)
        let receivedFrame = await waitUntil { await sink.videoAppendCount() == 1 }
        XCTAssertTrue(receivedFrame)
        await firstSession.stop()
        firstSession.yield(sampleBuffer, outputType: .screen)
        try await Task.sleep(for: .milliseconds(30))
        let frameCount = await sink.videoAppendCount()
        XCTAssertEqual(frameCount, 1)
    }

    func testScreenAndWebcamFramesUseSeparateVideoTracks() async throws {
        let sink = RecordingMediaSink()
        let forwarder = MediaSampleForwarder(sink: sink)
        let sampleBuffer = try makeVideoSampleBuffer()
        forwarder.yield(sampleBuffer, outputType: .screen)
        forwarder.yieldWebcam(sampleBuffer)
        let receivedTracks = await waitUntil { await sink.videoTracks().sorted() == [0, 1] }
        XCTAssertTrue(receivedTracks)
        await forwarder.stop()
    }

    func testWebcamSampleTimestampsCanBeMappedToCaptureClock() throws {
        let sampleBuffer = try makeVideoSampleBuffer()
        let offset = CMTime(seconds: 3, preferredTimescale: 600)
        let synchronizedSample = try XCTUnwrap(copySampleBuffer(sampleBuffer) { CMTimeAdd($0, offset) })
        XCTAssertEqual(synchronizedSample.presentationTimeStamp, offset)
        XCTAssertEqual(synchronizedSample.duration, sampleBuffer.duration)
        XCTAssertEqual(synchronizedSample.imageBuffer, sampleBuffer.imageBuffer)
    }

    func testOnlyCompleteScreenCaptureFramesAreUsable() {
        XCTAssertTrue(isCompleteScreenCaptureFrame([
            .status: SCFrameStatus.complete.rawValue,
        ]))
        XCTAssertFalse(isCompleteScreenCaptureFrame([
            .status: SCFrameStatus.blank.rawValue,
        ]))
        XCTAssertFalse(isCompleteScreenCaptureFrame([
            .status: SCFrameStatus.started.rawValue,
        ]))
        XCTAssertFalse(isCompleteScreenCaptureFrame([
            .status: SCFrameStatus.idle.rawValue,
        ]))
        XCTAssertFalse(isCompleteScreenCaptureFrame(nil))
    }

    func testFailedFinalizationRemovesRecordingDirectory() async throws {
        let recordingsDirectory = temporaryRecordingsDirectory()
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }
        let recorder = LocalMediaRecorder(recordingsDirectory: recordingsDirectory)
        try await recorder.start(
            profile: OutputProfile(
                width: 640,
                height: 360,
                videoBitRate: 1_000_000,
                frameRate: 30,
                audioBitRate: 128_000
            ),
            capturesAudio: false,
            webcamEnabled: false,
            webcamLayout: .defaultLayout
        )

        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: recordingsDirectory.path).count,
            1
        )
        do {
            _ = try await recorder.finish()
            XCTFail("Expected an empty recording to fail finalization")
        } catch {
            XCTAssertTrue(
                try FileManager.default.contentsOfDirectory(atPath: recordingsDirectory.path).isEmpty
            )
        }
    }

    func testLocalRecorderFinalizesVideoAndAudioMP4() async throws {
        let recordingsDirectory = temporaryRecordingsDirectory()
        defer { try? FileManager.default.removeItem(at: recordingsDirectory) }
        // AAC encoder discovery uses a macOS service that is unavailable in some
        // test sandboxes. Probe a known format independently of the recorder so
        // missing host capabilities do not masquerade as a recording regression.
        try requireAACEncoder(in: recordingsDirectory)
        let recorder = LocalMediaRecorder(recordingsDirectory: recordingsDirectory)
        let profile = OutputProfile(
            width: 640,
            height: 360,
            videoBitRate: 1_000_000,
            frameRate: 30,
            audioBitRate: 128_000
        )
        try await recorder.start(
            profile: profile,
            capturesAudio: true,
            webcamEnabled: false,
            webcamLayout: .defaultLayout
        )
        let mixer = MediaMixer(captureSessionMode: .manual)
        let baseSeconds = ProcessInfo.processInfo.systemUptime
        let audioFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)
        )

        recorder.mixer(
            mixer,
            didOutput: try makeVideoSampleBuffer(
                presentationTimeStamp: CMTime(
                    seconds: baseSeconds - 1,
                    preferredTimescale: 1_000_000_000
                )
            )
        )
        try await Task.sleep(for: .milliseconds(20))
        await recorder.appendVideo(
            try makeWhiteVideoSampleBuffer(
                presentationTimeStamp: CMTime(
                    seconds: baseSeconds,
                    preferredTimescale: 1_000_000_000
                )
            ),
            track: 0
        )
        let leadingAudio = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 800)
        )
        leadingAudio.frameLength = 800
        recorder.mixer(
            mixer,
            didOutput: leadingAudio,
            when: AVAudioTime(
                hostTime: AVAudioTime.hostTime(forSeconds: baseSeconds - 0.5)
            )
        )
        try await Task.sleep(for: .milliseconds(20))

        for frame in 0..<30 {
            let videoTime = CMTime(
                seconds: baseSeconds + Double(frame) / 30,
                preferredTimescale: 1_000_000_000
            )
            recorder.mixer(
                mixer,
                didOutput: try makeWhiteVideoSampleBuffer(presentationTimeStamp: videoTime)
            )
            if frame == 9 {
                // ScreenCaptureKit can deliver video well before microphone samples.
                // Exercise a delay longer than the recorder's former 300 ms fallback.
                try await Task.sleep(for: .milliseconds(350))
            }
            guard frame >= 10 else { continue }
            for audioIndex in 0..<2 {
                let sample = frame * 1_600 + audioIndex * 800
                let buffer = try XCTUnwrap(
                    AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: 800)
                )
                buffer.frameLength = 800
                for channel in 0..<Int(audioFormat.channelCount) {
                    guard let samples = buffer.floatChannelData?[channel] else {
                        XCTFail("Expected Float32 audio samples")
                        continue
                    }
                    for frameOffset in 0..<Int(buffer.frameLength) {
                        let absoluteSample = sample + frameOffset
                        samples[frameOffset] = Float(
                            0.4 * sin(2 * .pi * 440 * Double(absoluteSample) / 48_000)
                        )
                    }
                }
                let seconds = baseSeconds + Double(sample) / 48_000
                try await recorder.appendAudio(
                    makeAudioSampleBuffer(
                        buffer,
                        presentationTimeStamp: CMTime(
                            seconds: seconds,
                            preferredTimescale: 1_000_000_000
                        )
                    ),
                    track: 0
                )
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(400))

        let artifacts = try await recorder.finish()
        let outputURL = artifacts.recordingURL
        XCTAssertEqual(
            outputURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
            recordingsDirectory.standardizedFileURL
        )
        XCTAssertEqual(outputURL.lastPathComponent, "recording.mp4")
        XCTAssertTrue(outputURL.deletingLastPathComponent().lastPathComponent.hasPrefix("ScreenContext "))
        let files = try FileManager.default.contentsOfDirectory(
            at: outputURL.deletingLastPathComponent(), includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.map(\.lastPathComponent), ["recording.mp4"])
        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 1)
        XCTAssertGreaterThan(duration, 0.5)
        let maximumAudioAmplitude = try await maximumDecodedAudioAmplitude(in: asset)
        XCTAssertGreaterThan(
            maximumAudioAmplitude,
            1_000,
            "The finalized MP4 contains an audio track, but its decoded samples are silent."
        )
    }
}

private func requireAACEncoder(in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let probe = try AVAssetWriter(
        outputURL: directory.appendingPathComponent("encoder-probe.mp4"),
        fileType: .mp4
    )
    let supported = probe.canApply(outputSettings: [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000,
    ], forMediaType: .audio)
    try XCTSkipUnless(
        supported,
        "The host cannot access the macOS AAC encoder. Run script/test_unit.sh outside the execution sandbox to validate media encoding."
    )
}

private func makeAudioSampleBuffer(
    _ buffer: AVAudioPCMBuffer,
    presentationTimeStamp: CMTime
) throws -> CMSampleBuffer {
    var sampleBuffer: CMSampleBuffer?
    var status = CMAudioSampleBufferCreateWithPacketDescriptions(
        allocator: nil,
        dataBuffer: nil,
        dataReady: false,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: buffer.format.formatDescription,
        sampleCount: Int(buffer.frameLength),
        presentationTimeStamp: presentationTimeStamp,
        packetDescriptions: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sampleBuffer else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    status = CMSampleBufferSetDataBufferFromAudioBufferList(
        sampleBuffer,
        blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault,
        flags: 0,
        bufferList: buffer.audioBufferList
    )
    guard status == noErr else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return sampleBuffer
}

private func maximumDecodedAudioAmplitude(in asset: AVAsset) async throws -> Int16 {
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    let track = try XCTUnwrap(audioTracks.first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    )
    guard reader.canAdd(output) else {
        XCTFail("Could not add decoded audio reader output")
        return 0
    }
    reader.add(output)
    guard reader.startReading() else {
        throw try XCTUnwrap(reader.error)
    }

    var maximum: Int16 = 0
    while let sampleBuffer = output.copyNextSampleBuffer(),
          let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        var samples = [Int16](repeating: 0, count: byteCount / MemoryLayout<Int16>.size)
        let status = samples.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: bytes.baseAddress!
            )
        }
        guard status == kCMBlockBufferNoErr else { continue }
        for value in samples {
            let magnitude = value == .min ? Int16.max : abs(value)
            maximum = max(maximum, magnitude)
        }
    }
    return maximum
}

private actor TestSourceCatalog: CaptureSourceCatalog {
    let values: [CaptureSource]
    init(screens: [ScreenSource], windows: [WindowSource] = []) {
        values = screens.map(CaptureSource.display) + windows.map(CaptureSource.window)
    }
    func sources() -> [CaptureSource] { values }
}

private actor InMemoryPreferences: PreferencesStore {
    var snapshot: PreferencesSnapshot
    init(snapshot: PreferencesSnapshot) { self.snapshot = snapshot }
    func load() -> PreferencesSnapshot { snapshot }
    func save(_ snapshot: PreferencesSnapshot) { self.snapshot = snapshot }
}

private actor TestRecordingPipeline: RecordingPipeline {
    private let outputURL: URL
    private var startCount = 0
    private var stopCount = 0
    private var cancelCount = 0
    private var continuation: AsyncStream<RecordingPipelineEvent>.Continuation?
    private var configuration: RecordingConfiguration?

    init(
        outputURL: URL
    ) {
        self.outputURL = outputURL
    }
    func start(configuration: RecordingConfiguration) -> AsyncStream<RecordingPipelineEvent> {
        startCount += 1
        self.configuration = configuration
        let events = AsyncStream.makeStream(of: RecordingPipelineEvent.self)
        continuation = events.continuation
        return events.stream
    }
    func stop() -> RecordingArtifacts {
        stopCount += 1
        continuation?.finish()
        return RecordingArtifacts(recordingURL: outputURL)
    }
    func cancel() {
        cancelCount += 1
        continuation?.finish()
    }
    func startCountValue() -> Int { startCount }
    func stopCountValue() -> Int { stopCount }
    func configurationValue() -> RecordingConfiguration? { configuration }
}

private actor RecoverableFailureRecordingPipeline: RecordingPipeline {
    private let recoveryURL: URL
    private var continuation: AsyncStream<RecordingPipelineEvent>.Continuation?

    init(recoveryURL: URL) {
        self.recoveryURL = recoveryURL
    }

    func start(configuration: RecordingConfiguration) -> AsyncStream<RecordingPipelineEvent> {
        let events = AsyncStream.makeStream(of: RecordingPipelineEvent.self)
        continuation = events.continuation
        return events.stream
    }


    func stop() throws -> RecordingArtifacts {
        continuation?.finish()
        throw RecordingRecoveryError(
            recoveryURL: recoveryURL,
            diagnosticDescription: "Synthetic writer failure"
        )
    }

    func cancel() {
        continuation?.finish()
    }
}

private actor FailingStartRecordingPipeline: RecordingPipeline {
    func start(configuration: RecordingConfiguration) throws -> AsyncStream<RecordingPipelineEvent> {
        throw TestRecordingAnalyticsError.failed
    }
    func stop() throws -> RecordingArtifacts { throw TestRecordingAnalyticsError.failed }
    func cancel() {}
}

private actor NonRecoverableFailureRecordingPipeline: RecordingPipeline {
    private var continuation: AsyncStream<RecordingPipelineEvent>.Continuation?
    func start(configuration: RecordingConfiguration) -> AsyncStream<RecordingPipelineEvent> {
        let events = AsyncStream.makeStream(of: RecordingPipelineEvent.self)
        continuation = events.continuation
        return events.stream
    }
    func stop() throws -> RecordingArtifacts {
        continuation?.finish()
        throw TestRecordingAnalyticsError.failed
    }
    func cancel() { continuation?.finish() }
}

private enum TestRecordingAnalyticsError: Error {
    case failed
}

private actor BlockingStartPipeline: RecordingPipeline {
    private let outputURL: URL
    private var continuation: CheckedContinuation<Void, Never>?
    private var cancelCount = 0
    init(outputURL: URL) { self.outputURL = outputURL }
    func start(configuration: RecordingConfiguration) async -> AsyncStream<RecordingPipelineEvent> {
        await withCheckedContinuation { continuation = $0 }
        return AsyncStream { $0.finish() }
    }
    func stop() -> RecordingArtifacts {
        RecordingArtifacts(recordingURL: outputURL)
    }
    func cancel() {
        cancelCount += 1
        continuation?.resume()
        continuation = nil
    }
    func releaseStart() { continuation?.resume(); continuation = nil }
    func cancelCountValue() -> Int { cancelCount }
}

private actor RecordingCaptureAuthorization: CaptureAuthorization {
    private var cameraCount = 0
    private var microphoneCount = 0
    private var systemAudioCount = 0
    func requestCameraAccess() -> Bool { cameraCount += 1; return true }
    func requestMicrophoneAccess() -> Bool { microphoneCount += 1; return true }
    func requestSystemAudioAccess(for source: CaptureSource) -> Bool { systemAudioCount += 1; return true }
    func counts() -> (camera: Int, microphone: Int, systemAudio: Int) {
        (cameraCount, microphoneCount, systemAudioCount)
    }
}

private actor PermittedCaptureAuthorization: CaptureAuthorization {
    func requestCameraAccess() -> Bool { true }
    func requestMicrophoneAccess() -> Bool { true }
    func requestSystemAudioAccess(for source: CaptureSource) -> Bool { true }
}

private actor RecordingMediaSink: MediaSampleSink {
    private var appendedVideoTracks: [UInt8] = []
    private var appendedAudioTracks: [UInt8] = []
    func appendVideo(_ sampleBuffer: CMSampleBuffer, track: UInt8) { appendedVideoTracks.append(track) }
    func appendAudio(_ sampleBuffer: CMSampleBuffer, track: UInt8) { appendedAudioTracks.append(track) }
    func videoAppendCount() -> Int { appendedVideoTracks.count }
    func videoTracks() -> [UInt8] { appendedVideoTracks }
    func audioTracks() -> [UInt8] { appendedAudioTracks }
}

@MainActor
private func makeStore(
    pipeline: any RecordingPipeline,
    recordingHistoryStore: any RecordingHistoryStore = VolatileRecordingHistoryStore(),
    analyticsClient: any AnalyticsClient = NoOpAnalyticsClient()
) -> RecordingSessionStore {
    RecordingSessionStore(
        sourceCatalog: TestSourceCatalog(screens: [makeScreen(id: 1, isPrimary: true)]),
        captureAuthorization: PermittedCaptureAuthorization(),
        preferencesStore: InMemoryPreferences(snapshot: PreferencesSnapshot(
            selectedCaptureSourceID: .display(1),
            capturesSystemAudio: false,
            capturesMicrophone: false
        )),
        recordingHistoryStore: recordingHistoryStore,
        recordingPipeline: pipeline,
        analyticsClient: analyticsClient
    )
}

@MainActor
private final class StoreAnalyticsSpy: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []
    func capture(_ event: AnalyticsEvent) { events.append(event) }
    func optIn() {}
    func optOut() {}
    func flush() {}
}

private actor TestRecordingHistoryStore: RecordingHistoryStore {
    private var snapshot: RecordingHistorySnapshot
    private var deletedIDs: [UUID] = []

    init(snapshot: RecordingHistorySnapshot = RecordingHistorySnapshot()) {
        self.snapshot = snapshot
    }

    func load() -> RecordingHistorySnapshot { snapshot }
    func save(_ snapshot: RecordingHistorySnapshot) { self.snapshot = snapshot }
    func delete(_ recording: RecordingHistoryEntry) {
        deletedIDs.append(recording.id)
        snapshot = RecordingHistorySnapshot(
            recordings: snapshot.recordings.filter { $0.id != recording.id },
            selectedRecordingID: snapshot.selectedRecordingID
        )
    }
    func snapshotValue() -> RecordingHistorySnapshot { snapshot }
    func deletedIDsValue() -> [UUID] { deletedIDs }
}

private actor SuspendingRecordingHistoryStore: RecordingHistoryStore {
    private var snapshot: RecordingHistorySnapshot
    private var deletedIDs: [UUID] = []
    private var shouldSuspendNextSave = false
    private var saveDidStart = false
    private var saveStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveReleaseContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: RecordingHistorySnapshot) {
        self.snapshot = snapshot
    }

    func load() -> RecordingHistorySnapshot { snapshot }

    func save(_ snapshot: RecordingHistorySnapshot) async {
        if shouldSuspendNextSave {
            shouldSuspendNextSave = false
            saveDidStart = true
            saveStartWaiters.forEach { $0.resume() }
            saveStartWaiters.removeAll()
            await withCheckedContinuation { continuation in
                saveReleaseContinuation = continuation
            }
        }
        self.snapshot = snapshot
    }

    func delete(_ recording: RecordingHistoryEntry) {
        deletedIDs.append(recording.id)
        snapshot = RecordingHistorySnapshot(
            recordings: snapshot.recordings.filter { $0.id != recording.id },
            selectedRecordingID: snapshot.selectedRecordingID
        )
    }

    func suspendNextSave() {
        shouldSuspendNextSave = true
        saveDidStart = false
    }

    func waitUntilSaveStarts() async {
        guard !saveDidStart else { return }
        await withCheckedContinuation { continuation in
            saveStartWaiters.append(continuation)
        }
    }

    func resumeSave() {
        saveReleaseContinuation?.resume()
        saveReleaseContinuation = nil
    }

    func deletedIDsValue() -> [UUID] { deletedIDs }
}

private func recordingHistoryEntry(id: UUID, timestamp: TimeInterval) -> RecordingHistoryEntry {
    RecordingHistoryEntry(
        id: id,
        fileURL: temporaryRecordingURL(),
        recordedAt: Date(timeIntervalSince1970: timestamp)
    )
}

private func temporaryRecordingURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("screencontext-\(UUID().uuidString).mp4")
}

private func temporaryRecordingsDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "screencontext-recorder-\(UUID().uuidString)",
        isDirectory: true
    )
}

private func makeVideoSampleBuffer(
    presentationTimeStamp: CMTime = .zero
) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    let pixelStatus = CVPixelBufferCreate(
        kCFAllocatorDefault, 2, 2, kCVPixelFormatType_32BGRA, nil, &pixelBuffer
    )
    guard pixelStatus == kCVReturnSuccess, let pixelBuffer else {
        throw NSError(domain: "ScreenContextTests", code: Int(pixelStatus))
    }
    var formatDescription: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else {
        throw NSError(domain: "ScreenContextTests", code: Int(formatStatus))
    }
    var timing = CMSampleTimingInfo(
        duration: .invalid,
        presentationTimeStamp: presentationTimeStamp,
        decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr, let sampleBuffer else {
        throw NSError(domain: "ScreenContextTests", code: Int(sampleStatus))
    }
    return sampleBuffer
}

private func makeWhiteVideoSampleBuffer(
    presentationTimeStamp: CMTime
) throws -> CMSampleBuffer {
    let sampleBuffer = try makeVideoSampleBuffer(
        presentationTimeStamp: presentationTimeStamp
    )
    guard let pixelBuffer = sampleBuffer.imageBuffer else {
        throw NSError(domain: "ScreenContextTests", code: -1)
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        throw NSError(domain: "ScreenContextTests", code: -2)
    }
    memset(baseAddress, 0xFF, CVPixelBufferGetDataSize(pixelBuffer))
    return sampleBuffer
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

@MainActor
@discardableResult
private func waitUntilOnMainActor(
    timeout: Duration = .seconds(1),
    condition: @MainActor () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}
