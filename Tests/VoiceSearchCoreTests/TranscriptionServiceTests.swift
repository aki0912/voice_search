import Testing
import Foundation
@testable import VoiceSearchCore

@Suite
struct TranscriptionServiceTests {
    struct StubSpeechService: TranscriptionService {
        let response: TranscriptionOutput

        func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
            response
        }
    }

    @Test
    func normalizerRemovesInvalidWordsAndSortsByStart() throws {
        let normalizer = TranscriptWordNormalizer()
        let words = [
            TranscriptWord(text: "  middle  ", startTime: 3.0, endTime: 3.2),
            TranscriptWord(text: "first", startTime: 0.0, endTime: 1.2),
            TranscriptWord(text: "", startTime: 1.5, endTime: 1.8),
            TranscriptWord(text: "late", startTime: 3.4, endTime: -1.0),
            TranscriptWord(text: "early", startTime: 2.5, endTime: 2.9)
        ]

        let result = normalizer.sanitize(words)

        #expect(result.count == 4)
        #expect(result[0].text == "first")
        #expect(result[1].text == "early")
        #expect(result[2].text == "middle")
        #expect(result[3].text == "late")
        #expect(result[3].startTime == 3.4)
        #expect(result[3].endTime == 3.4)
    }

    @Test
    func pipelineRejectsUnsupportedExtension() async throws {
        let request = TranscriptionRequest(sourceURL: URL(fileURLWithPath: "/tmp/example.txt"), locale: nil)
        let pipeline = TranscriptionPipeline()
        let service = StubSpeechService(
            response: TranscriptionOutput(
                sourceURL: request.sourceURL,
                words: []
            )
        )

        await #expect(throws: TranscriptionServiceError.self) {
            _ = try await pipeline.run(request, service: service)
        }
    }

    @Test
    func pipelineSanitizesAndReturnsOutput() async throws {
        let url = URL(fileURLWithPath: "/tmp/recording.wav")
        let request = TranscriptionRequest(sourceURL: url, locale: Locale(identifier: "en-US"))
        let rawOutput = TranscriptionOutput(
            sourceURL: url,
            words: [
                TranscriptWord(text: "  hello ", startTime: 1.2, endTime: 1.6),
                TranscriptWord(text: "world", startTime: 0.0, endTime: 0.5),
            ],
            duration: 3.0
        )
        let service = StubSpeechService(response: rawOutput)
        let pipeline = TranscriptionPipeline()

        let output = try await pipeline.run(request, service: service)

        #expect(output.words.count == 2)
        #expect(output.words[0].text == "world")
        #expect(output.words[1].text == "hello")
        #expect(output.words[0].startTime == 0.0)
        #expect(output.words[1].startTime == 1.2)
        #expect(output.locale?.identifier == "en-US")
        #expect(output.duration == 3.0)
    }
}

