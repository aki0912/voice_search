import Foundation

public struct TranscriptionRequest: Sendable {
    public let sourceURL: URL
    public let locale: Locale?
    public let contextualStrings: [String]

    public init(sourceURL: URL, locale: Locale? = nil, contextualStrings: [String] = []) {
        self.sourceURL = sourceURL
        self.locale = locale
        self.contextualStrings = contextualStrings
    }
}

public struct TranscriptionOutput: Equatable, Sendable {
    public let sourceURL: URL
    public let words: [TranscriptWord]
    public let locale: Locale?
    public let duration: TimeInterval?
    public let diagnostics: [String]

    public init(
        sourceURL: URL,
        words: [TranscriptWord],
        locale: Locale? = nil,
        duration: TimeInterval? = nil,
        diagnostics: [String] = []
    ) {
        self.sourceURL = sourceURL
        self.words = words
        self.locale = locale
        self.duration = duration
        self.diagnostics = diagnostics
    }
}

public enum TranscriptionServiceError: Error, Equatable, Sendable {
    case unsupportedFileType(String)
    case emptyTranscript
    case invalidInput(String)
}

public protocol TranscriptionService: Sendable {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput
}

public struct TranscriptWordNormalizer: Sendable {
    public init() {}

    public func sanitize(_ words: [TranscriptWord]) -> [TranscriptWord] {
        let normalized = words.compactMap { word -> TranscriptWord? in
            let trimmedText = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }
            guard word.startTime.isFinite, word.endTime.isFinite else { return nil }

            let start = max(0.0, word.startTime)
            let end = max(start, word.endTime)
            return TranscriptWord(id: word.id, text: trimmedText, startTime: start, endTime: end)
        }

        return normalized.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }
    }
}

public struct TranscriptionPipeline: Sendable {
    public let acceptedExtensions: Set<String>
    public let wordNormalizer: TranscriptWordNormalizer

    public init(
        acceptedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aac", "aiff", "flac", "ogg", "opus", "mp4", "mov", "m4v", "mkv", "avi", "webm", "ts", "mts"],
        wordNormalizer: TranscriptWordNormalizer = TranscriptWordNormalizer()
    ) {
        self.acceptedExtensions = acceptedExtensions
        self.wordNormalizer = wordNormalizer
    }

    public func run(_ request: TranscriptionRequest, service: TranscriptionService) async throws -> TranscriptionOutput {
        guard isSupported(request.sourceURL) else {
            throw TranscriptionServiceError.unsupportedFileType(request.sourceURL.pathExtension.lowercased())
        }

        let raw = try await service.transcribe(request: request)
        let normalizedWords = wordNormalizer.sanitize(raw.words)

        if normalizedWords.isEmpty {
            throw TranscriptionServiceError.emptyTranscript
        }

        return TranscriptionOutput(
            sourceURL: request.sourceURL,
            words: normalizedWords,
            locale: request.locale ?? raw.locale,
            duration: raw.duration,
            diagnostics: raw.diagnostics
        )
    }

    public func isSupported(_ url: URL) -> Bool {
        acceptedExtensions.contains(url.pathExtension.lowercased())
    }
}
