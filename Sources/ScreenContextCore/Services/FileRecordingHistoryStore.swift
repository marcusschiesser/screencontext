import Foundation

public protocol RecordingHistoryStore: Sendable {
    func load() async throws -> RecordingHistorySnapshot
    func save(_ snapshot: RecordingHistorySnapshot) async throws
    func delete(_ recording: RecordingHistoryEntry) async throws
}

public enum RecordingStorage {
    public static func recordingsDirectory(fileManager: FileManager = .default) -> URL {
        // Keep the on-disk location stable across the ScreenContext rename.
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ContextCast", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }
}

public actor FileRecordingHistoryStore: RecordingHistoryStore {
    private static let catalogFileName = "recording-history.json"
    private let fileManager: FileManager
    private let recordingsDirectory: URL

    public init(
        recordingsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.recordingsDirectory = recordingsDirectory
            ?? RecordingStorage.recordingsDirectory(fileManager: fileManager)
    }

    public func load() throws -> RecordingHistorySnapshot {
        try fileManager.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )

        var catalog = try loadCatalog()
        let knownDirectories = Set(catalog.recordings.map(\.directoryName))
        let discovered = try discoverRecordings(excluding: knownDirectories)
        if !discovered.isEmpty {
            catalog.recordings.append(contentsOf: discovered)
        }

        catalog.recordings = catalog.recordings.filter { stored in
            Self.isSafePathComponent(stored.directoryName)
                && Self.isSafePathComponent(stored.recordingFileName)
                && fileManager.fileExists(atPath: recordingURL(for: stored).path)
        }
        catalog.recordings.sort { recordingDate(for: $0) < recordingDate(for: $1) }

        let validIDs = Set(catalog.recordings.map(\.id))
        if let selectedID = catalog.selectedRecordingID,
           !validIDs.contains(selectedID) {
            catalog.selectedRecordingID = catalog.recordings.last?.id
        } else if catalog.selectedRecordingID == nil {
            catalog.selectedRecordingID = catalog.recordings.last?.id
        }

        if !discovered.isEmpty {
            try writeCatalog(catalog)
        }

        return RecordingHistorySnapshot(
            recordings: catalog.recordings.map(makeEntry),
            selectedRecordingID: catalog.selectedRecordingID
        )
    }

    public func save(_ snapshot: RecordingHistorySnapshot) throws {
        try fileManager.createDirectory(
            at: recordingsDirectory,
            withIntermediateDirectories: true
        )
        let storedRecordings = snapshot.recordings.compactMap(makeStoredRecording)
        let validIDs = Set(storedRecordings.map(\.id))
        let selectedID = snapshot.selectedRecordingID.flatMap { id in
            validIDs.contains(id) ? id : storedRecordings.last?.id
        } ?? storedRecordings.last?.id
        try writeCatalog(StoredCatalog(
            version: 2,
            selectedRecordingID: selectedID,
            recordings: storedRecordings
        ))
    }

    public func delete(_ recording: RecordingHistoryEntry) throws {
        let directory = recording.fileURL.deletingLastPathComponent()
        guard directory.deletingLastPathComponent().standardizedFileURL
            == recordingsDirectory.standardizedFileURL else {
            throw RecordingHistoryError.invalidRecordingLocation
        }
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private var catalogURL: URL {
        recordingsDirectory.appendingPathComponent(Self.catalogFileName)
    }

    private func loadCatalog() throws -> StoredCatalog {
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            return StoredCatalog(version: 2, selectedRecordingID: nil, recordings: [])
        }
        let data = try Data(contentsOf: catalogURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredCatalog.self, from: data)
    }

    private func writeCatalog(_ catalog: StoredCatalog) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(catalog).write(to: catalogURL, options: .atomic)
    }

    private func discoverRecordings(excluding knownDirectories: Set<String>) throws
        -> [StoredRecording] {
        let directories = try fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return try directories.compactMap { directory in
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true,
                  !knownDirectories.contains(directory.lastPathComponent) else {
                return nil
            }
            let recordingURL = directory.appendingPathComponent("recording.mp4")
            guard fileManager.fileExists(atPath: recordingURL.path) else { return nil }
            let keyframes = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map {
                    StoredKeyframe(
                        timestamp: Self.timestamp(
                            fromKeyframeName: $0.deletingPathExtension().lastPathComponent
                        ),
                        fileName: $0.lastPathComponent
                    )
                }
            return StoredRecording(
                id: UUID(),
                directoryName: directory.lastPathComponent,
                recordingFileName: recordingURL.lastPathComponent,
                keyframes: keyframes,
                recordedAt: Self.recordingDate(
                    directoryName: directory.lastPathComponent,
                    recordingURL: recordingURL,
                    fileManager: fileManager
                ),
                requestedTranscription: false,
                transcriptionLocale: TranscriptionLocale(Locale.autoupdatingCurrent),
                transcriptSRT: "",
                transcriptIsAvailable: false
            )
        }
    }

    private func makeStoredRecording(_ entry: RecordingHistoryEntry) -> StoredRecording? {
        let directory = entry.fileURL.deletingLastPathComponent()
        guard directory.deletingLastPathComponent().standardizedFileURL
            == recordingsDirectory.standardizedFileURL else {
            return nil
        }
        return StoredRecording(
            id: entry.id,
            directoryName: directory.lastPathComponent,
            recordingFileName: entry.fileURL.lastPathComponent,
            keyframes: entry.keyframes.map {
                StoredKeyframe(timestamp: $0.timestamp, fileName: $0.fileURL.lastPathComponent)
            },
            recordedAt: entry.recordedAt,
            requestedTranscription: entry.requestedTranscription,
            transcriptionLocale: entry.transcriptionLocale,
            transcriptSRT: entry.transcriptSRT,
            transcriptIsAvailable: entry.transcriptIsAvailable
        )
    }

    private func makeEntry(_ stored: StoredRecording) -> RecordingHistoryEntry {
        let directory = recordingsDirectory.appendingPathComponent(
            stored.directoryName,
            isDirectory: true
        )
        return RecordingHistoryEntry(
            id: stored.id,
            fileURL: directory.appendingPathComponent(stored.recordingFileName),
            keyframes: stored.keyframes.compactMap { keyframe in
                guard Self.isSafePathComponent(keyframe.fileName) else { return nil }
                let fileURL = directory.appendingPathComponent(keyframe.fileName)
                guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
                return RecordingKeyframe(timestamp: keyframe.timestamp, fileURL: fileURL)
            },
            recordedAt: recordingDate(for: stored),
            requestedTranscription: stored.requestedTranscription,
            transcriptionLocale: stored.transcriptionLocale,
            transcriptSRT: stored.transcriptSRT,
            transcriptIsAvailable: stored.transcriptIsAvailable
        )
    }

    private func recordingURL(for stored: StoredRecording) -> URL {
        recordingsDirectory
            .appendingPathComponent(stored.directoryName, isDirectory: true)
            .appendingPathComponent(stored.recordingFileName)
    }

    private func recordingDate(for stored: StoredRecording) -> Date {
        stored.recordedAt ?? Self.recordingDate(
            directoryName: stored.directoryName,
            recordingURL: recordingURL(for: stored),
            fileManager: fileManager
        )
    }

    private static func recordingDate(
        directoryName: String,
        recordingURL: URL,
        fileManager: FileManager
    ) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Existing recordings retain their original names, including collision suffixes.
        for prefix in ["ScreenContext", "ContextCast"] {
            let timestampLength = "\(prefix) 0000-00-00 00-00-00".count
            let timestamp = String(directoryName.prefix(timestampLength))
            formatter.dateFormat = "'\(prefix)' yyyy-MM-dd HH-mm-ss"
            if let date = formatter.date(from: timestamp) {
                return date
            }
        }
        let values = try? recordingURL.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]
        )
        return values?.creationDate
            ?? values?.contentModificationDate
            ?? Date(timeIntervalSince1970: 0)
    }

    private static func timestamp(fromKeyframeName name: String) -> TimeInterval {
        guard name.hasPrefix("frame-"),
              let seconds = Int(name.dropFirst("frame-".count).prefix { $0.isNumber }) else {
            return 0
        }
        return TimeInterval(seconds)
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains(":")
    }
}

private struct StoredCatalog: Codable {
    let version: Int
    var selectedRecordingID: UUID?
    var recordings: [StoredRecording]
}

private struct StoredRecording: Codable {
    let id: UUID
    let directoryName: String
    let recordingFileName: String
    let keyframes: [StoredKeyframe]
    let recordedAt: Date?
    let requestedTranscription: Bool
    let transcriptionLocale: TranscriptionLocale
    let transcriptSRT: String
    let transcriptIsAvailable: Bool
}

private struct StoredKeyframe: Codable {
    let timestamp: TimeInterval
    let fileName: String
}

actor VolatileRecordingHistoryStore: RecordingHistoryStore {
    private var snapshot = RecordingHistorySnapshot()

    func load() -> RecordingHistorySnapshot { snapshot }
    func save(_ snapshot: RecordingHistorySnapshot) { self.snapshot = snapshot }
    func delete(_ recording: RecordingHistoryEntry) {
        snapshot = RecordingHistorySnapshot(
            recordings: snapshot.recordings.filter { $0.id != recording.id },
            selectedRecordingID: snapshot.selectedRecordingID == recording.id
                ? nil
                : snapshot.selectedRecordingID
        )
    }
}

public enum RecordingHistoryError: Error, LocalizedError, Sendable {
    case invalidRecordingLocation

    public var errorDescription: String? {
        "The recording is outside ScreenContext's sandboxed recordings directory."
    }
}
