import Foundation
import Testing
@testable import VoiceSearchCore
@testable import VoiceSearchServices

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private struct StubTranscriptionService: TranscriptionService {
    let calls: CallCounter
    let run: @Sendable () async throws -> TranscriptionOutput

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
        calls.increment()
        return try await run()
    }
}

private struct StubAnalyzerError: Error {}

@Suite
struct HybridTranscriptionServiceTests {
    @Test
    func speechAnalyzerFirstDoesNotFallbackWhenAnalyzerUnavailable() async {
        let analyzerCalls = CallCounter()
        let legacyCalls = CallCounter()

        let service = HybridTranscriptionService(
            mode: .speechAnalyzerFirst,
            analyzer: StubTranscriptionService(
                calls: analyzerCalls,
                run: {
                    TranscriptionOutput(sourceURL: URL(fileURLWithPath: "/tmp/a.wav"), words: [])
                }
            ),
            legacy: StubTranscriptionService(
                calls: legacyCalls,
                run: {
                    TranscriptionOutput(sourceURL: URL(fileURLWithPath: "/tmp/b.wav"), words: [])
                }
            ),
            analyzerAvailability: { false }
        )

        await #expect(throws: SpeechAnalyzerTranscriptionError.self) {
            _ = try await service.transcribe(
                request: TranscriptionRequest(sourceURL: URL(fileURLWithPath: "/tmp/input.wav"))
            )
        }
        #expect(analyzerCalls.count == 0)
        #expect(legacyCalls.count == 0)
    }

    @Test
    func speechAnalyzerFirstPropagatesAnalyzerErrorWithoutFallback() async {
        let analyzerCalls = CallCounter()
        let legacyCalls = CallCounter()

        let service = HybridTranscriptionService(
            mode: .speechAnalyzerFirst,
            analyzer: StubTranscriptionService(
                calls: analyzerCalls,
                run: {
                    throw StubAnalyzerError()
                }
            ),
            legacy: StubTranscriptionService(
                calls: legacyCalls,
                run: {
                    TranscriptionOutput(sourceURL: URL(fileURLWithPath: "/tmp/b.wav"), words: [])
                }
            ),
            analyzerAvailability: { true }
        )

        await #expect(throws: StubAnalyzerError.self) {
            _ = try await service.transcribe(
                request: TranscriptionRequest(sourceURL: URL(fileURLWithPath: "/tmp/input.wav"))
            )
        }
        #expect(analyzerCalls.count == 1)
        #expect(legacyCalls.count == 0)
    }

    @Test
    func speechOnlyUsesLegacyServiceOnly() async throws {
        let analyzerCalls = CallCounter()
        let legacyCalls = CallCounter()
        let expected = TranscriptionOutput(
            sourceURL: URL(fileURLWithPath: "/tmp/legacy.wav"),
            words: [TranscriptWord(text: "legacy", startTime: 0, endTime: 0.3)],
            diagnostics: ["recognitionMode: serverOnly"]
        )

        let service = HybridTranscriptionService(
            mode: .speechOnly,
            analyzer: StubTranscriptionService(
                calls: analyzerCalls,
                run: {
                    TranscriptionOutput(sourceURL: URL(fileURLWithPath: "/tmp/analyzer.wav"), words: [])
                }
            ),
            legacy: StubTranscriptionService(
                calls: legacyCalls,
                run: { expected }
            ),
            analyzerAvailability: { true }
        )

        let output = try await service.transcribe(
            request: TranscriptionRequest(sourceURL: URL(fileURLWithPath: "/tmp/input.wav"))
        )

        #expect(output == expected)
        #expect(analyzerCalls.count == 0)
        #expect(legacyCalls.count == 1)
    }
}
