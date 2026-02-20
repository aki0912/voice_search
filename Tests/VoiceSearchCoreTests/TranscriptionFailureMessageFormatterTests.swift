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

        let modeLabel = "on-device"
        let message = formatter.format(modeLabel: modeLabel, error: error)
        #expect(message.contains("\(CoreL10n.format("failure.headline", modeLabel)): top level"))
        #expect(message.contains(CoreL10n.format("failure.cause", "failed reason")))
    }

    @Test
    func addsPermissionHintForAuthorizationErrors() {
        let formatter = TranscriptionFailureMessageFormatter()
        let error = NSError(
            domain: "Test",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "not authorized"]
        )

        let message = formatter.format(modeLabel: "server", error: error)
        #expect(message.contains(CoreL10n.text("failure.hint.authorization")))
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

        let message = formatter.format(modeLabel: "on-device", error: error)
        let causePrefix = CoreL10n.text("failure.cause").replacingOccurrences(of: "%@", with: "")
        #expect(!message.contains("\n\(causePrefix)"))
    }
}
