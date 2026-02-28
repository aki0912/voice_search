import Foundation
import Testing

#if canImport(VoiceSearchApp)
@testable import VoiceSearchApp
#elseif canImport(VoiceSearch)
@testable import VoiceSearch
#else
#error("Neither VoiceSearchApp nor VoiceSearch module is available")
#endif

@Suite
struct SearchRegressionTests {
    @Test
    func containsModeMatchesPartialWordButExactDoesNot() {
        let words = [
            TranscriptWord(text: "recognition", startTime: 0.0, endTime: 0.5),
        ]
        let service = TranscriptSearchService()

        let containsHits = service.search(
            words: words,
            query: "cog",
            options: SearchOptions(mode: .contains)
        )
        #expect(containsHits.count == 1)

        let exactHits = service.search(
            words: words,
            query: "cog",
            options: SearchOptions(mode: .exact)
        )
        #expect(exactHits.isEmpty)
    }

    @Test
    func phraseMatchReturnsPhraseBoundaryAndRange() {
        let words = [
            TranscriptWord(text: "hello", startTime: 0.0, endTime: 0.2),
            TranscriptWord(text: "swift", startTime: 0.3, endTime: 0.6),
            TranscriptWord(text: "world", startTime: 0.7, endTime: 1.0),
        ]
        let service = TranscriptSearchService()

        let hits = service.search(
            words: words,
            query: "swift world",
            options: SearchOptions(mode: .exact)
        )

        #expect(hits.count == 1)
        #expect(hits[0].startIndex == 1)
        #expect(hits[0].endIndex == 2)
        #expect(hits[0].startTime == 0.3)
        #expect(hits[0].endTime == 1.0)
        #expect(hits[0].displayText == "swift world")
    }

    @Test
    func dictionaryEntryAllowsAliasToMatchCanonicalWord() {
        let words = [
            TranscriptWord(text: "アップル", startTime: 0.0, endTime: 0.6),
        ]
        var dictionary = UserDictionary()
        dictionary.insert(
            UserDictionaryEntry(
                canonical: "アップル",
                aliases: ["りんご"]
            )
        )

        let service = TranscriptSearchService(dictionary: dictionary)
        let hits = service.search(
            words: words,
            query: "りんご",
            options: SearchOptions(mode: .exact)
        )

        #expect(hits.count == 1)
        #expect(hits[0].displayText == "アップル")
    }

    @Test
    func maxResultsLimitsSingleTokenMatches() {
        let words = [
            TranscriptWord(text: "swift", startTime: 0.0, endTime: 0.2),
            TranscriptWord(text: "swift", startTime: 0.3, endTime: 0.5),
            TranscriptWord(text: "swift", startTime: 0.6, endTime: 0.8),
        ]
        let service = TranscriptSearchService()

        let hits = service.search(
            words: words,
            query: "swift",
            options: SearchOptions(maxResults: 2, mode: .exact)
        )

        #expect(hits.count == 2)
        #expect(hits[0].startIndex == 0)
        #expect(hits[1].startIndex == 1)
    }

    @Test
    func maxResultsLimitsPhraseMatches() {
        let words = [
            TranscriptWord(text: "swift", startTime: 0.0, endTime: 0.2),
            TranscriptWord(text: "world", startTime: 0.3, endTime: 0.5),
            TranscriptWord(text: "swift", startTime: 0.6, endTime: 0.8),
            TranscriptWord(text: "world", startTime: 0.9, endTime: 1.1),
        ]
        let service = TranscriptSearchService()

        let hits = service.search(
            words: words,
            query: "swift world",
            options: SearchOptions(maxResults: 1, mode: .exact)
        )

        #expect(hits.count == 1)
        #expect(hits[0].startIndex == 0)
        #expect(hits[0].endIndex == 1)
    }
}
