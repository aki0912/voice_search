import Testing
import Foundation
@testable import VoiceSearchCore

@Suite
struct TranscriptSearchServiceTests {
    @Test
    func exactMatchReturnsTimestamp() throws {
        let words = [
            TranscriptWord(text: "Hello", startTime: 0, endTime: 0.9),
            TranscriptWord(text: "world", startTime: 1.0, endTime: 2.4),
            TranscriptWord(text: "from", startTime: 2.5, endTime: 3.2)
        ]

        let service = TranscriptSearchService()
        let results = service.search(words: words, query: "world")

        #expect(results.count == 1)
        let hit = try #require(results.first)
        #expect(hit.startIndex == 1)
        #expect(hit.endIndex == 1)
        #expect(hit.startTime == 1.0)
        #expect(hit.endTime == 2.4)
    }

    @Test
    func phraseMatchReturnsPhraseBoundaryAndTimeRange() throws {
        let words = [
            TranscriptWord(text: "good", startTime: 0, endTime: 0.9),
            TranscriptWord(text: "morning", startTime: 1.0, endTime: 1.8),
            TranscriptWord(text: "everyone", startTime: 1.9, endTime: 2.6)
        ]

        let service = TranscriptSearchService()
        let results = service.search(words: words, query: "morning everyone")

        #expect(results.count == 1)
        let hit = try #require(results.first)
        #expect(hit.startIndex == 1)
        #expect(hit.endIndex == 2)
        #expect(hit.startTime == 1.0)
        #expect(hit.endTime == 2.6)
        #expect(hit.displayText == "morning everyone")
    }

    @Test
    func dictionaryEntryImprovesMatchForSynonyms() throws {
        var dict = UserDictionary()
        dict.insert(UserDictionaryEntry(canonical: "kyoto", aliases: ["京都", "kyouto"]))
        let service = TranscriptSearchService(dictionary: dict)

        let words = [
            TranscriptWord(text: "kyoto", startTime: 0, endTime: 1.0),
            TranscriptWord(text: "arrived", startTime: 1.2, endTime: 2.1)
        ]

        let resultByAlias = service.search(words: words, query: "京都")
        let resultByExact = service.search(words: words, query: "kyoto")
        #expect(resultByAlias.count == 1)
        #expect(resultByExact.count == 1)
        let aliasHit = try #require(resultByAlias.first)
        #expect(aliasHit.startIndex == 0)
    }

    @Test
    func containsModeMatchesPartialWord() throws {
        let words = [
            TranscriptWord(text: "café", startTime: 0, endTime: 0.8),
            TranscriptWord(text: "noise", startTime: 0.9, endTime: 1.4)
        ]

        let service = TranscriptSearchService()
        let exact = service.search(words: words, query: "cafe")
        let contains = service.search(words: words, query: "cafe", options: SearchOptions(mode: .contains))

        #expect(exact.count == 1)
        #expect(contains.count == 1)
    }

    @Test
    func containsModeDoesNotMatchReverseContainment() throws {
        let words = [
            TranscriptWord(text: "で", startTime: 0, endTime: 0.2),
            TranscriptWord(text: "おはようございます", startTime: 0.3, endTime: 1.2)
        ]

        let service = TranscriptSearchService()
        let contains = service.search(words: words, query: "です", options: SearchOptions(mode: .contains))

        #expect(contains.isEmpty)
    }

    @Test
    func nearestWordIndexFindsClosestWord() throws {
        let words = [
            TranscriptWord(text: "a", startTime: 0.0, endTime: 1.0),
            TranscriptWord(text: "b", startTime: 1.1, endTime: 2.0),
            TranscriptWord(text: "c", startTime: 2.2, endTime: 3.0)
        ]

        #expect(PlaybackLocator.nearestWordIndex(at: -1, in: words) == 0)
        #expect(PlaybackLocator.nearestWordIndex(at: 1.5, in: words) == 1)
        #expect(PlaybackLocator.nearestWordIndex(at: 2.6, in: words) == 2)
        #expect(PlaybackLocator.nearestWordIndex(at: 100, in: words) == 2)
    }
}

@Suite
struct TranscriptDisplayGrouperTests {
    @Test
    func mergesKatakanaFragmentsIntoSingleDisplayWord() {
        let words = [
            TranscriptWord(text: "コー", startTime: 0.0, endTime: 0.25),
            TranscriptWord(text: "デックス", startTime: 0.26, endTime: 0.62)
        ]

        let grouper = TranscriptDisplayGrouper()
        let grouped = grouper.group(words: words)

        #expect(grouped.count == 1)
        #expect(grouped[0].text == "コーデックス")
        #expect(grouped[0].startTime == 0.0)
        #expect(grouped[0].endTime == 0.62)
    }

    @Test
    func keepsSeparatedWordsWhenGapIsLarge() {
        let words = [
            TranscriptWord(text: "今日は", startTime: 0.0, endTime: 0.4),
            TranscriptWord(text: "会議", startTime: 1.2, endTime: 1.6)
        ]

        let grouper = TranscriptDisplayGrouper()
        let grouped = grouper.group(words: words)

        #expect(grouped.count == 2)
        #expect(grouped[0].text == "今日は")
        #expect(grouped[1].text == "会議")
    }

    @Test
    func punctuationIsAttachedToPreviousDisplayWord() {
        let words = [
            TranscriptWord(text: "こんにちは", startTime: 0.0, endTime: 0.5),
            TranscriptWord(text: "。", startTime: 0.51, endTime: 0.54)
        ]

        let grouper = TranscriptDisplayGrouper()
        let grouped = grouper.group(words: words)

        #expect(grouped.count == 1)
        #expect(grouped[0].text == "こんにちは。")
    }
}
