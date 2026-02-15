import Foundation
import Testing
@testable import VoiceSearchServices

@Suite
struct AudioInputPreparerTests {
    @Test
    func extractionRuleForSingleAudioOnlyFile() {
        #expect(
            AudioInputPreparer.requiresExtraction(
                fileExtension: "m4a",
                audioTrackCount: 1,
                hasVideoTrack: false
            ) == false
        )
    }

    @Test
    func extractionRuleForVideoOrMultiTrackOrUnknownExtension() {
        #expect(
            AudioInputPreparer.requiresExtraction(
                fileExtension: "mov",
                audioTrackCount: 1,
                hasVideoTrack: true
            )
        )

        #expect(
            AudioInputPreparer.requiresExtraction(
                fileExtension: "m4a",
                audioTrackCount: 2,
                hasVideoTrack: false
            )
        )

        #expect(
            AudioInputPreparer.requiresExtraction(
                fileExtension: "bin",
                audioTrackCount: 1,
                hasVideoTrack: false
            )
        )
    }

    @Test
    func prioritizeTrackCandidatesUsesStartThenDurationThenPreferredSubtype() {
        let candidates = [
            AudioTrackCandidate(trackID: 11, startTime: 5.0, duration: 90.0, isPreferredSubtype: true),
            AudioTrackCandidate(trackID: 20, startTime: 0.0, duration: 20.0, isPreferredSubtype: false),
            AudioTrackCandidate(trackID: 31, startTime: 0.0, duration: 40.0, isPreferredSubtype: false),
            AudioTrackCandidate(trackID: 30, startTime: 0.0, duration: 40.0, isPreferredSubtype: true),
        ]

        let prioritized = AudioInputPreparer.prioritizeTrackCandidates(candidates)
        #expect(prioritized.map(\.trackID) == [30, 31, 20, 11])
    }
}
