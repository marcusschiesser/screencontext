import Foundation
import XCTest
@testable import ScreenContextCore

final class RecordingContextTests: XCTestCase {
    func testContextContainsOnlyUnescapedFilePath() {
        let url = URL(fileURLWithPath: "/tmp/ScreenContext Demo 日本語/recording.mp4")
        let recording = RecordingResult(fileURL: url)

        XCTAssertEqual(recording.context, "/tmp/ScreenContext Demo 日本語/recording.mp4")
    }

    func testLegacyCatalogsPreserveRecordingIdentityAndSelection() async throws {
        for version in [1, 2] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("screencontext-legacy-\(UUID())", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let directory = root.appendingPathComponent("ScreenContext 2026-09-01 12-00-00")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let video = directory.appendingPathComponent("recording.mp4")
            try Data([1]).write(to: video)
            let legacyImage = directory.appendingPathComponent("frame-0000.png")
            try Data([2]).write(to: legacyImage)
            let id = UUID()
            var entry: [String: Any] = [
                "id": id.uuidString,
                "directoryName": directory.lastPathComponent,
                "recordingFileName": "recording.mp4",
                "keyframes": [["timestamp": 0, "fileName": "frame-0000.png"]],
                "requestedTranscription": true,
                "transcriptionLocale": ["identifier": "de"],
                "transcriptSRT": "Old speech text",
                "transcriptIsAvailable": true,
            ]
            if version == 2 { entry["recordedAt"] = "2026-09-01T10:00:00Z" }
            let catalog: [String: Any] = [
                "version": version,
                "selectedRecordingID": id.uuidString,
                "recordings": [entry],
            ]
            let catalogURL = root.appendingPathComponent("recording-history.json")
            try JSONSerialization.data(withJSONObject: catalog).write(to: catalogURL)
            let store = FileRecordingHistoryStore(recordingsDirectory: root)

            let loaded = try await store.load()

            XCTAssertEqual(loaded.selectedRecordingID, id)
            XCTAssertEqual(loaded.recordings.map(\.id), [id])
            XCTAssertEqual(loaded.recordings.first?.fileURL, video)
            if version == 2 {
                XCTAssertEqual(
                    loaded.recordings.first?.recordedAt,
                    ISO8601DateFormatter().date(from: "2026-09-01T10:00:00Z")
                )
            }
            try await store.save(loaded)
            let reloaded = try await store.load()
            XCTAssertEqual(reloaded, loaded)
            XCTAssertTrue(FileManager.default.fileExists(atPath: video.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyImage.path))

            let saved = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
            )
            let savedEntries = try XCTUnwrap(saved["recordings"] as? [[String: Any]])
            XCTAssertEqual(Set(try XCTUnwrap(savedEntries.first).keys), [
                "id", "directoryName", "recordingFileName", "recordedAt",
            ])
        }
    }
}
