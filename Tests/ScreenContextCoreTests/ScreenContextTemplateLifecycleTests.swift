import XCTest
@testable import ScreenContextCore

final class ScreenContextTemplateLifecycleTests: XCTestCase {
    private let original = ScreenContextTemplate(id: "builtin.original", name: "Original", body: "Old")
    private let added = ScreenContextTemplate(id: "builtin.added", name: "Added", body: "New")
    private let custom = ScreenContextTemplate(id: "custom", name: "My template", body: "{transcript}")

    func testNewBuiltinsAppearAfterSavingCustomTemplates() throws {
        let data = try ScreenContextTemplateLibrary.encode(
            [original, custom], bundledTemplates: [original]
        )
        let upgraded = ScreenContextTemplateLibrary.decode(data, bundledTemplates: [original, added])
        XCTAssertEqual(upgraded, [original, custom, added])
        let saved = try ScreenContextTemplateLibrary.encode(upgraded, bundledTemplates: [original, added])
        XCTAssertEqual(ScreenContextTemplateLibrary.decode(saved, bundledTemplates: [original, added]), upgraded)
    }

    func testDeletedBuiltinsStayDeletedWhileNewBuiltinsAppear() throws {
        let data = try ScreenContextTemplateLibrary.encode([], bundledTemplates: [original])
        XCTAssertEqual(ScreenContextTemplateLibrary.decode(data, bundledTemplates: [original, added]), [added])
    }

    func testUneditedBuiltinUpdatesButUserEditsSurvive() throws {
        var updated = original
        updated.body = "Improved default"
        let unedited = try ScreenContextTemplateLibrary.encode([original], bundledTemplates: [original])
        XCTAssertEqual(ScreenContextTemplateLibrary.decode(unedited, bundledTemplates: [updated]), [updated])

        var edited = original
        edited.name = "My instructions"
        edited.body = "Custom instructions"
        let data = try ScreenContextTemplateLibrary.encode([edited, custom], bundledTemplates: [original])
        XCTAssertEqual(ScreenContextTemplateLibrary.decode(data, bundledTemplates: [updated, added]), [edited, custom, added])
    }

    func testRestoredBuiltinsRemainRestoredAfterRelaunch() throws {
        let deleted = try ScreenContextTemplateLibrary.encode([custom])
        let restored = ScreenContextTemplateLibrary.restoringMissingBundledTemplates(
            in: ScreenContextTemplateLibrary.decode(deleted)
        )
        let saved = try ScreenContextTemplateLibrary.encode(restored)
        XCTAssertEqual(ScreenContextTemplateLibrary.decode(saved), restored)
        XCTAssertEqual(ScreenContextTemplateLibrary.restoringMissingBundledTemplates(in: restored), restored)
    }

    func testCustomEditsDeletionAndOrderSurviveRelaunch() throws {
        var edited = custom
        edited.name = "Renamed"
        edited.body = "{recording}\nMy instructions"
        let saved = try ScreenContextTemplateLibrary.encode([edited, original], bundledTemplates: [original])
        let loaded = ScreenContextTemplateLibrary.decode(saved, bundledTemplates: [original])
        XCTAssertEqual(loaded, [edited, original])
        let deleted = try ScreenContextTemplateLibrary.encode(
            loaded.filter { $0.id != edited.id }, bundledTemplates: [original]
        )
        XCTAssertEqual(ScreenContextTemplateLibrary.decode(deleted, bundledTemplates: [original]), [original])
    }

    func testInvalidStorageFallsBackToBundledTemplates() {
        XCTAssertEqual(
            ScreenContextTemplateLibrary.decode(Data("invalid".utf8), bundledTemplates: [original]),
            [original]
        )
    }

    func testBuiltinCatalogContainsIssueTemplateAndExcludesHardcodedFormats() throws {
        let templates = ScreenContextTemplateLibrary.decode(Data())
        XCTAssertFalse(templates.contains { ["builtin.agent-mode", "builtin.markdown", "builtin.srt"].contains($0.id) })
        let issue = try XCTUnwrap(templates.first { $0.id == "builtin.create-issue" })
        for placeholder in ScreenContextTemplateFormatter.placeholders {
            XCTAssertTrue(issue.body.contains(placeholder))
        }
    }

    func testFormattingDoesNotExpandPlaceholdersInsideInsertedContent() {
        let result = ScreenContextTemplateFormatter().format(
            template: "{recording}\n{keyframes}\n{transcript}\n{recording}",
            recordingURL: URL(fileURLWithPath: "/tmp/{keyframes}/{transcript}.mp4"),
            keyframes: [RecordingKeyframe(timestamp: 0, fileURL: URL(fileURLWithPath: "/tmp/{transcript}.png"))],
            srt: "1\n00:00:00,000 --> 00:00:01,000\nSay {recording}."
        )
        XCTAssertEqual(result.components(separatedBy: "/tmp/{keyframes}/{transcript}.mp4").count, 3)
        XCTAssertTrue(result.contains("/tmp/{transcript}.png"))
        XCTAssertTrue(result.contains("Say {recording}."))
    }
}
