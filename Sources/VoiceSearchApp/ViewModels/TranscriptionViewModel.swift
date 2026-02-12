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
    @Published var statusText: String = "ファイルをドラッグしてください"
    @Published var isAnalyzing = false
    @Published var query: String = ""
    @Published var searchHits: [SearchHit] = []
    @Published var highlightedIndex: Int? = nil
    @Published var currentTime: TimeInterval = 0
    @Published var isDropTargeted = false
    @Published var dictionaryEntries: [UserDictionaryEntry] = []
    @Published var newTermCanonical: String = ""
    @Published var newTermAliases: String = ""
    @Published var errorMessage: String?

    private let transcriber: TranscriptionService
    private let pipeline: TranscriptionPipeline
    private let normalizer = DefaultTokenNormalizer()
    private let options = SearchOptions()

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private let fileDictionaryURL: URL

    init(
        transcriber: TranscriptionService = SpeechURLTranscriptionService(),
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

    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
    }

    func addDictionaryEntry() {
        let canonical = newTermCanonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty else { return }

        let aliases = newTermAliases
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let entry = UserDictionaryEntry(canonical: canonical, aliases: aliases)
        dictionaryEntries.removeAll { normalizer.normalize($0.canonical) == normalizer.normalize(canonical) }
        dictionaryEntries.append(entry)
        newTermCanonical = ""
        newTermAliases = ""
        persistDictionary()
        performSearch()
    }

    func removeDictionaryEntry(_ entry: UserDictionaryEntry) {
        dictionaryEntries.removeAll {
            normalizer.normalize($0.canonical) == normalizer.normalize(entry.canonical)
        }
        persistDictionary()
        performSearch()
    }

    func handleDrop(providers: [NSItemProvider]) async -> Bool {
        guard !providers.isEmpty else { return false }

        for provider in providers {
            do {
                let url = try await provider.loadDroppedURL()
                await transcribe(url: url)
                return true
            } catch {
                errorMessage = "ドロップデータの読み込みに失敗: \(error.localizedDescription)"
            }
        }
        return false
    }

    func transcribe(url: URL) async {
        isAnalyzing = true
        errorMessage = nil
        sourceURL = url

        let request = TranscriptionRequest(sourceURL: url, locale: nil)

        do {
            let output = try await pipeline.run(request, service: transcriber)
            transcript = output.words
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
        searchHits = service.search(words: transcript, query: query, options: options)
    }

    func jump(to hit: SearchHit) {
        seek(to: hit.startTime)
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

    private func startTimeObservation() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        guard let player else { return }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 10)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let seconds = time.seconds
            self.currentTime = seconds
            self.highlightedIndex = PlaybackLocator.nearestWordIndex(at: seconds, in: self.transcript)
        }
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
}
