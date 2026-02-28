import Foundation

enum UserDictionaryProcessor {
    static func contextualStrings(
        from entries: [UserDictionaryEntry],
        normalizer: TokenNormalizing,
        limit: Int = 100
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for entry in entries {
            let candidates = [entry.canonical] + entry.aliases
            for raw in candidates {
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }

                let key = normalizer.normalize(text)
                if key.isEmpty || seen.contains(key) { continue }
                seen.insert(key)
                output.append(text)
                if output.count >= limit { return output }
            }
        }

        return output
    }

    static func applyDisplayNormalization(
        rawTranscript: [TranscriptWord],
        entries: [UserDictionaryEntry],
        normalizer: TokenNormalizing
    ) -> [TranscriptWord] {
        guard !rawTranscript.isEmpty else { return [] }

        var displayMap: [String: String] = [:]
        for entry in entries {
            let canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else { continue }

            let canonicalKey = normalizer.normalize(canonical)
            if !canonicalKey.isEmpty {
                displayMap[canonicalKey] = canonical
            }

            for alias in entry.aliases {
                let aliasKey = normalizer.normalize(alias)
                if aliasKey.isEmpty { continue }
                displayMap[aliasKey] = canonical
            }
        }

        return rawTranscript.map { word in
            let key = normalizer.normalize(word.text)
            guard !key.isEmpty, let replacement = displayMap[key] else { return word }
            return TranscriptWord(id: word.id, text: replacement, startTime: word.startTime, endTime: word.endTime)
        }
    }
}
