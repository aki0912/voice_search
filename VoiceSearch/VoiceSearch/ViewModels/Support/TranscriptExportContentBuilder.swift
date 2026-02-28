import Foundation

struct TranscriptExportContentBuilder {
    static func txtContent(
        words: [TranscriptWord],
        pauseLineBreakThreshold: TimeInterval,
        transcriptHeader: String,
        timedWordsHeader: String
    ) -> String {
        let clampedThreshold = min(max(0, pauseLineBreakThreshold), 2.0)
        let plain = TranscriptPlainTextFormatter(
            pauseLineBreakThreshold: clampedThreshold
        ).format(words: words)
        let timed = words.map { word in
            "[\(formatTimeForExport(word.startTime)) - \(formatTimeForExport(word.endTime))] \(word.text)"
        }.joined(separator: "\n")

        return """
        \(transcriptHeader)
        \(plain)

        \(timedWordsHeader)
        \(timed)
        """
    }

    static func srtContent(words: [TranscriptWord]) -> String {
        struct Cue {
            let start: TimeInterval
            let end: TimeInterval
            let text: String
        }

        var cues: [Cue] = []
        var index = 0

        while index < words.count {
            let startWord = words[index]
            var endIndex = index

            while endIndex + 1 < words.count {
                let nextIndex = endIndex + 1
                let duration = words[nextIndex].endTime - startWord.startTime
                let wordCount = nextIndex - index + 1
                if duration > 2.5 || wordCount > 8 { break }
                endIndex = nextIndex
            }

            let text = words[index...endIndex].map(\.text).joined(separator: " ")
            cues.append(
                Cue(
                    start: startWord.startTime,
                    end: words[endIndex].endTime,
                    text: text
                )
            )
            index = endIndex + 1
        }

        return cues.enumerated().map { offset, cue in
            """
            \(offset + 1)
            \(formatTimeForSRT(cue.start)) --> \(formatTimeForSRT(cue.end))
            \(cue.text)
            """
        }.joined(separator: "\n\n")
    }

    private static func formatTimeForExport(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00.000" }
        let minutes = Int(value / 60)
        let seconds = Int(value) % 60
        let millis = Int((value - floor(value)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }

    private static func formatTimeForSRT(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00:00,000" }
        let hours = Int(value / 3600)
        let minutes = Int(value.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(value) % 60
        let millis = Int((value - floor(value)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }
}
