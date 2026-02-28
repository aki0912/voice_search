import Foundation
import Testing

#if canImport(VoiceSearchApp)
@testable import VoiceSearchApp
#elseif canImport(VoiceSearch)
@testable import VoiceSearch
#else
#error("Neither VoiceSearchApp nor VoiceSearch module is available")
#endif

@MainActor
@Suite
struct TranscriptionViewModelRegressionTests {
    @Test
    func basicFlowTranscribeSearchAndJump() async throws {
        let words = [
            TranscriptWord(text: "alpha", startTime: 0.0, endTime: 0.4),
            TranscriptWord(text: "beta", startTime: 0.5, endTime: 0.9),
            TranscriptWord(text: "gamma", startTime: 1.0, endTime: 1.5),
        ]
        let supportDir = makeTempDirectory()
        let viewModel = TranscriptionViewModel(
            appSupportDirectory: supportDir,
            transcriptionServiceFactory: { _ in
                StubTranscriptionService(words: words, duration: 2.0, diagnostics: [])
            }
        )
        let mediaURL = try makeTempMediaURL(ext: "m4a")

        await viewModel.transcribe(url: mediaURL)
        #expect(viewModel.sourceURL == mediaURL)
        #expect(viewModel.transcript.count == 3)
        #expect(!viewModel.displayTranscript.isEmpty)
        #expect(viewModel.analysisProgress == 1.0)

        viewModel.query = "beta"
        viewModel.performSearch()
        #expect(viewModel.searchHits.count == 1)

        let hit = viewModel.searchHits[0]
        viewModel.jump(to: hit)
        #expect(abs(viewModel.currentTime - hit.startTime) < 0.001)
        #expect(viewModel.isPlaying)
        #expect(viewModel.highlightedIndex == hit.startIndex)
    }

    @Test
    func dictionaryAddAndRemoveImmediatelyAffectsSearch() async throws {
        let words = [
            TranscriptWord(text: "アップル", startTime: 0.0, endTime: 0.6),
        ]
        let supportDir = makeTempDirectory()
        let viewModel = TranscriptionViewModel(
            appSupportDirectory: supportDir,
            transcriptionServiceFactory: { _ in
                StubTranscriptionService(words: words, duration: 1.0, diagnostics: [])
            }
        )
        let mediaURL = try makeTempMediaURL(ext: "m4a")

        await viewModel.transcribe(url: mediaURL)
        viewModel.query = "りんご"
        viewModel.performSearch()
        #expect(viewModel.searchHits.isEmpty)

        let added = viewModel.addDictionaryEntry(canonical: "アップル", aliasesText: "りんご")
        #expect(added)
        #expect(viewModel.searchHits.count == 1)
        #expect(viewModel.searchHits[0].displayText == "アップル")

        viewModel.removeDictionaryEntry(UserDictionaryEntry(canonical: "アップル", aliases: ["りんご"]))
        #expect(viewModel.searchHits.isEmpty)
    }

    @Test
    func transcriptionFailureClearsStateAndPersistsFailureLog() async throws {
        let words = [
            TranscriptWord(text: "ready", startTime: 0.0, endTime: 0.5),
        ]
        let supportDir = makeTempDirectory()
        let failureLogURL = supportDir.appendingPathComponent("failure.log")
        let writer = RecordingFailureLogWriter(returnURL: failureLogURL)
        let viewModel = TranscriptionViewModel(
            appSupportDirectory: supportDir,
            failureLogWriter: writer,
            transcriptionServiceFactory: { _ in
                StubTranscriptionService(words: words, duration: 1.0, diagnostics: [])
            }
        )

        let validMedia = try makeTempMediaURL(ext: "m4a")
        await viewModel.transcribe(url: validMedia)
        viewModel.query = "ready"
        viewModel.performSearch()
        #expect(!viewModel.searchHits.isEmpty)

        let unsupportedMedia = try makeTempMediaURL(ext: "txt")
        await viewModel.transcribe(url: unsupportedMedia)

        #expect(viewModel.transcript.isEmpty)
        #expect(viewModel.displayTranscript.isEmpty)
        #expect(viewModel.searchHits.isEmpty)
        #expect(viewModel.currentTime == 0)
        #expect(viewModel.sourceDuration == 0)
        #expect(viewModel.scrubPosition == 0)
        #expect(!viewModel.isPlaying)
        #expect(!viewModel.isAnalyzing)
        #expect(writer.entries.count == 1)
        #expect(viewModel.errorMessage != nil)
    }

    @Test
    func exportFormattingProducesTxtAndSrtContent() async throws {
        let words = [
            TranscriptWord(text: "hello", startTime: 0.0, endTime: 0.5),
            TranscriptWord(text: "world", startTime: 3.0, endTime: 3.4),
        ]
        let supportDir = makeTempDirectory()
        let viewModel = TranscriptionViewModel(
            appSupportDirectory: supportDir,
            transcriptionServiceFactory: { _ in
                StubTranscriptionService(words: words, duration: 4.0, diagnostics: [])
            }
        )
        let mediaURL = try makeTempMediaURL(ext: "m4a")
        await viewModel.transcribe(url: mediaURL)

        let txt = viewModel.transcriptTextContentForTesting(format: .txt)
        #expect(txt.contains("[00:00.000 - 00:00.500] hello"))
        #expect(txt.contains("[00:03.000 - 00:03.399] world"))

        let srt = viewModel.transcriptTextContentForTesting(format: .srt)
        #expect(srt.contains("1\n00:00:00,000 --> 00:00:00,500\nhello"))
        #expect(srt.contains("2\n00:00:03,000 --> 00:00:03,399\nworld"))
    }

    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempMediaURL(ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try Data().write(to: url)
        return url
    }
}

private struct StubTranscriptionService: TranscriptionService {
    let words: [TranscriptWord]
    let duration: TimeInterval?
    let diagnostics: [String]

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        request.progressHandler?(TranscriptionProgress(fractionCompleted: 0.35))
        request.progressHandler?(TranscriptionProgress(fractionCompleted: 0.85))
        return TranscriptionOutput(
            sourceURL: request.sourceURL,
            words: words,
            locale: request.locale,
            duration: duration,
            diagnostics: diagnostics
        )
    }
}

private final class RecordingFailureLogWriter: TranscriptionFailureLogWriting {
    let returnURL: URL
    private(set) var entries: [TranscriptionFailureLogEntry] = []

    init(returnURL: URL) {
        self.returnURL = returnURL
    }

    func write(_ entry: TranscriptionFailureLogEntry) throws -> URL {
        entries.append(entry)
        return returnURL
    }
}
