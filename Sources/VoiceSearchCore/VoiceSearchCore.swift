import Foundation

public struct TranscriptWord: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(id: UUID = UUID(), text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

public protocol TokenNormalizing: Sendable {
    func normalize(_ text: String) -> String
    func tokenize(_ text: String) -> [String]
}

public struct DefaultTokenNormalizer: TokenNormalizing {
    public init() {}

    public func normalize(_ text: String) -> String {
        let lowered = text.lowercased().folding(options: [.diacriticInsensitive], locale: .current)
        let stripped = String(lowered.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
                ? Character(scalar)
                : " "
        })
        let kanaUnified = String(stripped.unicodeScalars.map { scalar -> Character in
            let mappedScalar: UnicodeScalar
            switch scalar.value {
            case 0x3041...0x3096, 0x309D...0x309E:
                mappedScalar = UnicodeScalar(scalar.value + 0x60) ?? scalar
            default:
                mappedScalar = scalar
            }
            return Character(mappedScalar)
        })

        return kanaUnified
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    public func tokenize(_ text: String) -> [String] {
        normalize(text)
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
    }
}

public struct SearchOptions: Sendable {
    public enum MatchMode: Sendable {
        case exact
        case contains
    }

    public var maxResults: Int
    public var mode: MatchMode

    public init(maxResults: Int = 50, mode: MatchMode = .exact) {
        self.maxResults = maxResults
        self.mode = mode
    }
}

public struct UserDictionaryEntry: Equatable, Hashable, Codable, Sendable {
    public let canonical: String
    public let aliases: [String]

    public init(canonical: String, aliases: [String]) {
        self.canonical = canonical
        self.aliases = aliases
    }
}

public struct UserDictionary: Sendable {
    private var normalizedMap: [String: Set<String>] = [:]

    public init(entries: [UserDictionaryEntry] = [], normalizer: TokenNormalizing = DefaultTokenNormalizer()) {
        self.normalizedMap = [:]
        for entry in entries {
            self.insert(entry, normalizer: normalizer)
        }
    }

    public mutating func insert(_ entry: UserDictionaryEntry, normalizer: TokenNormalizing = DefaultTokenNormalizer()) {
        let canonical = normalizer.normalize(entry.canonical)
        let aliases = Set(entry.aliases.map { normalizer.normalize($0) }.filter { !$0.isEmpty })
        var group = aliases
        group.insert(canonical)

        for token in group {
            normalizedMap[token] = group
        }
    }

    public func forms(for text: String, normalizer: TokenNormalizing = DefaultTokenNormalizer()) -> Set<String> {
        let normalized = normalizer.normalize(text)
        var forms = Set<String>()
        forms.insert(normalized)
        if let linked = normalizedMap[normalized] {
            forms.formUnion(linked)
        }
        return forms
    }
}

public struct SearchHit: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startIndex: Int
    public let endIndex: Int
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let matchedText: String
    public let displayText: String

    public init(startIndex: Int, endIndex: Int, startTime: TimeInterval, endTime: TimeInterval, matchedText: String, displayText: String) {
        self.id = UUID()
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.startTime = startTime
        self.endTime = endTime
        self.matchedText = matchedText
        self.displayText = displayText
    }
}

public struct TranscriptSearchService: Sendable {
    private let normalizer: TokenNormalizing
    private let dictionary: UserDictionary

    public init(normalizer: TokenNormalizing = DefaultTokenNormalizer(), dictionary: UserDictionary = UserDictionary()) {
        self.normalizer = normalizer
        self.dictionary = dictionary
    }

    public func search(words: [TranscriptWord], query: String, options: SearchOptions = SearchOptions()) -> [SearchHit] {
        let queryTokens = normalizer.tokenize(query)
        guard !queryTokens.isEmpty else {
            return []
        }

        if queryTokens.count == 1 {
            return searchSingle(words: words, queryToken: queryTokens[0], options: options)
        }

        return searchPhrase(words: words, queryTokens: queryTokens, options: options)
    }

    private func searchSingle(words: [TranscriptWord], queryToken: String, options: SearchOptions) -> [SearchHit] {
        var hits: [SearchHit] = []
        let queryForms = dictionary.forms(for: queryToken, normalizer: normalizer)

        for index in words.indices {
            let word = words[index]
            let tokenForms = dictionary.forms(for: word.text, normalizer: normalizer)
            if matches(tokenForms: tokenForms, queryForms: queryForms, mode: options.mode) {
                hits.append(
                    SearchHit(
                        startIndex: index,
                        endIndex: index,
                        startTime: word.startTime,
                        endTime: word.endTime,
                        matchedText: normalizer.normalize(word.text),
                        displayText: word.text
                    )
                )
            }
        }

        return hits.prefix(options.maxResults).map { $0 }
    }

    private func searchPhrase(words: [TranscriptWord], queryTokens: [String], options: SearchOptions) -> [SearchHit] {
        guard words.count >= queryTokens.count else { return [] }

        let queryForms = queryTokens.map { dictionary.forms(for: $0, normalizer: normalizer) }
        var hits: [SearchHit] = []

        for start in 0...(words.count - queryTokens.count) {
            var allMatched = true
            for offset in queryTokens.indices {
                let word = words[start + offset]
                let tokenForms = dictionary.forms(for: word.text, normalizer: normalizer)
                let expected = queryForms[offset]
                if !matches(tokenForms: tokenForms, queryForms: expected, mode: options.mode) {
                    allMatched = false
                    break
                }
            }
            if allMatched {
                let end = start + queryTokens.count - 1
                let first = words[start]
                let last = words[end]
                let matchedText = normalizer.normalize(queryTokens.joined(separator: " "))
                let displayText = words[start ... end].map(\.text).joined(separator: " ")
                hits.append(
                    SearchHit(
                        startIndex: start,
                        endIndex: end,
                        startTime: first.startTime,
                        endTime: last.endTime,
                        matchedText: matchedText,
                        displayText: displayText
                    )
                )
            }
        }

        return hits.prefix(options.maxResults).map { $0 }
    }

    private func matches(tokenForms: Set<String>, queryForms: Set<String>, mode: SearchOptions.MatchMode) -> Bool {
        switch mode {
        case .exact:
            return !tokenForms.isDisjoint(with: queryForms)
        case .contains:
            for token in tokenForms {
                for query in queryForms {
                    if token.contains(query) {
                        return true
                    }
                }
            }
            return false
        }
    }
}

public enum PlaybackLocator {
    public static func nearestWordIndex(at time: TimeInterval, in words: [TranscriptWord]) -> Int? {
        guard !words.isEmpty else { return nil }

        if time <= words.first!.startTime { return 0 }
        if time >= words.last!.endTime { return words.count - 1 }

        var left = 0
        var right = words.count - 1
        var best = 0

        while left <= right {
            let middle = (left + right) / 2
            let current = words[middle]

            if current.startTime <= time && time <= current.endTime {
                return middle
            }

            if current.startTime < time {
                best = middle
                left = middle + 1
            } else {
                right = middle - 1
            }
        }

        return best
    }
}
