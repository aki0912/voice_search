import Foundation

public struct TranscriptPlainTextFormatter: Sendable {
    public var preferredLineLength: Int
    public var hardLineLength: Int
    public var pauseLineBreakThreshold: TimeInterval

    public init(
        preferredLineLength: Int = 36,
        hardLineLength: Int = 54,
        pauseLineBreakThreshold: TimeInterval = 0.1
    ) {
        self.preferredLineLength = max(8, preferredLineLength)
        self.hardLineLength = max(self.preferredLineLength, hardLineLength)
        self.pauseLineBreakThreshold = max(0, pauseLineBreakThreshold)
    }

    public func format(words: [TranscriptWord]) -> String {
        let normalizedWords = words.compactMap { word -> TranscriptWord? in
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptWord(id: word.id, text: text, startTime: word.startTime, endTime: word.endTime)
        }

        guard !normalizedWords.isEmpty else { return "" }

        var lines: [String] = []
        var currentLine = ""
        var previousToken: String?
        var previousWord: TranscriptWord?

        for word in normalizedWords {
            let token = word.text
            if let previousWord,
               shouldBreakOnPause(previous: previousWord, next: word),
               !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = ""
                previousToken = nil
            }

            if currentLine.isEmpty {
                currentLine = token
            } else {
                if shouldInsertSpace(previous: previousToken, next: token) {
                    currentLine.append(" ")
                }
                currentLine.append(token)
            }

            previousToken = token
            previousWord = word

            if shouldBreakAfter(token: token, currentLineLength: currentLine.count) {
                lines.append(currentLine)
                currentLine = ""
                previousToken = nil
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.joined(separator: "\n")
    }

    private func shouldBreakOnPause(previous: TranscriptWord, next: TranscriptWord) -> Bool {
        guard previous.endTime.isFinite, next.startTime.isFinite else { return false }
        let gap = next.startTime - previous.endTime
        return gap >= pauseLineBreakThreshold
    }

    private func shouldBreakAfter(token: String, currentLineLength: Int) -> Bool {
        if isSentenceTerminal(token) {
            return true
        }

        if currentLineLength >= preferredLineLength, isSoftBreakToken(token) {
            return true
        }

        if currentLineLength >= hardLineLength {
            return true
        }

        return false
    }

    private func shouldInsertSpace(previous: String?, next: String) -> Bool {
        guard let previous else { return false }
        if isPunctuationToken(next) || isClosingBracketToken(next) {
            return false
        }
        if isOpeningBracketToken(previous) {
            return false
        }
        if isJapaneseToken(previous) || isJapaneseToken(next) {
            return false
        }
        return true
    }

    private func isJapaneseToken(_ token: String) -> Bool {
        token.unicodeScalars.contains(where: isJapaneseScalar)
    }

    private func isJapaneseScalar(_ scalar: UnicodeScalar) -> Bool {
        (0x3040...0x309F).contains(scalar.value) || // Hiragana
        (0x30A0...0x30FF).contains(scalar.value) || // Katakana
        (0x3400...0x4DBF).contains(scalar.value) || // CJK Extension A
        (0x4E00...0x9FFF).contains(scalar.value)    // CJK Unified Ideographs
    }

    private func isPunctuationToken(_ token: String) -> Bool {
        let scalars = token.unicodeScalars
        guard !scalars.isEmpty else { return false }
        return scalars.allSatisfy { punctuationSet.contains($0) }
    }

    private func isSentenceTerminal(_ token: String) -> Bool {
        token.unicodeScalars.contains { sentenceTerminalSet.contains($0) }
    }

    private func isSoftBreakToken(_ token: String) -> Bool {
        token.unicodeScalars.contains { softBreakSet.contains($0) }
    }

    private func isOpeningBracketToken(_ token: String) -> Bool {
        token.unicodeScalars.contains { openingBracketSet.contains($0) }
    }

    private func isClosingBracketToken(_ token: String) -> Bool {
        token.unicodeScalars.contains { closingBracketSet.contains($0) }
    }

    private var punctuationSet: CharacterSet {
        CharacterSet(charactersIn: "、。,.!?！？…:;：；・（）()[]「」『』【】〈〉《》")
    }

    private var sentenceTerminalSet: CharacterSet {
        CharacterSet(charactersIn: "。.!?！？")
    }

    private var softBreakSet: CharacterSet {
        CharacterSet(charactersIn: "、,，;；:：")
    }

    private var openingBracketSet: CharacterSet {
        CharacterSet(charactersIn: "（([「『【〈《")
    }

    private var closingBracketSet: CharacterSet {
        CharacterSet(charactersIn: "）)]」』】〉》")
    }
}
