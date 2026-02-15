import Foundation
import VoiceSearchCore

public final class HybridTranscriptionService: NSObject, @unchecked Sendable, TranscriptionService {
    public enum Mode: String, CaseIterable, Sendable {
        case speechAnalyzerFirst
        case speechAnalyzerOnly
        case speechOnly
    }

    private let analyzer: any TranscriptionService
    private let legacy: any TranscriptionService
    private let analyzerAvailability: @Sendable () -> Bool
    public let mode: Mode

    public init(mode: Mode = .speechAnalyzerFirst) {
        self.analyzer = SpeechAnalyzerTranscriptionService()
        self.legacy = SpeechURLTranscriptionService()
        self.mode = mode
        self.analyzerAvailability = { SpeechAnalyzerTranscriptionService.isAvailable }
    }

    init(
        mode: Mode,
        analyzer: any TranscriptionService,
        legacy: any TranscriptionService,
        analyzerAvailability: @escaping @Sendable () -> Bool
    ) {
        self.analyzer = analyzer
        self.legacy = legacy
        self.mode = mode
        self.analyzerAvailability = analyzerAvailability
    }

    public func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        switch mode {
        case .speechOnly:
            return try await legacy.transcribe(request: request)
        case .speechAnalyzerFirst, .speechAnalyzerOnly:
            guard analyzerAvailability() else {
                throw SpeechAnalyzerTranscriptionError.unavailable
            }
            return try await analyzer.transcribe(request: request)
        }
    }
}
