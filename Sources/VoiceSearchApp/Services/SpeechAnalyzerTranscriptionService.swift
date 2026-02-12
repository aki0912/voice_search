import Foundation
import VoiceSearchCore

public enum SpeechAnalyzerTranscriptionError: Error {
    case unavailable
    case invalidInput(String)
    case implementationMissing
}

/// Placeholder adapter for SpeechAnalyzer.
/// The app currently falls back to SFSpeech via HybridTranscriptionService.
public final class SpeechAnalyzerTranscriptionService: NSObject, @unchecked Sendable, TranscriptionService {
    public override init() { }

    public static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    public func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        guard request.sourceURL.isFileURL else {
            throw TranscriptionServiceError.invalidInput("Unsupported source: not a file URL")
        }

        if !Self.isAvailable {
            throw SpeechAnalyzerTranscriptionError.unavailable
        }

        throw SpeechAnalyzerTranscriptionError.implementationMissing
    }
}
