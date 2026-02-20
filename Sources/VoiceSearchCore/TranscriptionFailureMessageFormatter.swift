import Foundation

public struct TranscriptionFailureMessageFormatter: Sendable {
    public init() {}

    public func format(modeLabel: String, error: Error) -> String {
        let headline = CoreL10n.format("failure.headline", modeLabel)
        let primary = normalized(error.localizedDescription)
        let nsError = error as NSError
        let cause = extractCause(nsError: nsError, primary: primary)
        let hint = inferHint(primary: primary, cause: cause)

        var lines: [String] = ["\(headline): \(primary)"]
        if let cause {
            lines.append(CoreL10n.format("failure.cause", cause))
        }
        if let hint {
            lines.append(CoreL10n.format("failure.hint", hint))
        }
        return lines.joined(separator: "\n")
    }

    private func extractCause(nsError: NSError, primary: String) -> String? {
        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
            let normalizedReason = normalized(reason)
            if !normalizedReason.isEmpty, normalizedReason != primary {
                return normalizedReason
            }
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            let underlyingText = normalized(underlying.localizedDescription)
            if !underlyingText.isEmpty, underlyingText != primary {
                return underlyingText
            }
        }

        return nil
    }

    private func inferHint(primary: String, cause: String?) -> String? {
        let normalizedTarget = normalized([primary, cause].compactMap { $0 }.joined(separator: " "))
        let lower = normalizedTarget.lowercased()

        if lower.contains("権限") || lower.contains("not authorized") || lower.contains("authorization") {
            return CoreL10n.text("failure.hint.authorization")
        }
        if lower.contains("no audio track") || lower.contains("音声トラック") {
            return CoreL10n.text("failure.hint.noAudioTrack")
        }
        if lower.contains("unsupported locale") || lower.contains("サポート") || lower.contains("locale") {
            return CoreL10n.text("failure.hint.unsupportedLocale")
        }
        if lower.contains("asset") || lower.contains("model") {
            return CoreL10n.text("failure.hint.asset")
        }
        return nil
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
