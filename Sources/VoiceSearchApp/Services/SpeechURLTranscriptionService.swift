import Foundation
import AVFoundation
import Speech
import VoiceSearchCore

public enum SpeechURLTranscriptionServiceError: Error {
    case notAuthorized
    case unsupportedLocale
    case invalidInput(String)
}

public final class SpeechURLTranscriptionService: NSObject, @unchecked Sendable, TranscriptionService {
    private struct PreparedRecognitionInput {
        let url: URL
        let cleanupURL: URL?
    }

    public override init() {
        super.init()
    }

    public func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        let url = request.sourceURL
        guard url.isFileURL else {
            throw TranscriptionServiceError.invalidInput("Unsupported source: not a file URL")
        }

        let locale = request.locale ?? .current
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechURLTranscriptionServiceError.unsupportedLocale
        }

        try await requestAuthorizationIfNeeded()

        let preparedInput = try await prepareRecognitionInput(from: url)
        defer {
            if let cleanupURL = preparedInput.cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }

        let recognitionRequest = SFSpeechURLRecognitionRequest(url: preparedInput.url)
        recognitionRequest.shouldReportPartialResults = false
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.contextualStrings = Array(request.contextualStrings.prefix(100))

        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let words: [TranscriptWord] = try await withCheckedThrowingContinuation { continuation in
            var alreadyReturned = false
            _ = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if alreadyReturned { return }

                if let error {
                    alreadyReturned = true
                    continuation.resume(throwing: SpeechURLTranscriptionServiceError.invalidInput(error.localizedDescription))
                    return
                }

                guard let result else { return }
                if result.isFinal {
                    alreadyReturned = true
                    let words = result.bestTranscription.segments.map { segment in
                        TranscriptWord(
                            text: segment.substring.trimmingCharacters(in: .whitespacesAndNewlines),
                            startTime: segment.timestamp,
                            endTime: segment.timestamp + segment.duration
                        )
                    }
                    continuation.resume(returning: words)
                }
            }
        }

        return TranscriptionOutput(
            sourceURL: url,
            words: words,
            locale: locale,
            duration: duration.map(CMTimeGetSeconds),
            diagnostics: [
                "segments: \(words.count)",
                "contextualStrings: \(recognitionRequest.contextualStrings.count)",
                "recognitionInputExtension: \(preparedInput.url.pathExtension.lowercased())"
            ]
        )
    }

    private func prepareRecognitionInput(from sourceURL: URL) async throws -> PreparedRecognitionInput {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw SpeechURLTranscriptionServiceError.invalidInput("No audio track found in input file.")
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let ext = sourceURL.pathExtension.lowercased()
        let audioOnlyExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "aiff", "flac", "ogg", "opus"]
        let shouldExtractAudio = !videoTracks.isEmpty || !audioOnlyExtensions.contains(ext)
        guard shouldExtractAudio else {
            return PreparedRecognitionInput(url: sourceURL, cleanupURL: nil)
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpeechURLTranscriptionServiceError.invalidInput("Failed to create audio extractor for video.")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: tempURL)

        exporter.outputURL = tempURL
        exporter.outputFileType = .m4a

        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: SpeechURLTranscriptionServiceError.invalidInput(exporter.error?.localizedDescription ?? "Audio extraction failed."))
                case .cancelled:
                    continuation.resume(throwing: SpeechURLTranscriptionServiceError.invalidInput("Audio extraction cancelled."))
                default:
                    continuation.resume(throwing: SpeechURLTranscriptionServiceError.invalidInput("Audio extraction did not complete."))
                }
            }
        }

        return PreparedRecognitionInput(url: tempURL, cleanupURL: tempURL)
    }

    private func requestAuthorizationIfNeeded() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return }
        if status == .denied || status == .restricted {
            throw SpeechURLTranscriptionServiceError.notAuthorized
        }

        let nextStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard nextStatus == .authorized else {
            throw SpeechURLTranscriptionServiceError.notAuthorized
        }
    }
}
