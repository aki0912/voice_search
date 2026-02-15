import Foundation
import Testing
@testable import VoiceSearchCore
@testable import VoiceSearchServices

@Suite
struct OnDeviceRecognitionAccumulatorTests {
    @Test
    func mergesPartialResultsAcrossCallbacks() {
        var accumulator = OnDeviceRecognitionAccumulator()

        accumulator.ingest([
            TranscriptWord(text: "hello", startTime: 0.00, endTime: 0.50),
            TranscriptWord(text: "world", startTime: 0.50, endTime: 1.00),
        ])
        accumulator.ingest([
            TranscriptWord(text: "WORLD", startTime: 0.50, endTime: 1.00),
            TranscriptWord(text: "swift", startTime: 1.00, endTime: 1.40),
        ])

        let words = accumulator.sortedWords()
        #expect(words.count == 3)
        #expect(words[0].text == "hello")
        #expect(words[1].text == "WORLD")
        #expect(words[2].text == "swift")
    }

    @Test
    func filtersInvalidSegments() {
        var accumulator = OnDeviceRecognitionAccumulator()
        accumulator.ingest([
            TranscriptWord(text: "valid", startTime: 1.0, endTime: 1.5),
            TranscriptWord(text: "", startTime: 2.0, endTime: 2.5),
            TranscriptWord(text: "short", startTime: 3.0, endTime: 3.01),
            TranscriptWord(text: "reverse", startTime: 4.0, endTime: 3.5),
            TranscriptWord(text: "nan", startTime: .nan, endTime: 5.0),
        ])

        let words = accumulator.sortedWords()
        #expect(words.count == 1)
        #expect(words[0].text == "valid")
    }

    @Test
    func keepsWordsSortedByStartThenEnd() {
        var accumulator = OnDeviceRecognitionAccumulator()
        accumulator.ingest([
            TranscriptWord(text: "third", startTime: 3.0, endTime: 3.5),
            TranscriptWord(text: "first", startTime: 1.0, endTime: 1.5),
            TranscriptWord(text: "second-b", startTime: 2.0, endTime: 2.6),
            TranscriptWord(text: "second-a", startTime: 2.0, endTime: 2.4),
        ])

        let words = accumulator.sortedWords()
        #expect(words.map(\.text) == ["first", "second-a", "second-b", "third"])
    }
}
