import Foundation
import Testing
@testable import VoiceSearchCore

@Suite
struct TranscriptionFailureMessageFormatterTests {
    @Test
    func includesUnderlyingCauseWhenAvailable() {
        let formatter = TranscriptionFailureMessageFormatter()
        let underlying = NSError(
            domain: "Test",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "underlying cause"]
        )
        let error = NSError(
            domain: "Test",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "top level",
                NSLocalizedFailureReasonErrorKey: "failed reason",
                NSUnderlyingErrorKey: underlying,
            ]
        )

        let message = formatter.format(modeLabel: "オンデバイス", error: error)
        #expect(message.contains("文字起こしに失敗（オンデバイス）: top level"))
        #expect(message.contains("原因: failed reason"))
    }

    @Test
    func addsPermissionHintForAuthorizationErrors() {
        let formatter = TranscriptionFailureMessageFormatter()
        let error = NSError(
            domain: "Test",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "not authorized"]
        )

        let message = formatter.format(modeLabel: "サーバー", error: error)
        #expect(message.contains("対処:"))
        #expect(message.contains("音声認識"))
    }

    @Test
    func doesNotDuplicateCauseWhenSameAsPrimary() {
        let formatter = TranscriptionFailureMessageFormatter()
        let error = NSError(
            domain: "Test",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "same",
                NSLocalizedFailureReasonErrorKey: "same",
            ]
        )

        let message = formatter.format(modeLabel: "オンデバイス", error: error)
        #expect(!message.contains("\n原因:"))
    }
}
