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

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true

        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let words: [TranscriptWord] = try await withCheckedThrowingContinuation { continuation in
            var alreadyReturned = false
            _ = recognizer.recognitionTask(with: request) { result, error in
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
            diagnostics: ["segments: \(words.count)"]
        )
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
