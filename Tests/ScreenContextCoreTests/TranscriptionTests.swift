import XCTest
@testable import ScreenContextCore

final class TranscriptionTests: XCTestCase {
    private let transformer = SRTTranscriptTransformer()

    func testSRTTransformerGroupsWordsAndPreservesTimestamps() {
        let result = transformer.transform(Transcript(segments: [
            TranscriptSegment(startTime: 0.25, duration: 0.4, text: "Hello"),
            TranscriptSegment(startTime: 0.7, duration: 0.5, text: "world."),
            TranscriptSegment(startTime: 2, duration: 0.3, text: "Next"),
            TranscriptSegment(startTime: 2.4, duration: 0.4, text: "line!"),
        ]))

        XCTAssertEqual(
            result,
            """
            1
            00:00:00,250 --> 00:00:01,200
            Hello world.

            2
            00:00:02,000 --> 00:00:02,800
            Next line!
            """
        )
    }

    func testSRTTransformerReturnsEmptyTextWithoutSpeech() {
        XCTAssertEqual(transformer.transform(.empty), "")
    }

    @available(macOS 26.0, *)
    func testInstalledSpeechLocalesCoverEverySelectedLocale() {
        XCTAssertTrue(SpeechAssetPreparation.installedLocalesCover(
            selected: [Locale(identifier: "en_GB")],
            installed: [Locale(identifier: "de_DE"), Locale(identifier: "en_GB")]
        ))
        XCTAssertFalse(SpeechAssetPreparation.installedLocalesCover(
            selected: [Locale(identifier: "en_GB"), Locale(identifier: "fr_FR")],
            installed: [Locale(identifier: "en_GB")]
        ))
        XCTAssertFalse(SpeechAssetPreparation.installedLocalesCover(
            selected: [],
            installed: [Locale(identifier: "en_GB")]
        ))
    }

}

final class TranscriptMarkdownFormatterTests: XCTestCase {
    private let formatter = TranscriptMarkdownFormatter()
    private let recordingURL = URL(fileURLWithPath: "/tmp/save-bug/recording.mp4")

    func testFormatsSRTCuesAsTimestampedMarkdown() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,000
        I open the document and change the title.

        2
        00:00:05,000 --> 00:00:07,000
        Now I click Save.
        """

        XCTAssertEqual(
            formatter.format(
                recordingURL: recordingURL,
                keyframes: [
                    RecordingKeyframe(
                        timestamp: 8,
                        fileURL: URL(fileURLWithPath: "/tmp/save-bug/frame-0008.png")
                    ),
                    RecordingKeyframe(
                        timestamp: 3,
                        fileURL: URL(fileURLWithPath: "/tmp/save-bug/frame-0003.png")
                    ),
                ],
                srt: srt
            ),
            """
            ## Recording

            /tmp/save-bug/recording.mp4

            ## Keyframes

            - 00:03 — /tmp/save-bug/frame-0003.png
            - 00:08 — /tmp/save-bug/frame-0008.png

            ## Transcript

            [00:01] I open the document and change the title.
            [00:05] Now I click Save.
            """
        )
    }

    func testEmptySRTStillProducesTranscriptHeading() {
        XCTAssertEqual(
            formatter.format(recordingURL: recordingURL, keyframes: [], srt: ""),
            """
            ## Recording

            /tmp/save-bug/recording.mp4

            ## Keyframes

            ## Transcript
            """
        )
    }

    func testKeepsHoursForLongRecordings() {
        let srt = """
        1
        01:02:03,400 --> 01:02:04,000
        Still recording.
        """

        XCTAssertEqual(
            formatter.format(recordingURL: nil, keyframes: [], srt: srt),
            "## Recording\n\n## Keyframes\n\n## Transcript\n\n[01:02:03] Still recording."
        )
    }
}

final class ScreenContextTemplateFormatterTests: XCTestCase {
    private let formatter = ScreenContextTemplateFormatter()

    func testReplacesEverySupportedContextElement() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        Save the document.
        """

        XCTAssertEqual(
            formatter.format(
                template: "Before\n\n{transcript}\n\n{recording}\n\n{keyframes}\n\nAfter",
                recordingURL: URL(fileURLWithPath: "/tmp/session/recording.mp4"),
                keyframes: [
                    RecordingKeyframe(
                        timestamp: 3,
                        fileURL: URL(fileURLWithPath: "/tmp/session/frame-0003.png")
                    ),
                ],
                srt: srt
            ),
            """
            Before

            ## Transcript

            [00:01] Save the document.

            ## Recording

            /tmp/session/recording.mp4

            ## Keyframes

            - 00:03 — /tmp/session/frame-0003.png

            After
            """
        )
    }

    func testLeavesUnknownPlaceholdersUntouched() {
        XCTAssertEqual(
            formatter.format(
                template: "{unknown}\n\n{recording}",
                recordingURL: nil,
                keyframes: [],
                srt: ""
            ),
            "{unknown}\n\n## Recording"
        )
    }

    func testProductVideoTemplateRequestsFinishedVideoWithAllContext() {
        let template = ScreenContextTemplateLibrary.decode(Data()).first {
            $0.id == "builtin.product-video"
        }

        XCTAssertTrue(template?.body.contains("finished video presentation") == true)
        for placeholder in ScreenContextTemplateFormatter.placeholders {
            XCTAssertTrue(template?.body.contains(placeholder) == true, "Missing \(placeholder)")
        }
    }
}

final class ScreenContextTemplateLibraryTests: XCTestCase {
    func testEmptyStorageInstallsBundledTemplates() {
        let templates = ScreenContextTemplateLibrary.decode(Data())

        XCTAssertEqual(templates.map(\.id), [
            "builtin.create-issue",
            "builtin.product-video",
        ])
        XCTAssertEqual(templates.map(\.name), ["Create issue", "Product video"])
        XCTAssertTrue(templates.allSatisfy { !$0.body.isEmpty })
    }

    func testStoredLibraryKeepsBundledTemplatesDeleted() throws {
        let customTemplate = ScreenContextTemplate(
            id: "custom",
            name: "Issue report",
            body: "{transcript}"
        )
        let customizedAgentTemplate = ScreenContextTemplate(
            id: "builtin.create-issue",
            name: "My agent",
            body: "Custom {transcript}"
        )
        let data = try ScreenContextTemplateLibrary.encode([
            customTemplate,
            customizedAgentTemplate,
        ])

        let templates = ScreenContextTemplateLibrary.decode(data)

        XCTAssertEqual(templates, [customTemplate, customizedAgentTemplate])
        XCTAssertEqual(
            ScreenContextTemplateLibrary.decode(
                try ScreenContextTemplateLibrary.encode([])
            ),
            []
        )
    }

    func testRestoreAddsOnlyMissingBundledTemplatesWithoutOverwritingChanges() {
        let customTemplate = ScreenContextTemplate(
            id: "custom",
            name: "Issue report",
            body: "{transcript}"
        )
        let customizedAgentTemplate = ScreenContextTemplate(
            id: "builtin.create-issue",
            name: "My agent",
            body: "Custom {transcript}"
        )

        let templates = ScreenContextTemplateLibrary.restoringMissingBundledTemplates(
            in: [customTemplate, customizedAgentTemplate]
        )

        XCTAssertEqual(Array(templates.prefix(2)), [customTemplate, customizedAgentTemplate])
        XCTAssertEqual(Set(templates.map(\.id)), [
            "custom",
            "builtin.create-issue",
            "builtin.product-video",
        ])
        XCTAssertEqual(templates.count, 3)
    }

    func testPlaceholderInsertionReplacesSelectionAndMovesCursorAfterToken() {
        let body = "Before selected after"
        let range = body.range(of: "selected")!

        let insertion = ScreenContextTemplateEditing.inserting(
            "{recording}",
            into: body,
            replacing: range
        )

        XCTAssertEqual(insertion.body, "Before {recording} after")
        XCTAssertEqual(insertion.cursorOffset, "Before {recording}".count)
    }

    func testRoundTripPreservesCurrentLibrary() throws {
        let addedTemplate = ScreenContextTemplate(
            id: "custom",
            name: "Issue report",
            body: "{keyframes}\n\n{transcript}"
        )
        let data = try ScreenContextTemplateLibrary.encode([addedTemplate])
        let templates = ScreenContextTemplateLibrary.decode(data)
        let roundTrippedData = try ScreenContextTemplateLibrary.encode(templates)

        XCTAssertEqual(ScreenContextTemplateLibrary.decode(roundTrippedData), [addedTemplate])
    }
}
