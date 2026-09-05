import AVFAudio
import Foundation
@preconcurrency import Speech

public enum TranscriptionModelAvailability: Equatable, Sendable {
    case checking
    case available
    case downloadable
    case installing
    case unsupported
    case automaticInstallationUnavailable
}

protocol SpeechModelManaging: Sendable {
    func availability(localeIdentifier: String?) async -> TranscriptionModelAvailability
    func availabilityFollowingDownload(
        localeIdentifier: String?
    ) async -> TranscriptionModelAvailability
    func install(localeIdentifier: String?) async throws -> TranscriptionModelAvailability
    func transcribeRecording(at fileURL: URL, localeIdentifier: String?) async throws -> Transcript
}

actor SpeechModelManager: SpeechModelManaging {
    func availability(localeIdentifier: String?) async -> TranscriptionModelAvailability {
        guard #available(macOS 26.0, *) else {
            return .automaticInstallationUnavailable
        }
        guard let transcriber = await transcriber(localeIdentifier: localeIdentifier) else {
            return .unsupported
        }
        switch await SpeechAssetPreparation.status(for: transcriber) {
        case .installed: return .available
        case .supported: return .downloadable
        case .downloading: return .installing
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    func install(localeIdentifier: String?) async throws -> TranscriptionModelAvailability {
        guard #available(macOS 26.0, *) else {
            return .automaticInstallationUnavailable
        }
        guard let transcriber = await transcriber(localeIdentifier: localeIdentifier) else {
            return .unsupported
        }
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else {
            return await availabilityFollowingDownload(localeIdentifier: localeIdentifier)
        }
        try await request.downloadAndInstall()
        return await availabilityFollowingDownload(localeIdentifier: localeIdentifier)
    }

    func availabilityFollowingDownload(
        localeIdentifier: String?
    ) async -> TranscriptionModelAvailability {
        while !Task.isCancelled {
            let status = await availability(localeIdentifier: localeIdentifier)
            guard status == .installing else { return status }
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return .installing
            }
        }
        return .installing
    }

    func transcribeRecording(
        at fileURL: URL,
        localeIdentifier: String?
    ) async throws -> Transcript {
        guard #available(macOS 26.0, *),
              let transcriber = await transcriber(localeIdentifier: localeIdentifier) else {
            throw OnDeviceSpeechTranscriberError.recognizerUnavailable
        }
        guard await SpeechAssetPreparation.status(for: transcriber) == .installed else {
            throw OnDeviceSpeechTranscriberError.onDeviceRecognitionUnavailable
        }

        let audioFile = try AVAudioFile(forReading: fileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let collectedSegments = Self.collectFinalSegments(from: transcriber)
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            return Transcript(segments: try await collectedSegments)
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    @available(macOS 26.0, *)
    private func transcriber(localeIdentifier: String?) async -> SpeechTranscriber? {
        let requestedLocale = Locale(
            identifier: localeIdentifier ?? Locale.autoupdatingCurrent.identifier
        )
        guard SpeechTranscriber.isAvailable,
              let supportedLocale = await SpeechTranscriber.supportedLocale(
                equivalentTo: requestedLocale
              ) else {
            return nil
        }
        return SpeechTranscriber(
            locale: supportedLocale,
            preset: .timeIndexedProgressiveTranscription
        )
    }

    @available(macOS 26.0, *)
    private static func collectFinalSegments(
        from transcriber: SpeechTranscriber
    ) async throws -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        for try await result in transcriber.results where result.isFinal {
            let text = String(result.text.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = result.range.start.seconds
            let duration = result.range.duration.seconds
            segments.append(TranscriptSegment(
                startTime: start.isFinite ? max(0, start) : 0,
                duration: duration.isFinite ? max(0, duration) : 0,
                text: text
            ))
        }
        return segments
    }
}

@available(macOS 26.0, *)
enum SpeechAssetPreparation {
    static func status(for transcriber: SpeechTranscriber) async -> AssetInventory.Status {
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status == .supported else { return status }

        let installedLocales = await SpeechTranscriber.installedLocales
        guard installedLocalesCover(
            selected: transcriber.selectedLocales,
            installed: installedLocales
        ) else {
            return status
        }

        guard await speechLocaleReservationCoordinator.prepare(
            selectedLocales: transcriber.selectedLocales
        ) else {
            return status
        }

        return await AssetInventory.status(forModules: [transcriber])
    }

    static func installedLocalesCover(
        selected: [Locale],
        installed: [Locale]
    ) -> Bool {
        guard !selected.isEmpty else { return false }
        let installedIdentifiers = Set(installed.map(\.identifier))
        return selected.allSatisfy { installedIdentifiers.contains($0.identifier) }
    }
}

@available(macOS 26.0, *)
private let speechLocaleReservationCoordinator = SpeechLocaleReservationCoordinator()

@available(macOS 26.0, *)
private actor SpeechLocaleReservationCoordinator {
    func prepare(selectedLocales: [Locale]) async -> Bool {
        let selectedIdentifiers = Set(selectedLocales.map(\.identifier))
        let reservedLocales = await AssetInventory.reservedLocales

        for locale in reservedLocales where !selectedIdentifiers.contains(locale.identifier) {
            _ = await AssetInventory.release(reservedLocale: locale)
        }

        let retainedIdentifiers = Set(
            reservedLocales
                .filter { selectedIdentifiers.contains($0.identifier) }
                .map(\.identifier)
        )
        do {
            for locale in selectedLocales where !retainedIdentifiers.contains(locale.identifier) {
                guard try await AssetInventory.reserve(locale: locale) else { return false }
            }
            return true
        } catch {
            return false
        }
    }
}
