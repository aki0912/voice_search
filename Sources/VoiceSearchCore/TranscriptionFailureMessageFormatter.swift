import Foundation

public struct TranscriptionFailureMessageFormatter: Sendable {
    public init() {}

    public func format(modeLabel: String, error: Error) -> String {
        let headline = "文字起こしに失敗（\(modeLabel)）"
        let primary = normalized(error.localizedDescription)
        let nsError = error as NSError
        let cause = extractCause(nsError: nsError, primary: primary)
        let hint = inferHint(primary: primary, cause: cause)

        var lines: [String] = ["\(headline): \(primary)"]
        if let cause {
            lines.append("原因: \(cause)")
        }
        if let hint {
            lines.append("対処: \(hint)")
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
            return "システム設定の「プライバシーとセキュリティ > 音声認識」で許可状態を確認してください。"
        }
        if lower.contains("no audio track") || lower.contains("音声トラック") {
            return "音声トラックを含むファイルを指定してください。動画の場合は音声付きファイルを使ってください。"
        }
        if lower.contains("unsupported locale") || lower.contains("サポート") || lower.contains("locale") {
            return "認識言語設定を変更し、対象言語が利用可能か確認してください。"
        }
        if lower.contains("asset") || lower.contains("model") {
            return "音声認識アセットの準備が完了するまで待ってから再実行してください。"
        }
        return nil
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
