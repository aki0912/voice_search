import Foundation
import Testing
@testable import VoiceSearchApp
@testable import VoiceSearchCore

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
        viewModel.errorMessage = nil

        await viewModel.transcribe(url: URL(fileURLWithPath: "/tmp/unsupported_input.txt"))

        #expect(viewModel.transcript.isEmpty)
        #expect(viewModel.searchHits.isEmpty)
        #expect(viewModel.highlightedIndex == nil)
        #expect(viewModel.currentTime == 0)
        #expect(viewModel.isAnalyzing == false)
        #expect(viewModel.statusText.contains("文字起こしに失敗"))
        #expect(viewModel.errorMessage?.contains("文字起こしに失敗") == true)
    }
}
