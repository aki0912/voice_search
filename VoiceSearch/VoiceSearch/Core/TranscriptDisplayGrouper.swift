import Foundation

public struct TranscriptDisplayGrouper: Sendable {
    public var maxGap: TimeInterval
    public var maxDuration: TimeInterval
    public var maxCharacters: Int

    public init(
        maxGap: TimeInterval = 0.28,
        maxDuration: TimeInterval = 2.0,
        maxCharacters: Int = 18
    ) {
        self.maxGap = maxGap
        self.maxDuration = maxDuration
        self.maxCharacters = maxCharacters
    }

    public func group(words: [TranscriptWord]) -> [TranscriptWord] {
        guard !words.isEmpty else { return [] }

        let ordered = words.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }

        var grouped: [TranscriptWord] = []
        var current: [TranscriptWord] = [ordered[0]]

        for next in ordered.dropFirst() {
            if shouldMerge(current: current, next: next) {
                current.append(next)
            } else {
                grouped.append(makeGroupedWord(from: current))
                current = [next]
            }
        }

        grouped.append(makeGroupedWord(from: current))
        return grouped
    }

    private func shouldMerge(current: [TranscriptWord], next: TranscriptWord) -> Bool {
        guard let first = current.first, let last = current.last else { return false }

        let gap = max(0, next.startTime - last.endTime)
        if gap > maxGap {
            return false
        }

        let previousText = last.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextText = next.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousText.isEmpty, !nextText.isEmpty else { return false }

        if isPunctuationToken(nextText) {
            return true
        }
        if isAttachable(nextText) {
            return true
        }
        if isContinuation(previousText: previousText, nextText: nextText) {
            return true
        }

        let candidateDuration = next.endTime - first.startTime
        let candidateCharacters = mergedCharacterCount(of: current) + nextText.count
        if candidateDuration > maxDuration || candidateCharacters > maxCharacters {
            return false
        }

        if isJapaneseToken(previousText), isJapaneseToken(nextText), gap <= maxGap * 0.45 {
            return true
        }

        return false
    }

    private func makeGroupedWord(from words: [TranscriptWord]) -> TranscriptWord {
        guard let first = words.first, let last = words.last else {
            return TranscriptWord(text: "", startTime: 0, endTime: 0)
        }

        let text = mergeText(words.map(\.text))
        return TranscriptWord(id: first.id, text: text, startTime: first.startTime, endTime: last.endTime)
    }

    private func mergedCharacterCount(of words: [TranscriptWord]) -> Int {
        words.reduce(0) { partial, word in
            partial + word.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        }
    }

    private func mergeText(_ tokens: [String]) -> String {
        guard var merged = tokens.first?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }

        for raw in tokens.dropFirst() {
            let next = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !next.isEmpty else { continue }
            if shouldInsertSpace(between: merged, and: next) {
                merged.append(" ")
            }
            merged.append(next)
        }
        return merged
    }

    private func shouldInsertSpace(between lhs: String, and rhs: String) -> Bool {
        if lhs.isEmpty || rhs.isEmpty { return false }
        if isPunctuationToken(rhs) { return false }
        if isJapaneseToken(lhs) || isJapaneseToken(rhs) { return false }
        guard let lhsLast = lhs.unicodeScalars.last, let rhsFirst = rhs.unicodeScalars.first else {
            return false
        }
        return CharacterSet.alphanumerics.contains(lhsLast) && CharacterSet.alphanumerics.contains(rhsFirst)
    }

    private func isAttachable(_ token: String) -> Bool {
        if functionWords.contains(token) {
            return true
        }
        return token.count <= 2 && isKanaOnly(token)
    }

    private func isContinuation(previousText: String, nextText: String) -> Bool {
        if isKatakanaOnly(previousText), isKatakanaOnly(nextText) {
            return previousText.count <= 4 || nextText.count <= 4
        }

        if previousText.hasSuffix("ー"), isKatakanaOnly(nextText) {
            return true
        }

        if previousText.count == 1, isJapaneseToken(previousText), isJapaneseToken(nextText) {
            return true
        }

        return false
    }

    private func isJapaneseToken(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isJapaneseScalar)
    }

    private func isKanaOnly(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        return scalars.allSatisfy { scalar in
            isHiraganaScalar(scalar) || isKatakanaScalar(scalar)
        }
    }

    private func isKatakanaOnly(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        return scalars.allSatisfy { scalar in
            isKatakanaScalar(scalar) || scalar == "ー"
        }
    }

    private func isPunctuationToken(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        return scalars.allSatisfy { punctuationCharacters.contains($0) }
    }

    private func isJapaneseScalar(_ scalar: UnicodeScalar) -> Bool {
        isHiraganaScalar(scalar) || isKatakanaScalar(scalar) || isCJKScalar(scalar)
    }

    private func isHiraganaScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x3040...0x309F).contains(scalar.value)
    }

    private func isKatakanaScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x30A0...0x30FF).contains(scalar.value) || (0x31F0...0x31FF).contains(scalar.value)
    }

    private func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
    }

    private var punctuationCharacters: CharacterSet {
        CharacterSet(charactersIn: "、。.,!?！？…・:;：；")
    }

    private var functionWords: Set<String> {
        [
            "は", "が", "を", "に", "へ", "で", "と", "も", "や", "の",
            "ね", "よ", "か", "な", "さ", "わ", "ぞ", "ぜ", "って",
            "から", "まで", "より", "だけ", "しか", "でも", "ほど",
            "くらい", "ぐらい", "など", "です", "ます", "だ", "だった",
            "でした", "ない", "たい", "た", "て", "で", "ん", "う", "よう"
        ]
    }
}
