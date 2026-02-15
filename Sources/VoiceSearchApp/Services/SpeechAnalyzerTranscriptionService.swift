import AVFoundation
import Foundation
import NaturalLanguage
import Speech
import VoiceSearchCore

public enum SpeechAnalyzerTranscriptionError: Error {
    case unavailable
    case unsupportedLocale(String)
    case invalidInput(String)
    case assetInstallFailed(String)
}

extension SpeechAnalyzerTranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "SpeechAnalyzer がこの環境で利用できません。"
        case let .unsupportedLocale(identifier):
            return "SpeechAnalyzer がロケール \(identifier) をサポートしていません。"
        case let .invalidInput(message):
            return message
        case let .assetInstallFailed(message):
            return "音声認識アセットの準備に失敗しました: \(message)"
        }
    }
}

public final class SpeechAnalyzerTranscriptionService: NSObject, @unchecked Sendable, TranscriptionService {
    public override init() { }

    public static var isAvailable: Bool {
        if #available(macOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }

    public func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        guard request.sourceURL.isFileURL else {
            throw TranscriptionServiceError.invalidInput("Unsupported source: not a file URL")
        }
        guard Self.isAvailable else {
            throw SpeechAnalyzerTranscriptionError.unavailable
        }

        if #available(macOS 26.0, *) {
            return try await transcribeWithSpeechAnalyzer(request: request)
        }
        throw SpeechAnalyzerTranscriptionError.unavailable
    }

    @available(macOS 26.0, *)
    private func transcribeWithSpeechAnalyzer(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        let locale = request.locale ?? .current

        let supportedLocales = await SpeechTranscriber.supportedLocales
        guard supportedLocales.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw SpeechAnalyzerTranscriptionError.unsupportedLocale(locale.identifier)
        }

        for reservedLocale in await AssetInventory.reservedLocales {
            await AssetInventory.release(reservedLocale: reservedLocale)
        }
        try await AssetInventory.reserve(locale: locale)

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        let modules: [any SpeechModule] = [transcriber]

        let installedLocales = await SpeechTranscriber.installedLocales
        if !installedLocales.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            do {
                if let installRequest = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                    try await installRequest.downloadAndInstall()
                }
            } catch {
                throw SpeechAnalyzerTranscriptionError.assetInstallFailed(error.localizedDescription)
            }
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: request.sourceURL)
        } catch {
            throw SpeechAnalyzerTranscriptionError.invalidInput("音声ファイルを開けませんでした: \(error.localizedDescription)")
        }

        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        let analyzer = SpeechAnalyzer(modules: modules)
        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        } catch {
            throw SpeechAnalyzerTranscriptionError.invalidInput("SpeechAnalyzer の開始に失敗: \(error.localizedDescription)")
        }

        var transcript = AttributedString()
        var finalizationTime: TimeInterval = 0
        for try await result in transcriber.results {
            transcript += result.text
            finalizationTime = max(finalizationTime, result.resultsFinalizationTime.seconds)

            if duration.isFinite, duration > 0 {
                let progress = max(0.01, min(0.99, result.resultsFinalizationTime.seconds / duration))
                request.progressHandler?(
                    TranscriptionProgress(
                        fractionCompleted: progress,
                        recognizedDuration: result.resultsFinalizationTime.seconds,
                        totalDuration: duration
                    )
                )
            }
        }

        request.progressHandler?(
            TranscriptionProgress(
                fractionCompleted: 1,
                recognizedDuration: duration.isFinite ? duration : finalizationTime,
                totalDuration: duration.isFinite ? duration : nil
            )
        )

        let words = transcript.transcriptWords()

        return TranscriptionOutput(
            sourceURL: request.sourceURL,
            words: words,
            locale: locale,
            duration: duration.isFinite ? duration : nil,
            diagnostics: [
                "recognitionMode: onDeviceSpeechAnalyzer",
                "speechAnalyzerLocale: \(locale.identifier)",
                "speechAnalyzerFinalizationTimeSeconds: \(finalizationTime)",
                "segments: \(words.count)",
            ]
        )
    }
}

@available(macOS 26.0, *)
private extension AttributedString {
    func transcriptWords() -> [TranscriptWord] {
        struct TimedCharacter {
            let start: TimeInterval
            let end: TimeInterval
        }

        var composedText = ""
        var timedCharacters: [TimedCharacter] = []
        for run in runs {
            let raw = String(self[run.range].characters)
            guard !raw.isEmpty else { continue }
            guard let timeRange = run.audioTimeRange else { continue }

            let start = max(0, timeRange.start.seconds)
            let end = max(start, timeRange.end.seconds)
            let characters = Array(raw)
            guard !characters.isEmpty else { continue }

            let perCharacter = characters.count == 0 ? 0 : (end - start) / Double(characters.count)
            for (index, character) in characters.enumerated() {
                let charStart = start + (Double(index) * perCharacter)
                let charEnd = index == characters.count - 1 ? end : (charStart + perCharacter)
                composedText.append(character)
                timedCharacters.append(TimedCharacter(start: charStart, end: charEnd))
            }
        }

        guard !composedText.isEmpty else { return [] }

        let tokens = tokenizeWords(from: composedText)
        var words: [TranscriptWord] = []
        for range in tokens {
            let token = String(composedText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }

            let startOffset = composedText.distance(from: composedText.startIndex, to: range.lowerBound)
            let endOffset = composedText.distance(from: composedText.startIndex, to: range.upperBound)
            guard startOffset >= 0, startOffset < timedCharacters.count else { continue }
            guard endOffset > 0, endOffset <= timedCharacters.count else { continue }

            let tokenStart = timedCharacters[startOffset].start
            let tokenEnd = timedCharacters[endOffset - 1].end
            words.append(TranscriptWord(text: token, startTime: tokenStart, endTime: tokenEnd))
        }

        if words.isEmpty {
            if let first = timedCharacters.first, let last = timedCharacters.last {
                return [TranscriptWord(text: composedText, startTime: first.start, endTime: last.end)]
            }
            return []
        }

        return words.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }
    }

    private func tokenizeWords(from text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        let ranges = tokenizer.tokens(for: text.startIndex..<text.endIndex).filter { range in
            !String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if !ranges.isEmpty {
            return ranges
        }

        return [text.startIndex..<text.endIndex]
    }
}
