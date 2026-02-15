import Foundation
import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import VoiceSearchCore
import VoiceSearchServices

@MainActor
final class TranscriptionViewModel: ObservableObject {
    enum RecognitionMode: String, CaseIterable, Identifiable {
        case onDevice
        case server

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .onDevice:
                return "オンデバイス"
            case .server:
                return "サーバー"
            }
        }
    }

    @Published var sourceURL: URL?
    @Published var isVideoSource = false
    @Published var transcript: [TranscriptWord] = []
    @Published var queue: [URL] = []
    @Published var statusText: String = "ファイルをドラッグしてください"
    @Published var isAnalyzing = false
    @Published var query: String = ""
    @Published var isContainsMatchMode: Bool = true
    @Published var searchHits: [SearchHit] = []
    @Published var highlightedIndex: Int? = nil
    @Published var currentTime: TimeInterval = 0
    @Published var isDropTargeted = false
    @Published var dictionaryEntries: [UserDictionaryEntry] = []
    @Published var errorMessage: String?
    @Published var analysisProgress: Double = 0
    @Published var recognitionMode: RecognitionMode = .onDevice {
        didSet {
            guard recognitionMode != oldValue else { return }
            guard sourceURL != nil, !isAnalyzing else { return }
            statusText = "認識方式を\(recognitionMode.displayLabel)に変更しました（再解析で反映）"
        }
    }

    private let pipeline: TranscriptionPipeline
    private let normalizer = DefaultTokenNormalizer()
    private let options = SearchOptions()

    private var rawTranscript: [TranscriptWord] = []
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var timeObserverPlayer: AVPlayer?
    private var analysisProgressTask: Task<Void, Never>?
    private let fileDictionaryURL: URL

    private enum TranscriptExportFormat: String {
        case txt
        case srt

        var suggestedExtension: String { rawValue }
    }

    init(
        pipeline: TranscriptionPipeline = TranscriptionPipeline()
    ) {
        self.pipeline = pipeline

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileDictionaryURL = support.appendingPathComponent("voice_search", isDirectory: true)
            .appendingPathComponent("dictionary.json")

        do {
            try FileManager.default.createDirectory(at: fileDictionaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            loadDictionary()
        } catch {
            errorMessage = "設定保存先を用意できませんでした: \(error.localizedDescription)"
        }
    }

    var playbackPlayer: AVPlayer? {
        player
    }

    func addDictionaryEntry(canonical rawCanonical: String, aliasesText rawAliases: String) -> Bool {
        let canonical = rawCanonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return false }

        let aliases = rawAliases
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let entry = UserDictionaryEntry(canonical: canonical, aliases: aliases)
        dictionaryEntries.removeAll { normalizer.normalize($0.canonical) == normalizer.normalize(canonical) }
        dictionaryEntries.append(entry)
        applyDictionaryDisplayNormalization()
        persistDictionary()
        performSearch()
        return true
    }

    func removeDictionaryEntry(_ entry: UserDictionaryEntry) {
        dictionaryEntries.removeAll {
            normalizer.normalize($0.canonical) == normalizer.normalize(entry.canonical)
        }
        applyDictionaryDisplayNormalization()
        persistDictionary()
        performSearch()
    }

    func handleDrop(providers: [NSItemProvider]) async -> Bool {
        guard !providers.isEmpty else { return false }
        var hasNewFiles = false

        for provider in providers {
            do {
                let url = try await provider.loadDroppedURL()
                queue.append(url)
                hasNewFiles = true
            } catch {
                errorMessage = "ドロップデータの読み込みに失敗: \(error.localizedDescription)"
            }
        }

        guard hasNewFiles else { return false }

        if !isAnalyzing {
            await processQueue()
        }
        return true
    }

    private func processQueue() async {
        guard !queue.isEmpty else { return }

        while !queue.isEmpty {
            let next = queue.removeFirst()
            await transcribe(url: next)
        }
    }

    func transcribe(url: URL) async {
        isAnalyzing = true
        await startAnalysisProgress(for: url)
        var didSucceed = false
        defer {
            finishAnalysisProgress(success: didSucceed)
            isAnalyzing = false
        }

        errorMessage = nil
        sourceURL = url
        isVideoSource = isVideoFile(url)

        if !queue.isEmpty {
            statusText = "\(1 + queue.count)件中現在処理: \(url.lastPathComponent)"
        } else {
            statusText = "解析中: \(url.lastPathComponent)"
        }

        let request = TranscriptionRequest(
            sourceURL: url,
            locale: nil,
            contextualStrings: transcriptionContextualStrings(),
            progressHandler: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.mergeAnalysisProgress(progress)
                }
            }
        )

        do {
            let service = buildTranscriptionService(for: recognitionMode)
            let output = try await pipeline.run(request, service: service)
            rawTranscript = output.words
            applyDictionaryDisplayNormalization()

            detachTimeObserver()
            player = AVPlayer(url: url)

            let itemCount = transcript.count
            let modeText = recognitionModeLabel(from: output.diagnostics)
            if itemCount == 0 {
                statusText = "文字起こし結果が空です"
            } else if let modeText {
                statusText = "\(itemCount)語を抽出（\(modeText)）"
            } else {
                statusText = "\(itemCount)語を抽出"
            }
            if let sourceDuration = output.duration, sourceDuration > 30, itemCount <= 3 {
                errorMessage = "抽出語数が少ない結果です（\(itemCount)語 / 約\(Int(sourceDuration))秒）。言語設定や音声品質の影響が考えられます。"
            }

            performSearch()
            startTimeObservation()
            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
            statusText = "文字起こしに失敗"
            rawTranscript = []
            transcript = []
            searchHits = []
        }
    }

    func performSearch() {
        guard !query.isEmpty else {
            searchHits = []
            return
        }

        let service = TranscriptSearchService(dictionary: UserDictionary(entries: dictionaryEntries))
        var opts = options
        opts.mode = isContainsMatchMode ? .contains : .exact
        searchHits = service.search(words: transcript, query: query, options: opts)
    }

    func jump(to hit: SearchHit) {
        seek(to: hit.startTime)
    }

    func jump(toWordAt index: Int) {
        guard index >= 0 && index < transcript.count else { return }
        seek(to: transcript[index].startTime)
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    func playPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func exportTranscriptToFile() {
        guard !transcript.isEmpty else {
            errorMessage = "書き出す文字起こしがありません"
            return
        }

        guard let format = promptExportFormat() else { return }

        let panel = NSSavePanel()
        panel.title = "文字起こしテキストを保存"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if format == .txt {
            panel.allowedContentTypes = [.plainText]
        } else if let srtType = UTType(filenameExtension: "srt") {
            panel.allowedContentTypes = [srtType]
        }
        panel.nameFieldStringValue = suggestedExportFilename(format: format)

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let text = transcriptTextContent(format: format)
            try text.write(to: destinationURL, atomically: true, encoding: .utf8)
            errorMessage = nil
            statusText = "テキストを書き出しました: \(destinationURL.lastPathComponent)"
        } catch {
            errorMessage = "テキスト書き出しに失敗: \(error.localizedDescription)"
        }
    }

    private func startTimeObservation() {
        detachTimeObserver()
        guard let player else { return }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 10)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = seconds
                self.highlightedIndex = PlaybackLocator.nearestWordIndex(at: seconds, in: self.transcript)
            }
        }
        timeObserverPlayer = player
    }

    private func detachTimeObserver() {
        if let token = timeObserverToken, let observerPlayer = timeObserverPlayer {
            observerPlayer.removeTimeObserver(token)
        }
        timeObserverToken = nil
        timeObserverPlayer = nil
    }

    private func startAnalysisProgress(for url: URL) async {
        analysisProgressTask?.cancel()
        analysisProgressTask = nil
        analysisProgress = 0.02

        let expectedSeconds = await estimateAnalysisDuration(for: url)
        analysisProgressTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                let next = max(0.02, min(0.95, (elapsed / expectedSeconds) * 0.95))
                self.analysisProgress = max(self.analysisProgress, next)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func finishAnalysisProgress(success: Bool) {
        analysisProgressTask?.cancel()
        analysisProgressTask = nil
        analysisProgress = success ? 1.0 : 0.0
    }

    private func estimateAnalysisDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else {
            return 30
        }

        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            return 30
        }

        // Speech recognition speed varies by device and language.
        return max(12, seconds * 0.65)
    }

    private func mergeAnalysisProgress(_ progress: TranscriptionProgress) {
        guard isAnalyzing else { return }
        let clamped = max(0.02, min(0.98, progress.fractionCompleted))
        analysisProgress = max(analysisProgress, clamped)
    }

    private func loadDictionary() {
        guard FileManager.default.fileExists(atPath: fileDictionaryURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileDictionaryURL)
            let decoded = try JSONDecoder().decode([UserDictionaryEntry].self, from: data)
            dictionaryEntries = decoded
        } catch {
            errorMessage = "辞書の読み込みに失敗: \(error.localizedDescription)"
        }
    }

    private func persistDictionary() {
        do {
            let data = try JSONEncoder().encode(dictionaryEntries)
            try data.write(to: fileDictionaryURL, options: .atomic)
        } catch {
            errorMessage = "辞書の保存に失敗: \(error.localizedDescription)"
        }
    }

    private func transcriptionContextualStrings() -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for entry in dictionaryEntries {
            let candidates = [entry.canonical] + entry.aliases
            for raw in candidates {
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }

                let key = normalizer.normalize(text)
                if key.isEmpty || seen.contains(key) { continue }
                seen.insert(key)
                output.append(text)
                if output.count >= 100 { return output }
            }
        }

        return output
    }

    private func applyDictionaryDisplayNormalization() {
        guard !rawTranscript.isEmpty else {
            transcript = []
            return
        }

        var displayMap: [String: String] = [:]
        for entry in dictionaryEntries {
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

        transcript = rawTranscript.map { word in
            let key = normalizer.normalize(word.text)
            guard !key.isEmpty, let replacement = displayMap[key] else { return word }
            return TranscriptWord(id: word.id, text: replacement, startTime: word.startTime, endTime: word.endTime)
        }
    }

    private func promptExportFormat() -> TranscriptExportFormat? {
        let alert = NSAlert()
        alert.messageText = "書き出し形式を選択"
        alert.informativeText = "文字起こしを TXT または SRT で保存できます。"
        alert.addButton(withTitle: "SRT")
        alert.addButton(withTitle: "TXT")
        alert.addButton(withTitle: "キャンセル")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .srt
        case .alertSecondButtonReturn:
            return .txt
        default:
            return nil
        }
    }

    private func suggestedExportFilename(format: TranscriptExportFormat) -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "transcript"
        return "\(base)_transcript.\(format.suggestedExtension)"
    }

    private func transcriptTextContent(format: TranscriptExportFormat) -> String {
        switch format {
        case .txt:
            return transcriptTextContentTXT()
        case .srt:
            return transcriptTextContentSRT()
        }
    }

    private func transcriptTextContentTXT() -> String {
        let plain = transcript.map(\.text).joined(separator: " ")
        let timed = transcript.map { word in
            "[\(formatTimeForExport(word.startTime)) - \(formatTimeForExport(word.endTime))] \(word.text)"
        }.joined(separator: "\n")

        return """
        Transcript
        \(plain)

        Timed Words
        \(timed)
        """
    }

    private func transcriptTextContentSRT() -> String {
        struct Cue {
            let start: TimeInterval
            let end: TimeInterval
            let text: String
        }

        var cues: [Cue] = []
        var index = 0

        while index < transcript.count {
            let startWord = transcript[index]
            var endIndex = index

            while endIndex + 1 < transcript.count {
                let nextIndex = endIndex + 1
                let duration = transcript[nextIndex].endTime - startWord.startTime
                let wordCount = nextIndex - index + 1
                if duration > 2.5 || wordCount > 8 { break }
                endIndex = nextIndex
            }

            let text = transcript[index...endIndex].map(\.text).joined(separator: " ")
            cues.append(
                Cue(
                    start: startWord.startTime,
                    end: transcript[endIndex].endTime,
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

    private func formatTimeForExport(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00.000" }
        let minutes = Int(value / 60)
        let seconds = Int(value) % 60
        let millis = Int((value - floor(value)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, seconds, millis)
    }

    private func formatTimeForSRT(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "00:00:00,000" }
        let hours = Int(value / 3600)
        let minutes = Int(value.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(value) % 60
        let millis = Int((value - floor(value)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private func isVideoFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "ts", "mts"]
        return videoExtensions.contains(ext)
    }

    private func recognitionModeLabel(from diagnostics: [String]) -> String? {
        guard let line = diagnostics.first(where: { $0.hasPrefix("recognitionMode: ") }) else {
            return nil
        }
        let mode = line.replacingOccurrences(of: "recognitionMode: ", with: "")
        switch mode {
        case "onDeviceOnly", "onDeviceOnlyNoFallback", "onDeviceSpeechAnalyzer":
            return "オンデバイス"
        case "serverOnly":
            return "サーバー"
        default:
            return mode
        }
    }

    private func buildTranscriptionService(for mode: RecognitionMode) -> any TranscriptionService {
        switch mode {
        case .server:
            return SpeechURLTranscriptionService(recognitionStrategy: .serverOnly)
        case .onDevice:
            if SpeechAnalyzerTranscriptionService.isAvailable {
                return SpeechAnalyzerTranscriptionService()
            }
            return SpeechURLTranscriptionService(recognitionStrategy: .onDeviceOnly)
        }
    }
}
