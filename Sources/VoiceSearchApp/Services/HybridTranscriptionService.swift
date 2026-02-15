import Foundation
import VoiceSearchCore

public final class HybridTranscriptionService: NSObject, @unchecked Sendable, TranscriptionService {
    public enum Mode: String, CaseIterable, Sendable {
        case speechAnalyzerFirst
        case speechAnalyzerOnly
        case speechOnly
    }

    private let analyzer: SpeechAnalyzerTranscriptionService
    private let legacy: SpeechURLTranscriptionService
    public let mode: Mode

    public init(mode: Mode = .speechAnalyzerFirst) {
        self.analyzer = SpeechAnalyzerTranscriptionService()
        self.legacy = SpeechURLTranscriptionService()
        self.mode = mode
    }

    public func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        switch mode {
        case .speechOnly:
            return try await legacy.transcribe(request: request)
        case .speechAnalyzerFirst, .speechAnalyzerOnly:
            guard SpeechAnalyzerTranscriptionService.isAvailable else {
                throw SpeechAnalyzerTranscriptionError.unavailable
            }
            return try await analyzer.transcribe(request: request)
        }
    }
}
