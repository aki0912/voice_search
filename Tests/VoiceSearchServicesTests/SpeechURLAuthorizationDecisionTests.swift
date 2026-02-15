import Speech
import Testing
@testable import VoiceSearchServices

@Suite
struct SpeechURLAuthorizationDecisionTests {
    @Test
    func authorizedAlwaysProceeds() {
        #expect(
            SpeechURLTranscriptionService.authorizationDecision(
                status: .authorized,
                allowAuthorizationPrompt: false,
                canRequestAuthorizationPrompt: false
            ) == .proceed
        )
    }

    @Test
    func deniedAndRestrictedAreRejected() {
        #expect(
            SpeechURLTranscriptionService.authorizationDecision(
                status: .denied,
                allowAuthorizationPrompt: true,
                canRequestAuthorizationPrompt: true
            ) == .reject
        )
        #expect(
            SpeechURLTranscriptionService.authorizationDecision(
                status: .restricted,
                allowAuthorizationPrompt: true,
                canRequestAuthorizationPrompt: true
            ) == .reject
        )
    }

    @Test
    func notDeterminedDependsOnPromptFlag() {
        #expect(
            SpeechURLTranscriptionService.authorizationDecision(
                status: .notDetermined,
                allowAuthorizationPrompt: false,
                canRequestAuthorizationPrompt: true
            ) == .reject
        )
        #expect(
            SpeechURLTranscriptionService.authorizationDecision(
                status: .notDetermined,
                allowAuthorizationPrompt: true,
                canRequestAuthorizationPrompt: true
            ) == .requestPrompt
        )
        #expect(
            SpeechURLTranscriptionService.authorizationDecision(
                status: .notDetermined,
                allowAuthorizationPrompt: true,
                canRequestAuthorizationPrompt: false
            ) == .reject
        )
    }
}
