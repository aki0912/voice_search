import Foundation
import Speech
import VoiceSearchCore
import VoiceSearchServices

private enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message):
            return message
        }
    }
}

private enum RunMode: String {
    case diagnose
    case onDevice = "on-device"
    case server

    static let allValues = ["diagnose", "on-device", "server"]
}

private struct CLIOptions {
    let inputURL: URL
    let outputURL: URL
    let mode: RunMode
    let locale: Locale?
    let allowAuthorizationPrompt: Bool

    static func parse(arguments: [String]) throws -> CLIOptions {
        var inputPath: String?
        var outputPath: String?
        var mode: RunMode = .diagnose
        var localeIdentifier: String?
        var allowAuthorizationPrompt = false

        var index = 1
        while index < arguments.count {
            let arg = arguments[index]
            switch arg {
            case "--help", "-h":
                throw CLIError.usage(Self.usageText())
            case "--input":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("--input の値がありません\n\n" + Self.usageText())
                }
                inputPath = arguments[index]
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("--output の値がありません\n\n" + Self.usageText())
                }
                outputPath = arguments[index]
            case "--mode":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("--mode の値がありません\n\n" + Self.usageText())
                }
                guard let parsed = RunMode(rawValue: arguments[index]) else {
                    throw CLIError.usage("不正な --mode です: \(arguments[index])\n指定可能: \(RunMode.allValues.joined(separator: ", "))")
                }
                mode = parsed
            case "--locale":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.usage("--locale の値がありません\n\n" + Self.usageText())
                }
                localeIdentifier = arguments[index]
            case "--allow-auth-prompt":
                allowAuthorizationPrompt = true
            default:
                throw CLIError.usage("不明な引数です: \(arg)\n\n" + Self.usageText())
            }
            index += 1
        }

        guard let inputPath else {
            throw CLIError.usage("--input は必須です\n\n" + Self.usageText())
        }

        let resolvedInputPath = (inputPath as NSString).expandingTildeInPath
        let inputURL = URL(fileURLWithPath: resolvedInputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw CLIError.usage("入力ファイルが見つかりません: \(inputURL.path)")
        }

        let outputURL: URL = {
            if let outputPath {
                let resolvedOutputPath = (outputPath as NSString).expandingTildeInPath
                return URL(fileURLWithPath: resolvedOutputPath)
            }
            let stem = inputURL.deletingPathExtension().lastPathComponent
            return inputURL.deletingLastPathComponent().appendingPathComponent("\(stem)_diagnostics.txt")
        }()

        return CLIOptions(
            inputURL: inputURL,
            outputURL: outputURL,
            mode: mode,
            locale: localeIdentifier.map(Locale.init(identifier:)),
            allowAuthorizationPrompt: allowAuthorizationPrompt
        )
    }

    static func usageText() -> String {
        """
        Usage:
          swift run VoiceSearchCLI --input <audio-file> [--output <report-file>] [--mode diagnose|on-device|server] [--locale ja-JP] [--allow-auth-prompt]

        Examples:
          swift run VoiceSearchCLI --input sample2.m4a --mode diagnose
          swift run VoiceSearchCLI --input sample2.m4a --mode on-device --output sample2_ondevice.txt
          swift run VoiceSearchCLI --input sample2.m4a --mode server --allow-auth-prompt
        """
    }
}

private struct RunRecord {
    let label: String
    let output: TranscriptionOutput
    let elapsedSeconds: TimeInterval
    let bundleIdentifier: String
    let bundlePath: String
    let isAppBundle: Bool
    let authorizationStatusBefore: String
    let authorizationStatusAfter: String
}

@main
struct VoiceSearchCLI {
    static func main() async {
        do {
            let options = try CLIOptions.parse(arguments: CommandLine.arguments)
            let reportText = try await run(options: options)

            let parent = options.outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try reportText.write(to: options.outputURL, atomically: true, encoding: .utf8)

            print("完了: \(options.outputURL.path)")
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(options: CLIOptions) async throws -> String {
        switch options.mode {
        case .diagnose:
            let onDevice = try await runSingle(
                label: "on-device",
                strategy: .onDeviceOnly,
                options: options
            )
            let server = try await runSingle(
                label: "server",
                strategy: .serverOnly,
                options: options
            )
            return renderDiagnoseReport(options: options, onDevice: onDevice, server: server)
        case .onDevice:
            let record = try await runSingle(
                label: "on-device",
                strategy: .onDeviceOnly,
                options: options
            )
            return renderSingleReport(options: options, record: record)
        case .server:
            let record = try await runSingle(
                label: "server",
                strategy: .serverOnly,
                options: options
            )
            return renderSingleReport(options: options, record: record)
        }
    }

    private static func runSingle(
        label: String,
        strategy: SpeechURLTranscriptionService.RecognitionStrategy,
        options: CLIOptions
    ) async throws -> RunRecord {
        print("実行中 (\(label)) ...")
        let bundlePath = Bundle.main.bundleURL.path
        let statusBefore = authorizationStatusLabel(SFSpeechRecognizer.authorizationStatus())
        let pipeline = TranscriptionPipeline()
        let service: any TranscriptionService
        if strategy == .onDeviceOnly, SpeechAnalyzerTranscriptionService.isAvailable {
            service = SpeechAnalyzerTranscriptionService()
        } else {
            service = SpeechURLTranscriptionService(
                recognitionStrategy: strategy,
                allowAuthorizationPrompt: options.allowAuthorizationPrompt
            )
        }
        let request = TranscriptionRequest(
            sourceURL: options.inputURL,
            locale: options.locale
        )

        let startedAt = Date()
        let output = try await pipeline.run(request, service: service)
        let elapsed = Date().timeIntervalSince(startedAt)
        let statusAfter = authorizationStatusLabel(SFSpeechRecognizer.authorizationStatus())
        return RunRecord(
            label: label,
            output: output,
            elapsedSeconds: elapsed,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "(nil)",
            bundlePath: bundlePath,
            isAppBundle: Bundle.main.bundleURL.pathExtension == "app",
            authorizationStatusBefore: statusBefore,
            authorizationStatusAfter: statusAfter
        )
    }

    private static func renderDiagnoseReport(options: CLIOptions, onDevice: RunRecord, server: RunRecord) -> String {
        let onDeviceSummary = summarize(onDevice.output)
        let serverSummary = summarize(server.output)

        let wordsDiff = serverSummary.wordCount - onDeviceSummary.wordCount
        let coverageDiff: Double? = {
            guard let lhs = onDeviceSummary.coverageRate, let rhs = serverSummary.coverageRate else { return nil }
            return rhs - lhs
        }()

        let issueHint: String = {
            if onDeviceSummary.wordCount <= 3 && serverSummary.wordCount > onDeviceSummary.wordCount * 5 {
                return "オンデバイス認識が途中で打ち切られている可能性が高いです。"
            }
            if let coverageDiff, coverageDiff > 0.2 {
                return "オンデバイス認識のカバー時間が短く、サーバー認識との差が大きいです。"
            }
            return "オンデバイス特有の大きな欠落は統計上は明確ではありません。"
        }()

        return """
        VoiceSearchCLI Diagnose Report
        GeneratedAt: \(iso8601Now())
        Input: \(options.inputURL.path)
        Locale: \(options.locale?.identifier ?? "system-default")

        ## Runtime
        bundleIdentifier: \(onDevice.bundleIdentifier)
        bundlePath: \(onDevice.bundlePath)
        isAppBundle: \(onDevice.isAppBundle)
        authorizationStatus(before): \(onDevice.authorizationStatusBefore)
        authorizationStatus(after): \(onDevice.authorizationStatusAfter)

        ## Comparison
        on-device words: \(onDeviceSummary.wordCount)
        server words: \(serverSummary.wordCount)
        word diff (server - on-device): \(wordsDiff)
        on-device coverage: \(percent(onDeviceSummary.coverageRate))
        server coverage: \(percent(serverSummary.coverageRate))
        coverage diff (server - on-device): \(percent(coverageDiff))
        hint: \(issueHint)

        ## On-device Summary
        \(renderSummary(record: onDevice, summary: onDeviceSummary))

        ## Server Summary
        \(renderSummary(record: server, summary: serverSummary))
        """
    }

    private static func renderSingleReport(options: CLIOptions, record: RunRecord) -> String {
        let summary = summarize(record.output)
        return """
        VoiceSearchCLI Report
        GeneratedAt: \(iso8601Now())
        Input: \(options.inputURL.path)
        Mode: \(record.label)
        Locale: \(options.locale?.identifier ?? "system-default")
        bundleIdentifier: \(record.bundleIdentifier)
        bundlePath: \(record.bundlePath)
        isAppBundle: \(record.isAppBundle)
        authorizationStatus(before): \(record.authorizationStatusBefore)
        authorizationStatus(after): \(record.authorizationStatusAfter)

        \(renderSummary(record: record, summary: summary))
        """
    }

    private static func renderSummary(record: RunRecord, summary: Summary) -> String {
        let diagnostics = record.output.diagnostics.map { "- \($0)" }.joined(separator: "\n")
        let timedTranscript = record.output.words.map { word in
            "[\(formatTime(word.startTime)) - \(formatTime(word.endTime))] \(word.text)"
        }.joined(separator: "\n")

        return """
        label: \(record.label)
        elapsedSeconds: \(String(format: "%.2f", record.elapsedSeconds))
        wordCount: \(summary.wordCount)
        sourceDurationSeconds: \(summary.sourceDuration.map { String(format: "%.3f", $0) } ?? "n/a")
        coveredDurationSeconds: \(summary.coveredDuration.map { String(format: "%.3f", $0) } ?? "n/a")
        coverageRate: \(percent(summary.coverageRate))

        Diagnostics:
        \(diagnostics.isEmpty ? "- (none)" : diagnostics)

        Transcript (plain):
        \(record.output.words.map(\.text).joined(separator: " "))

        Transcript (timed words):
        \(timedTranscript)
        """
    }

    private struct Summary {
        let wordCount: Int
        let sourceDuration: TimeInterval?
        let coveredDuration: TimeInterval?
        let coverageRate: Double?
    }

    private static func summarize(_ output: TranscriptionOutput) -> Summary {
        let sourceDuration = output.duration
        let coveredDuration: TimeInterval? = {
            guard let first = output.words.first, let last = output.words.last else { return nil }
            return max(0, last.endTime - first.startTime)
        }()
        let coverageRate: Double? = {
            guard let sourceDuration, sourceDuration > 0, let coveredDuration else { return nil }
            return max(0, min(1, coveredDuration / sourceDuration))
        }()

        return Summary(
            wordCount: output.words.count,
            sourceDuration: sourceDuration,
            coveredDuration: coveredDuration,
            coverageRate: coverageRate
        )
    }

    private static func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00.000" }
        let minutes = Int(value / 60)
        let seconds = Int(value) % 60
        let millis = Int((value - floor(value)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }

    private static func percent(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return String(format: "%.1f%%", value * 100)
    }

    private static func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func authorizationStatusLabel(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .authorized:
            return "authorized"
        @unknown default:
            return "unknown(\(status.rawValue))"
        }
    }
}
