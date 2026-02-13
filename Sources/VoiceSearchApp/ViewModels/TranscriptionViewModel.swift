import Foundation
import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import VoiceSearchCore

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var sourceURL: URL?
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

    private let transcriber: TranscriptionService
    private let pipeline: TranscriptionPipeline
    private let normalizer = DefaultTokenNormalizer()
    private let options = SearchOptions()

    private var rawTranscript: [TranscriptWord] = []
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var timeObserverPlayer: AVPlayer?
    private let fileDictionaryURL: URL

    private enum TranscriptExportFormat: String {
        case txt
        case srt

        var suggestedExtension: String { rawValue }
    }

    init(
        transcriber: TranscriptionService = HybridTranscriptionService(),
        pipeline: TranscriptionPipeline = TranscriptionPipeline()
    ) {
        self.transcriber = transcriber
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
        errorMessage = nil
        sourceURL = url

        if !queue.isEmpty {
            statusText = "\(1 + queue.count)件中現在処理: \(url.lastPathComponent)"
        } else {
            statusText = "解析中: \(url.lastPathComponent)"
        }

        let request = TranscriptionRequest(
            sourceURL: url,
            locale: nil,
            contextualStrings: transcriptionContextualStrings()
        )

        do {
            let output = try await pipeline.run(request, service: transcriber)
            rawTranscript = output.words
            applyDictionaryDisplayNormalization()

            detachTimeObserver()
            player = AVPlayer(url: url)

            let itemCount = transcript.count
            statusText = itemCount == 0
                ? "文字起こし結果が空です"
                : "\(itemCount)語を抽出"

            performSearch()
            startTimeObservation()
        } catch {
            errorMessage = error.localizedDescription
            statusText = "文字起こしに失敗"
            rawTranscript = []
            transcript = []
            searchHits = []
        }

        isAnalyzing = false
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
}
