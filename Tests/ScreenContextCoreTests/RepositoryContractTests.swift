import Foundation
import XCTest

final class RepositoryContractTests: XCTestCase {
    private let expectedLocales: Set<String> = [
        "en", "ar", "de", "es", "fr", "it", "ja-JP", "ko-KR",
        "ru", "tr", "vi", "pt-BR", "zh-CN", "zh-TW",
    ]

    func testCatalogContainsAllFourteenLocalesForEveryLocalizedKey() throws {
        let catalogURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        XCTAssertFalse(strings.isEmpty)
        for (key, value) in strings {
            let entry = try XCTUnwrap(value as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), expectedLocales, "Missing locale for \(key)")
        }
    }

    func testCaptureCodeSupportsSingleWindowRecording() throws {
        let services = repositoryRoot.appendingPathComponent("Sources/ScreenContextCore/Services")
        let source = try swiftSources(under: services)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertTrue(source.contains("content.windows"))
        XCTAssertTrue(source.contains("desktopIndependentWindow"))

        let hudURL = repositoryRoot.appendingPathComponent("Sources/ScreenContext/Views/CaptureSettingsView.swift")
        let hudSource = try String(contentsOf: hudURL, encoding: .utf8)
        XCTAssertTrue(hudSource.contains("Section(\"Screens\")"))
        XCTAssertTrue(hudSource.contains("Section(\"Windows\")"))
        XCTAssertTrue(hudSource.contains("selectCaptureSource(source.id)"))
    }

    func testWindowSelectionIsTransientAndRecordingUsesLiveGeometry() throws {
        let preferencesURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContextCore/Models/Preferences.swift")
        let preferencesSource = try String(contentsOf: preferencesURL, encoding: .utf8)
        XCTAssertTrue(preferencesSource.contains("sanitizedForPersistence"))
        XCTAssertTrue(preferencesSource.contains("selectedCaptureSourceID = nil"))
        XCTAssertTrue(preferencesSource.contains("lastCaptureSourceKind"))

        let pipelineURL = repositoryRoot.appendingPathComponent(
            "Sources/ScreenContextCore/Services/ScreenCaptureRecordingPipeline.swift"
        )
        let pipelineSource = try String(contentsOf: pipelineURL, encoding: .utf8)
        XCTAssertTrue(pipelineSource.contains("resolvedTarget.pixelWidth"))
        XCTAssertTrue(pipelineSource.contains("resolvedTarget.pixelHeight"))
        XCTAssertFalse(pipelineSource.contains("OutputProfile.make(for: configuration.source)"))

        let factoryURL = repositoryRoot.appendingPathComponent(
            "Sources/ScreenContextCore/Services/ScreenCaptureKitContentFilterFactory.swift"
        )
        let factorySource = try String(contentsOf: factoryURL, encoding: .utf8)
        XCTAssertTrue(factorySource.contains("filter.contentRect"))
        XCTAssertTrue(factorySource.contains("filter.pointPixelScale"))

        let hudURL = repositoryRoot.appendingPathComponent("Sources/ScreenContext/Views/CaptureSettingsView.swift")
        let hudSource = try String(contentsOf: hudURL, encoding: .utf8)
        XCTAssertTrue(hudSource.contains("Choose a screen or window"))
        XCTAssertTrue(hudSource.contains(".disabled(store.configurationIsLocked)"))
    }






    func testWebcamLayoutEditorPreservesLiveCaptureGeometry() throws {
        let overlayURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/Panels/WebcamOverlayPanelController.swift")
        let source = try String(contentsOf: overlayURL, encoding: .utf8)
        XCTAssertTrue(source.contains("liveAppKitFrame(forWindowID:"))
        XCTAssertTrue(source.contains("inside: canvasFrame"))
        XCTAssertTrue(source.contains("previewFrame.maxY + Self.shapePickerSpacing"))
        XCTAssertTrue(source.contains("store?.updateWebcamPosition"))
        XCTAssertTrue(source.contains("store?.updateWebcamSize"))
        XCTAssertTrue(source.contains("Picker(\"Webcam shape\""))
    }

    func testSettingsSceneDoesNotOpenAtLaunch() throws {
        let appURL = repositoryRoot.appendingPathComponent("Sources/ScreenContext/App/ScreenContextApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)
        let menuBarLocation = try XCTUnwrap(source.range(of: "MenuBarExtra"))
        let settingsLocation = try XCTUnwrap(source.range(of: "Settings {"))
        XCTAssertLessThan(menuBarLocation.lowerBound, settingsLocation.lowerBound)
        XCTAssertTrue(source.contains(".defaultLaunchBehavior(.suppressed)"))
    }

    func testRecordingPlaybackStartsAutomatically() throws {
        let playbackURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/Views/RecordingResultView.swift")
        let source = try String(contentsOf: playbackURL, encoding: .utf8)
        let settingsURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/Views/ScreenContextTemplateSettingsView.swift")
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(source.contains("RecordingPlayerView(fileURL: result.fileURL)"))
        XCTAssertTrue(source.contains(".frame(width: 572, height: mediaHeight)"))
        XCTAssertTrue(source.contains("Label(\"Recording context\", systemImage: \"text.quote\")"))
        XCTAssertTrue(source.contains(".frame(height: mediaHeight)"))
        XCTAssertTrue(source.contains("result.transcriptIsAvailable || !result.requestedTranscription"))
        XCTAssertTrue(source.contains("player.play()"))
        XCTAssertTrue(source.contains("controlsStyle = .minimal"))
        XCTAssertTrue(source.contains("controlsStyle = .none"))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Copy video\""))
        XCTAssertTrue(source.contains("Picker(\"Transcript format\""))
        XCTAssertTrue(source.contains("case template(ScreenContextTemplate.ID)"))
        XCTAssertTrue(source.contains("case markdown"))
        XCTAssertTrue(source.contains("case srt"))
        XCTAssertTrue(source.contains("ForEach(editableScreenContextTemplates)"))
        XCTAssertTrue(source.contains("Text(\"Markdown\").tag(TranscriptFormat.markdown)"))
        XCTAssertTrue(source.contains("TranscriptMarkdownFormatter().format"))
        XCTAssertTrue(source.contains("ScreenContextTemplateFormatter().format"))
        XCTAssertTrue(source.contains("ScreenContextTemplatePreferenceKey.library"))
        XCTAssertFalse(source.contains("SystemRequestExtractor"))
        XCTAssertFalse(source.contains("Apple Intelligence"))
        XCTAssertTrue(source.contains("@Bindable var store: RecordingSessionStore"))
        XCTAssertTrue(source.contains("let fallbackResult: RecordingResult"))
        XCTAssertTrue(source.contains("result.transcriptSRT"))
        XCTAssertTrue(source.contains("result.keyframes"))
        XCTAssertTrue(source.contains("Button(\"Download Model\")"))
        XCTAssertTrue(source.contains("await store.installTranscriptionModel(for: result)"))
        XCTAssertTrue(source.contains("ProgressView(\"Transcribing recording…\")"))
        XCTAssertTrue(source.contains("NavigationSplitView"))
        XCTAssertTrue(source.contains("List(selection: recordingSelection)"))
        XCTAssertTrue(source.contains("ForEach(store.recordingResults.reversed())"))
        XCTAssertTrue(source.contains("Image(systemName: \"video.fill\")"))
        XCTAssertTrue(source.contains(".fill(.regularMaterial)"))
        XCTAssertTrue(source.contains(".background(.bar)"))
        XCTAssertTrue(source.contains("store.selectRecording(id)"))
        XCTAssertFalse(source.contains("Button(action: store.selectPreviousRecording)"))
        XCTAssertFalse(source.contains("Button(action: store.selectNextRecording)"))
        XCTAssertFalse(source.contains("store.selectedRecordingPosition"))
        XCTAssertTrue(source.contains("result.recordedAt"))
        XCTAssertTrue(source.contains("Button(role: .destructive)"))
        XCTAssertTrue(source.contains("await store.deleteSelectedRecording()"))
        XCTAssertTrue(source.contains("This permanently deletes the video and its keyframes."))
        XCTAssertTrue(source.contains("accessibilityLabel: \"Copy transcript\""))
        XCTAssertTrue(source.contains("pasteboard.setString(displayedTranscript, forType: .string)"))
        XCTAssertTrue(settingsSource.contains("List(editableTemplates"))
        XCTAssertTrue(settingsSource.contains("ScreenContextTemplateLibrary.markdownID"))
        XCTAssertTrue(source.contains("Video copied"))
        XCTAssertTrue(source.contains("Context copied"))
        XCTAssertTrue(source.contains("notification: .announcementRequested"))
        XCTAssertTrue(source.contains("item.setString(fileURL.absoluteString, forType: .fileURL)"))
        XCTAssertTrue(source.contains("pasteboard.writeObjects([item])"))
        XCTAssertFalse(source.contains("ScrollView {"))
        XCTAssertFalse(source.contains("Text(\"Share this recording\")"))
        XCTAssertFalse(source.contains("sharingOptions"))
        XCTAssertFalse(source.contains("NSCursor.pointingHand"))
        XCTAssertFalse(source.contains("pointingHandOnHover"))
        XCTAssertFalse(source.contains("NSSharingServicePicker"))
        XCTAssertFalse(source.contains("LocalRecordingShareButton"))
        XCTAssertFalse(source.contains("Share…"))
        XCTAssertFalse(source.contains("ShareLink("))
        XCTAssertFalse(source.contains("VideoPlayer(player:"))

        let transcriptURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/Views/ReadOnlyTranscriptTextView.swift")
        let transcriptSource = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertTrue(transcriptSource.contains("NSScrollView()"))
        XCTAssertTrue(transcriptSource.contains("hasVerticalScroller = true"))
    }

    func testRecordingsLibraryIsAvailableFromMenuBar() throws {
        let menuURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/Views/MenuBarContentView.swift")
        let menuSource = try String(contentsOf: menuURL, encoding: .utf8)
        XCTAssertTrue(menuSource.contains("Button(\"Recordings\", action: openRecordings)"))

        let appDelegateURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/App/AppDelegate.swift")
        let appDelegateSource = try String(contentsOf: appDelegateURL, encoding: .utf8)
        XCTAssertTrue(appDelegateSource.contains("recordingResultController?.presentSelectedRecording()"))
    }

    func testRecordingResultWindowIsMovable() throws {
        let controllerURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContext/Panels/RecordingResultPanelController.swift")
        let source = try String(contentsOf: controllerURL, encoding: .utf8)

        XCTAssertTrue(source.contains("window.isMovable = true"))
        XCTAssertTrue(source.contains("WindowPresentation.bringToFront(window)"))
        XCTAssertTrue(source.contains("store: store"))
        XCTAssertTrue(source.contains("func present(_ result: RecordingResult)"))
        XCTAssertTrue(source.contains("func presentSelectedRecording()"))
        XCTAssertTrue(source.contains("localized: \"Recordings\""))
        XCTAssertTrue(source.contains("contentWidth: CGFloat = 860"))
        XCTAssertTrue(source.contains("locale: result.locale"))
        XCTAssertFalse(source.contains("locale: store.effectiveLocale"))
        XCTAssertTrue(source.contains("WindowPresentation.afterMenuDismissal"))
        XCTAssertTrue(source.contains("visibleFrame.height"))
        XCTAssertTrue(source.contains("defaultMediaHeight"))
        XCTAssertTrue(source.contains("minimumMediaHeight"))
        XCTAssertTrue(source.contains("overflow / 2"))
        XCTAssertTrue(source.contains("window.contentView = hostingView"))
        XCTAssertFalse(source.contains(".resizable"))
        XCTAssertFalse(source.contains("parent?.presentSheet(window)"))
    }

    func testScreenContextBrandAssetsAndIdentityAreComplete() throws {
        let resources = repositoryRoot.appendingPathComponent("Sources/ScreenContext/Resources")
        let catalog = resources.appendingPathComponent("Assets.xcassets")
        for relativePath in [
            "AppIcon.appiconset/icon_512x512@2x.png",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: catalog.appendingPathComponent(relativePath).path
                ),
                "Missing brand asset: \(relativePath)"
            )
        }

        let retiredName = ["Paste", "Cast"].joined()
        for fileURL in try repositoryFiles(under: repositoryRoot) {
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            XCTAssertFalse(
                contents.localizedCaseInsensitiveContains(retiredName),
                "Found retired product identity in \(fileURL.path)"
            )
        }
    }

    func testTranscriptionUsesOnlySpeechAnalyzerAndRetriesAfterModelDownload() throws {
        let services = repositoryRoot.appendingPathComponent("Sources/ScreenContextCore/Services")
        let serviceSource = try swiftSources(under: services)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertFalse(serviceSource.contains("SFSpeechRecognizer"))
        XCTAssertFalse(serviceSource.contains("SFSpeechRecognitionTask"))
        XCTAssertFalse(serviceSource.contains("SFSpeechAudioBufferRecognitionRequest"))
        XCTAssertTrue(serviceSource.contains("SpeechAnalyzer"))
        XCTAssertTrue(serviceSource.contains("SpeechTranscriber"))
        XCTAssertTrue(serviceSource.contains("SpeechTranscriber.installedLocales"))
        XCTAssertTrue(serviceSource.contains("AssetInventory.reserve(locale: locale)"))
        XCTAssertTrue(serviceSource.contains("SpeechAssetPreparation.status(for: transcriber)"))
        XCTAssertTrue(serviceSource.contains("AssetInventory.assetInstallationRequest"))
        XCTAssertTrue(serviceSource.contains("analyzer.analyzeSequence(from: audioFile)"))

        let liveTranscriberURL = services
            .appendingPathComponent("ModernOnDeviceSpeechTranscriber.swift")
        let liveTranscriberSource = try String(
            contentsOf: liveTranscriberURL,
            encoding: .utf8
        )
        let finishInput = try XCTUnwrap(
            liveTranscriberSource.range(of: "inputContinuation?.finish()")
        )
        let finalizeInput = try XCTUnwrap(
            liveTranscriberSource.range(of: "finalizeAndFinishThroughEndOfInput()")
        )
        let startStreaming = try XCTUnwrap(
            liveTranscriberSource.range(of: "analyzer.start(inputSequence: inputs.stream)")
        )
        XCTAssertLessThan(startStreaming.lowerBound, finishInput.lowerBound)
        XCTAssertLessThan(finishInput.lowerBound, finalizeInput.lowerBound)
        XCTAssertFalse(liveTranscriberSource.contains("analyzeSequence(inputs.stream)"))
        XCTAssertTrue(liveTranscriberSource.contains("AnalyzerInput(buffer: outputBuffer)"))
        XCTAssertFalse(liveTranscriberSource.contains("bufferStartTime:"))

        let storeURL = repositoryRoot
            .appendingPathComponent("Sources/ScreenContextCore/Stores/RecordingSessionStore.swift")
        let storeSource = try String(contentsOf: storeURL, encoding: .utf8)
        XCTAssertTrue(storeSource.contains("await retryLastTranscription()"))
        XCTAssertTrue(storeSource.contains("speechModelManager.transcribeRecording"))
    }

    func testRepositoryGuidanceReferencesMacOSUISkills() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("AGENTS.md"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("build-macos-apps:swiftui-patterns"))
        XCTAssertTrue(source.contains("build-macos-apps:appkit-interop"))
    }

    func testRTMPPublishingSupportIsAbsent() throws {
        let source = try swiftSources(under: repositoryRoot.appendingPathComponent("Sources"))
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let manifest = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        for forbidden in ["RTMPHaishinKit", "RTMPConnection", "RTMPStream", "rtmpServerURL", "rtmpStreamKey"] {
            XCTAssertFalse(source.contains(forbidden), "Found removed publishing API: \(forbidden)")
            XCTAssertFalse(manifest.contains(forbidden), "Found removed publishing dependency: \(forbidden)")
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftSources(under directory: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            )
        )
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func repositoryFiles(under directory: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        )
        return enumerator.compactMap { element in
            guard let url = element as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }
}
