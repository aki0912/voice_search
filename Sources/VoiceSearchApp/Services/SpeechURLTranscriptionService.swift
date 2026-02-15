import Foundation
import AVFoundation
import Speech
import VoiceSearchCore

public enum SpeechURLTranscriptionServiceError: Error {
    case notAuthorized
    case unsupportedLocale
    case invalidInput(String)
    case missingPrivacyUsageDescription(String)
}

extension SpeechURLTranscriptionServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "音声認識の権限がありません。システム設定 > プライバシーとセキュリティ > 音声認識で許可してください。"
        case .unsupportedLocale:
            return "このロケールでは音声認識を利用できません。"
        case let .invalidInput(message):
            return message
        case let .missingPrivacyUsageDescription(key):
            return "\(key) が未設定のため音声認識を開始できません。Info.plist に使用目的を設定してください。"
        }
    }
}

public final class SpeechURLTranscriptionService: NSObject, @unchecked Sendable, TranscriptionService {
    public enum RecognitionStrategy: String, Sendable {
        case onDeviceOnly
        case serverOnly
    }

    private let recognitionStrategy: RecognitionStrategy
    private let allowAuthorizationPrompt: Bool

    enum AuthorizationDecision: Equatable, Sendable {
        case proceed
        case reject
        case requestPrompt
    }

    public init(
        recognitionStrategy: RecognitionStrategy = .onDeviceOnly,
        allowAuthorizationPrompt: Bool = true
    ) {
        self.recognitionStrategy = recognitionStrategy
        self.allowAuthorizationPrompt = allowAuthorizationPrompt
        super.init()
    }

    public func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        let url = request.sourceURL
        guard url.isFileURL else {
            throw TranscriptionServiceError.invalidInput("Unsupported source: not a file URL")
        }

        try ensureSpeechRecognitionUsageDescription()

        let locale = request.locale ?? .current
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw SpeechURLTranscriptionServiceError.unsupportedLocale
        }

        try await requestAuthorizationIfNeeded()

        let preparedInput: PreparedAudioInput
        do {
            preparedInput = try await AudioInputPreparer.prepare(from: url)
        } catch let error as AudioInputPreparationError {
            throw SpeechURLTranscriptionServiceError.invalidInput(error.localizedDescription)
        } catch {
            throw SpeechURLTranscriptionServiceError.invalidInput(error.localizedDescription)
        }
        defer {
            if let cleanupURL = preparedInput.cleanupURL {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }

        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let sourceDurationSeconds = duration.map(CMTimeGetSeconds)
        let contextualStrings = Array(request.contextualStrings.prefix(100))
        let progressHandler = request.progressHandler

        var words: [TranscriptWord]
        var diagnostics: [String] = ["recognitionStrategy: \(recognitionStrategy.rawValue)"]

        switch recognitionStrategy {
        case .onDeviceOnly:
            words = try await recognizeWords(
                recognizer: recognizer,
                audioURL: preparedInput.url,
                contextualStrings: contextualStrings,
                requiresOnDeviceRecognition: true,
                sourceDuration: sourceDurationSeconds,
                progressHandler: progressHandler
            )
            diagnostics.append("recognitionMode: onDeviceOnly")
        case .serverOnly:
            words = try await recognizeWords(
                recognizer: recognizer,
                audioURL: preparedInput.url,
                contextualStrings: contextualStrings,
                requiresOnDeviceRecognition: false,
                sourceDuration: sourceDurationSeconds,
                progressHandler: progressHandler
            )
            diagnostics.append("recognitionMode: serverOnly")
        }

        if let sourceDurationSeconds, sourceDurationSeconds.isFinite, sourceDurationSeconds > 0 {
            let coveredDuration = (words.last?.endTime ?? 0) - (words.first?.startTime ?? 0)
            diagnostics.append("sourceDurationSeconds: \(sourceDurationSeconds)")
            diagnostics.append("coveredDurationSeconds: \(coveredDuration)")
        }

        return TranscriptionOutput(
            sourceURL: url,
            words: words,
            locale: locale,
            duration: duration.map(CMTimeGetSeconds),
            diagnostics: diagnostics + [
                "segments: \(words.count)",
                "contextualStrings: \(contextualStrings.count)",
                "recognitionInputExtension: \(preparedInput.url.pathExtension.lowercased())"
            ]
        )
    }

    private func recognizeWords(
        recognizer: SFSpeechRecognizer,
        audioURL: URL,
        contextualStrings: [String],
        requiresOnDeviceRecognition: Bool,
        sourceDuration: TimeInterval?,
        progressHandler: (@Sendable (TranscriptionProgress) -> Void)?
    ) async throws -> [TranscriptWord] {
        let recognitionRequest = SFSpeechURLRecognitionRequest(url: audioURL)
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        recognitionRequest.contextualStrings = contextualStrings

        return try await withCheckedThrowingContinuation { continuation in
            var alreadyReturned = false
            var recognitionTask: SFSpeechRecognitionTask?
            var lastReportedProgress: Double = 0
            var accumulator = OnDeviceRecognitionAccumulator()

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if alreadyReturned { return }

                if let error {
                    alreadyReturned = true
                    recognitionTask?.cancel()
                    recognitionTask = nil
                    continuation.resume(throwing: SpeechURLTranscriptionServiceError.invalidInput(error.localizedDescription))
                    return
                }

                guard let result else { return }
                let currentWords = result.bestTranscription.segments.compactMap { segment -> TranscriptWord? in
                    let text = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                    let start = segment.timestamp
                    let end = segment.timestamp + segment.duration
                    return TranscriptWord(text: text, startTime: start, endTime: end)
                }
                accumulator.ingest(currentWords)

                if let progress = Self.progressFrom(result: result, sourceDuration: sourceDuration),
                   progress > lastReportedProgress {
                    lastReportedProgress = progress
                    progressHandler?(
                        TranscriptionProgress(
                            fractionCompleted: progress,
                            recognizedDuration: result.bestTranscription.segments.last.map { $0.timestamp + $0.duration },
                            totalDuration: sourceDuration
                        )
                    )
                }

                if result.isFinal {
                    alreadyReturned = true
                    let words = accumulator.sortedWords()
                    recognitionTask?.cancel()
                    recognitionTask = nil
                    continuation.resume(returning: words)
                }
            }
        }
    }

    private static func progressFrom(result: SFSpeechRecognitionResult, sourceDuration: TimeInterval?) -> Double? {
        guard let sourceDuration, sourceDuration.isFinite, sourceDuration > 0 else {
            return nil
        }
        guard let last = result.bestTranscription.segments.last else {
            return nil
        }

        let recognizedTime = max(0, last.timestamp + last.duration)
        let raw = recognizedTime / sourceDuration
        // Keep headroom for finalization/normalization.
        return max(0.01, min(0.98, raw * 0.98))
    }

    static func authorizationDecision(
        status: SFSpeechRecognizerAuthorizationStatus,
        allowAuthorizationPrompt: Bool,
        canRequestAuthorizationPrompt: Bool
    ) -> AuthorizationDecision {
        switch status {
        case .authorized:
            return .proceed
        case .denied, .restricted:
            return .reject
        case .notDetermined:
            return (allowAuthorizationPrompt && canRequestAuthorizationPrompt) ? .requestPrompt : .reject
        @unknown default:
            return .reject
        }
    }

    private func requestAuthorizationIfNeeded() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        let canRequestAuthorizationPrompt = Bundle.main.bundleURL.pathExtension == "app"
        switch Self.authorizationDecision(
            status: status,
            allowAuthorizationPrompt: allowAuthorizationPrompt,
            canRequestAuthorizationPrompt: canRequestAuthorizationPrompt
        ) {
        case .proceed:
            return
        case .reject:
            throw SpeechURLTranscriptionServiceError.notAuthorized
        case .requestPrompt:
            let nextStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard nextStatus == .authorized else {
                throw SpeechURLTranscriptionServiceError.notAuthorized
            }
        }
    }

    private func ensureSpeechRecognitionUsageDescription() throws {
        let key = "NSSpeechRecognitionUsageDescription"
        let usage = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let normalized = usage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized.isEmpty {
            throw SpeechURLTranscriptionServiceError.missingPrivacyUsageDescription(key)
        }
    }
}

struct OnDeviceRecognitionAccumulator {
    private var wordsByKey: [String: TranscriptWord] = [:]

    mutating func ingest(_ words: [TranscriptWord]) {
        for word in words where Self.isValid(word) {
            wordsByKey[Self.segmentKey(for: word)] = word
        }
    }

    func sortedWords() -> [TranscriptWord] {
        wordsByKey.values.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }
    }

    static func isValid(_ word: TranscriptWord) -> Bool {
        let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard word.startTime.isFinite, word.endTime.isFinite else { return false }
        guard word.endTime > word.startTime else { return false }
        guard (word.endTime - word.startTime) > 0.02 else { return false }
        return true
    }

    static func segmentKey(for word: TranscriptWord) -> String {
        // Use centisecond buckets to absorb minor timing jitter across partial/final results.
        let start = Int((word.startTime * 100).rounded())
        let end = Int((word.endTime * 100).rounded())
        return "\(start)-\(end)"
    }
}
