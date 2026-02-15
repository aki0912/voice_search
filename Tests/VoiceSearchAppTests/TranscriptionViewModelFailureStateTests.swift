import Foundation
import Testing
@testable import VoiceSearchApp
@testable import VoiceSearchCore

private final class StubFailureLogWriter: TranscriptionFailureLogWriting {
    private(set) var entries: [TranscriptionFailureLogEntry] = []
    let returnedURL: URL

    init(returnedURL: URL) {
        self.returnedURL = returnedURL
    }

    func write(_ entry: TranscriptionFailureLogEntry) throws -> URL {
        entries.append(entry)
        return returnedURL
    }
}

@Suite
struct TranscriptionViewModelFailureStateTests {
    @MainActor
    @Test
    func transcribeFailureClearsPlaybackAndSearchState() async {
        let viewModel = TranscriptionViewModel()

        viewModel.transcript = [
            TranscriptWord(text: "hello", startTime: 0, endTime: 0.5),
            TranscriptWord(text: "world", startTime: 0.6, endTime: 1.2),
        ]
        viewModel.searchHits = [
            SearchHit(
                startIndex: 0,
                endIndex: 0,
                startTime: 0,
                endTime: 0.5,
                matchedText: "hello",
                displayText: "hello"
            ),
        ]
        viewModel.highlightedIndex = 1
        viewModel.currentTime = 42
        viewModel.sourceDuration = 120
        viewModel.scrubPosition = 73
        viewModel.errorMessage = nil

        await viewModel.transcribe(url: URL(fileURLWithPath: "/tmp/unsupported_input.txt"))

        #expect(viewModel.transcript.isEmpty)
        #expect(viewModel.searchHits.isEmpty)
        #expect(viewModel.highlightedIndex == nil)
        #expect(viewModel.currentTime == 0)
        #expect(viewModel.sourceDuration == 0)
        #expect(viewModel.scrubPosition == 0)
        #expect(viewModel.isAnalyzing == false)
        #expect(viewModel.statusText.contains("文字起こしに失敗"))
        #expect(viewModel.errorMessage?.contains("文字起こしに失敗") == true)
    }

    @MainActor
    @Test
    func transcribeFailurePersistsFailureLogAndShowsPath() async {
        let expectedLogURL = URL(fileURLWithPath: "/tmp/voice_search_failure.log")
        let logger = StubFailureLogWriter(returnedURL: expectedLogURL)
        let viewModel = TranscriptionViewModel(failureLogWriter: logger)
        viewModel.query = "debug query"
        viewModel.isContainsMatchMode = true

        await viewModel.transcribe(url: URL(fileURLWithPath: "/tmp/unsupported_input.txt"))

        #expect(logger.entries.count == 1)
        let entry = logger.entries[0]
        #expect(entry.sourceURL.path == "/tmp/unsupported_input.txt")
        #expect(entry.query == "debug query")
        #expect(entry.containsMatchEnabled == true)
        #expect(viewModel.errorMessage?.contains("ログ: /tmp/voice_search_failure.log") == true)
    }

    @MainActor
    @Test
    func displayContextTextPrefersLineContainingMatchedWord() {
        let viewModel = TranscriptionViewModel()
        viewModel.displayTranscript = [
            TranscriptWord(text: "おはようございます", startTime: 0.0, endTime: 1.0),
            TranscriptWord(text: "本日の議題です", startTime: 1.2, endTime: 2.5),
        ]

        let hit = SearchHit(
            startIndex: 3,
            endIndex: 3,
            startTime: 1.01,
            endTime: 1.01,
            matchedText: "議題",
            displayText: "議題"
        )

        #expect(viewModel.displayContextText(for: hit) == "本日の議題です")
    }

    @MainActor
    @Test
    func displayContextTextFallsBackToMatchedWordWhenNoLineContainsIt() {
        let viewModel = TranscriptionViewModel()
        viewModel.displayTranscript = [
            TranscriptWord(text: "おはようございます", startTime: 0.0, endTime: 1.0),
            TranscriptWord(text: "本日の会議です", startTime: 1.2, endTime: 2.5),
        ]

        let hit = SearchHit(
            startIndex: 4,
            endIndex: 4,
            startTime: 2.9,
            endTime: 3.1,
            matchedText: "テスト",
            displayText: "テスト"
        )

        #expect(viewModel.displayContextText(for: hit) == "テスト")
    }

    @MainActor
    @Test
    func updateScrubPositionClampsWithinSourceDuration() {
        let viewModel = TranscriptionViewModel()
        viewModel.sourceDuration = 3600

        viewModel.updateScrubPosition(3900)
        #expect(viewModel.scrubPosition == 3600)
        #expect(viewModel.currentTime == 3600)

        viewModel.updateScrubPosition(-12)
        #expect(viewModel.scrubPosition == 0)
        #expect(viewModel.currentTime == 0)

        viewModel.updateScrubPosition(.nan)
        #expect(viewModel.scrubPosition == 0)
        #expect(viewModel.currentTime == 0)
    }
}
