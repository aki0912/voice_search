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
                return AppL10n.text("recognition.mode.onDevice")
            case .server:
                return AppL10n.text("recognition.mode.server")
            }
        }
    }

    enum RecognitionLanguage: String, CaseIterable, Identifiable {
        case automatic
        case japanese
        case englishUS

        var id: String { rawValue }

        var displayLabel: String {
            switch self {
            case .automatic:
                return AppL10n.text("recognition.language.automatic")
            case .japanese:
                return AppL10n.text("recognition.language.japanese")
            case .englishUS:
                return AppL10n.text("recognition.language.englishUS")
            }
        }

        var locale: Locale? {
            switch self {
            case .automatic:
                return nil
            case .japanese:
                return Locale(identifier: "ja-JP")
            case .englishUS:
                return Locale(identifier: "en-US")
            }
        }
    }

    @Published var sourceURL: URL?
    @Published var isVideoSource = false
    @Published var transcript: [TranscriptWord] = []
    @Published var displayTranscript: [TranscriptWord] = []
    @Published var queue: [URL] = []
    @Published var statusText: String = AppL10n.text("status.dragFile")
    @Published var isAnalyzing = false
    @Published var query: String = ""
    @Published var isContainsMatchMode: Bool = true
    @Published var searchHits: [SearchHit] = []
    @Published var highlightedIndex: Int? = nil
    @Published var displayHighlightedIndex: Int? = nil
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var sourceDuration: TimeInterval = 0
    @Published var scrubPosition: TimeInterval = 0
    @Published var txtPauseLineBreakThreshold: TimeInterval = 0.1
    @Published var isDropTargeted = false
    @Published var dictionaryEntries: [UserDictionaryEntry] = []
    @Published var errorMessage: String?
    @Published var analysisProgress: Double = 0
    @Published var recognitionMode: RecognitionMode = .onDevice {
        didSet {
            guard recognitionMode != oldValue else { return }
            guard sourceURL != nil, !isAnalyzing else { return }
            statusText = AppL10n.format("status.modeChanged", recognitionMode.displayLabel)
        }
    }
    @Published var recognitionLanguage: RecognitionLanguage = .automatic {
        didSet {
            guard recognitionLanguage != oldValue else { return }
            guard sourceURL != nil, !isAnalyzing else { return }
            statusText = AppL10n.format("status.languageChanged", recognitionLanguage.displayLabel)
        }
    }

    private let pipeline: TranscriptionPipeline
    private let normalizer = DefaultTokenNormalizer()
    private let displayGrouper = TranscriptDisplayGrouper()
    private let options = SearchOptions()
    private let failureMessageFormatter = TranscriptionFailureMessageFormatter()
    private let failureLogWriter: any TranscriptionFailureLogWriting

    private var rawTranscript: [TranscriptWord] = []
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var timeObserverPlayer: AVPlayer?
    private var analysisProgressTask: Task<Void, Never>?
    private var isScrubbingPlayback = false
    private var scrubWasPlayingBeforeDrag = false
    private let fileDictionaryURL: URL

    private enum TranscriptExportFormat: String {
        case txt
        case srt

        var suggestedExtension: String { rawValue }
    }

    private struct FailingTranscriptionService: TranscriptionService {
        let message: String

        func transcribe(request: TranscriptionRequest) async throws -> TranscriptionOutput {
            throw TranscriptionServiceError.invalidInput(message)
        }
    }

    init(
        pipeline: TranscriptionPipeline = TranscriptionPipeline(),
        appSupportDirectory: URL? = nil,
        failureLogWriter: (any TranscriptionFailureLogWriting)? = nil
    ) {
        self.pipeline = pipeline

        let support = appSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let appDirectoryURL = support.appendingPathComponent("voice_search", isDirectory: true)
        fileDictionaryURL = appDirectoryURL
            .appendingPathComponent("dictionary.json")
        self.failureLogWriter = failureLogWriter
            ?? FileTranscriptionFailureLogWriter(
                directoryURL: appDirectoryURL.appendingPathComponent("failure_logs", isDirectory: true)
            )

        do {
            try FileManager.default.createDirectory(at: fileDictionaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            loadDictionary()
        } catch {
            errorMessage = AppL10n.format(
                "error.prepareSettingsDirectory",
                error.localizedDescription
            )
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
                errorMessage = AppL10n.format(
                    "error.loadDroppedData",
                    error.localizedDescription
                )
            }
        }

        guard hasNewFiles else { return false }

        if !isAnalyzing {
            await processQueue()
        }
        return true
    }

    func clearLoadedMedia() {
        queue.removeAll()
        rawTranscript = []
        transcript = []
        displayTranscript = []
        searchHits = []
        highlightedIndex = nil
        displayHighlightedIndex = nil
        currentTime = 0
        sourceDuration = 0
        scrubPosition = 0
        analysisProgress = 0
        isPlaying = false
        isScrubbingPlayback = false
        scrubWasPlayingBeforeDrag = false
        sourceURL = nil
        isVideoSource = false
        isDropTargeted = false
        errorMessage = nil
        statusText = AppL10n.text("status.dragFile")
        detachTimeObserver()
        player = nil
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
            statusText = AppL10n.format(
                "status.processingQueuedFile",
                1 + queue.count,
                url.lastPathComponent
            )
        } else {
            statusText = AppL10n.format("status.analyzingFile", url.lastPathComponent)
        }

        let contextualStrings = transcriptionContextualStrings()

        do {
            let output = try await transcribeWithSelectedLanguage(
                sourceURL: url,
                contextualStrings: contextualStrings
            )
            rawTranscript = output.words
            applyDictionaryDisplayNormalization()

            detachTimeObserver()
            player = AVPlayer(url: url)
            sourceDuration = output.duration ?? 0
            if !sourceDuration.isFinite || sourceDuration < 0 {
                sourceDuration = 0
            }
            currentTime = 0
            scrubPosition = 0
            isScrubbingPlayback = false
            scrubWasPlayingBeforeDrag = false
            displayHighlightedIndex = nil
            isPlaying = false

            let itemCount = transcript.count
            let modeText = recognitionModeLabel(from: output.diagnostics)
            if itemCount == 0 {
                statusText = AppL10n.text("status.emptyTranscript")
            } else if let modeText {
                statusText = AppL10n.format("status.extractedWordsWithMode", itemCount, modeText)
            } else {
                statusText = AppL10n.format("status.extractedWords", itemCount)
            }
            if let sourceDuration = output.duration, sourceDuration > 30, itemCount <= 3 {
                errorMessage = AppL10n.format(
                    "error.lowWordCount",
                    itemCount,
                    Int(sourceDuration)
                )
            }

            performSearch()
            startTimeObservation()
            didSucceed = true
        } catch {
            resetUIStateAfterTranscriptionFailure()
            let formattedMessage = formattedFailureMessage(for: error, mode: recognitionMode)
            let failureLogURL = persistFailureLog(
                error: error,
                sourceURL: url,
                formattedMessage: formattedMessage
            )
            errorMessage = failureMessageWithLogPath(
                formattedMessage: formattedMessage,
                failureLogURL: failureLogURL
            )
            statusText = AppL10n.format("status.transcriptionFailed", recognitionMode.displayLabel)
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

    func jump(toDisplayWordAt index: Int) {
        guard index >= 0 && index < displayTranscript.count else { return }
        seek(to: displayTranscript[index].startTime)
    }

    func displayContextText(for hit: SearchHit) -> String {
        guard !displayTranscript.isEmpty else { return hit.displayText }
        let target = hit.displayText.trimmingCharacters(in: .whitespacesAndNewlines)

        let containsHitRange = displayTranscript.filter { line in
            line.startTime <= hit.startTime && line.endTime >= hit.endTime
        }
        if let text = bestDisplayContextText(from: containsHitRange, target: target, anchorTime: hit.startTime) {
            return text
        }

        let overlapsHitRange = displayTranscript.filter { line in
            line.endTime >= hit.startTime && line.startTime <= hit.endTime
        }
        if let text = bestDisplayContextText(from: overlapsHitRange, target: target, anchorTime: hit.startTime) {
            return text
        }

        if let text = bestDisplayContextText(from: displayTranscript, target: target, anchorTime: hit.startTime) {
            return text
        }

        return hit.displayText
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        let clampedSeconds = clampedTime(seconds)
        let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        let tolerance = finalSeekTolerance()
        player.currentItem?.cancelPendingSeeks()
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = clampedSeconds
        scrubPosition = clampedSeconds
        highlightedIndex = PlaybackLocator.nearestWordIndex(at: clampedSeconds, in: transcript)
        displayHighlightedIndex = PlaybackLocator.nearestWordIndex(at: clampedSeconds, in: displayTranscript)
        player.play()
        isPlaying = true
    }

    func playPause() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func beginScrubbing() {
        guard !isScrubbingPlayback else { return }
        scrubWasPlayingBeforeDrag = player?.timeControlStatus == .playing
        player?.pause()
        isPlaying = false
        isScrubbingPlayback = true
    }

    func updateScrubPosition(_ value: TimeInterval) {
        let clamped = clampedTime(value)
        scrubPosition = clamped
        currentTime = clamped
        highlightedIndex = PlaybackLocator.nearestWordIndex(at: clamped, in: transcript)
        displayHighlightedIndex = PlaybackLocator.nearestWordIndex(at: clamped, in: displayTranscript)

        guard let player else { return }
        guard !isScrubbingPlayback else { return }

        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance = interactiveSeekTolerance()
        player.currentItem?.cancelPendingSeeks()
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func endScrubbing() {
        let target = scrubPosition
        isScrubbingPlayback = false
        let shouldResume = scrubWasPlayingBeforeDrag
        scrubWasPlayingBeforeDrag = false

        guard let player else { return }
        let clampedSeconds = clampedTime(target)
        let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        let tolerance = finalSeekTolerance()
        player.currentItem?.cancelPendingSeeks()
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = clampedSeconds
        scrubPosition = clampedSeconds
        highlightedIndex = PlaybackLocator.nearestWordIndex(at: clampedSeconds, in: transcript)
        displayHighlightedIndex = PlaybackLocator.nearestWordIndex(at: clampedSeconds, in: displayTranscript)
        if shouldResume {
            player.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
    }

    func exportTranscriptToFile() {
        guard !transcript.isEmpty else {
            errorMessage = AppL10n.text("error.noTranscriptToExport")
            return
        }

        guard let format = promptExportFormat() else { return }

        let panel = NSSavePanel()
        panel.title = AppL10n.text("export.panel.title")
        panel.prompt = AppL10n.text("common.save")
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
            statusText = AppL10n.format("status.exportedText", destinationURL.lastPathComponent)
        } catch {
            errorMessage = AppL10n.format("error.exportFailed", error.localizedDescription)
        }
    }

    func updateTxtPauseLineBreakThreshold(_ value: TimeInterval) {
        guard value.isFinite else { return }
        txtPauseLineBreakThreshold = min(max(0, value), 2.0)
    }

    private func startTimeObservation() {
        detachTimeObserver()
        guard let player else { return }

        let interval = CMTime(seconds: 0.2, preferredTimescale: 10)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let itemDuration = player.currentItem?.duration.seconds,
                   itemDuration.isFinite,
                   itemDuration > 0 {
                    self.sourceDuration = itemDuration
                }
                self.isPlaying = player.timeControlStatus == .playing
                guard !self.isScrubbingPlayback else { return }
                self.currentTime = seconds
                self.scrubPosition = self.clampedTime(seconds)
                self.highlightedIndex = PlaybackLocator.nearestWordIndex(at: seconds, in: self.transcript)
                self.displayHighlightedIndex = PlaybackLocator.nearestWordIndex(at: seconds, in: self.displayTranscript)
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

    private func transcribeWithSelectedLanguage(
        sourceURL: URL,
        contextualStrings: [String]
    ) async throws -> TranscriptionOutput {
        if recognitionLanguage == .automatic {
            return try await transcribeByAutoDetectingLanguage(
                sourceURL: sourceURL,
                contextualStrings: contextualStrings
            )
        }

        return try await runTranscription(
            sourceURL: sourceURL,
            locale: recognitionLanguage.locale,
            contextualStrings: contextualStrings
        )
    }

    private func transcribeByAutoDetectingLanguage(
        sourceURL: URL,
        contextualStrings: [String]
    ) async throws -> TranscriptionOutput {
        let candidates = automaticLocaleCandidates()
        guard !candidates.isEmpty else {
            return try await runTranscription(
                sourceURL: sourceURL,
                locale: Locale.current,
                contextualStrings: contextualStrings
            )
        }

        var bestResult: (locale: Locale, output: TranscriptionOutput, score: Double)?
        var firstError: Error?

        for (index, locale) in candidates.enumerated() {
            statusText = AppL10n.format("status.autoDetectingLanguage", displayName(for: locale))
            do {
                let output = try await runTranscription(
                    sourceURL: sourceURL,
                    locale: locale,
                    contextualStrings: contextualStrings,
                    progressMapper: { [total = candidates.count] progress in
                        let scaled = (Double(index) + progress.fractionCompleted) / Double(total)
                        return TranscriptionProgress(
                            fractionCompleted: scaled,
                            recognizedDuration: progress.recognizedDuration,
                            totalDuration: progress.totalDuration
                        )
                    }
                )

                let score = autoDetectionScore(for: output)
                if let current = bestResult {
                    if score > current.score {
                        bestResult = (locale, output, score)
                    }
                } else {
                    bestResult = (locale, output, score)
                }

                if output.words.count >= 40 {
                    break
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let bestResult {
            var diagnostics = bestResult.output.diagnostics
            diagnostics.append("detectedLocale: \(bestResult.locale.identifier)")
            diagnostics.append("languageSelection: automatic")
            return TranscriptionOutput(
                sourceURL: bestResult.output.sourceURL,
                words: bestResult.output.words,
                locale: bestResult.locale,
                duration: bestResult.output.duration,
                diagnostics: diagnostics
            )
        }

        if let firstError {
            throw firstError
        }
        throw TranscriptionServiceError.emptyTranscript
    }

    private func runTranscription(
        sourceURL: URL,
        locale: Locale?,
        contextualStrings: [String],
        progressMapper: @escaping @Sendable (TranscriptionProgress) -> TranscriptionProgress = { $0 }
    ) async throws -> TranscriptionOutput {
        let request = TranscriptionRequest(
            sourceURL: sourceURL,
            locale: locale,
            contextualStrings: contextualStrings,
            progressHandler: { [weak self] progress in
                let mapped = progressMapper(progress)
                Task { @MainActor [weak self] in
                    self?.mergeAnalysisProgress(mapped)
                }
            }
        )

        let service = buildTranscriptionService(for: recognitionMode)
        return try await pipeline.run(request, service: service)
    }

    private func automaticLocaleCandidates() -> [Locale] {
        var seen = Set<String>()
        var locales: [Locale] = []

        func appendLocale(_ locale: Locale?) {
            guard let locale else { return }
            let key = locale.identifier.lowercased()
            if seen.insert(key).inserted {
                locales.append(locale)
            }
        }

        appendLocale(Locale.current)
        for preferred in Locale.preferredLanguages.prefix(3) {
            appendLocale(Locale(identifier: preferred))
        }
        appendLocale(Locale(identifier: "ja-JP"))
        appendLocale(Locale(identifier: "en-US"))

        return locales
    }

    private func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    private func autoDetectionScore(for output: TranscriptionOutput) -> Double {
        let wordCount = Double(output.words.count)
        let coveredDuration = max(0, (output.words.last?.endTime ?? 0) - (output.words.first?.startTime ?? 0))
        let sourceDuration = max(1, output.duration ?? coveredDuration)
        let coverageRate = max(0, min(1, coveredDuration / sourceDuration))

        // Prefer outputs with both enough words and broader time coverage.
        return wordCount + (coverageRate * 100)
    }

    private func loadDictionary() {
        guard FileManager.default.fileExists(atPath: fileDictionaryURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileDictionaryURL)
            let decoded = try JSONDecoder().decode([UserDictionaryEntry].self, from: data)
            dictionaryEntries = decoded
        } catch {
            errorMessage = AppL10n.format("error.dictionaryLoadFailed", error.localizedDescription)
        }
    }

    private func persistDictionary() {
        do {
            let data = try JSONEncoder().encode(dictionaryEntries)
            try data.write(to: fileDictionaryURL, options: .atomic)
        } catch {
            errorMessage = AppL10n.format("error.dictionarySaveFailed", error.localizedDescription)
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
            displayTranscript = []
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
        displayTranscript = displayGrouper.group(words: transcript)
    }

    private func promptExportFormat() -> TranscriptExportFormat? {
        let alert = NSAlert()
        alert.messageText = AppL10n.text("export.format.title")
        alert.informativeText = AppL10n.text("export.format.message")
        alert.addButton(withTitle: "SRT")
        alert.addButton(withTitle: "TXT")
        alert.addButton(withTitle: AppL10n.text("common.cancel"))

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
        let plain = TranscriptPlainTextFormatter(
            pauseLineBreakThreshold: min(max(0, txtPauseLineBreakThreshold), 2.0)
        ).format(words: transcript)
        let timed = transcript.map { word in
            "[\(formatTimeForExport(word.startTime)) - \(formatTimeForExport(word.endTime))] \(word.text)"
        }.joined(separator: "\n")

        return """
        \(AppL10n.text("export.txt.header.transcript"))
        \(plain)

        \(AppL10n.text("export.txt.header.timedWords"))
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
            return AppL10n.text("recognition.mode.onDevice")
        case "serverOnly":
            return AppL10n.text("recognition.mode.server")
        default:
            return mode
        }
    }

    private func formattedFailureMessage(for error: Error, mode: RecognitionMode) -> String {
        failureMessageFormatter.format(modeLabel: mode.displayLabel, error: error)
    }

    private func resetUIStateAfterTranscriptionFailure() {
        rawTranscript = []
        transcript = []
        displayTranscript = []
        searchHits = []
        highlightedIndex = nil
        displayHighlightedIndex = nil
        currentTime = 0
        sourceDuration = 0
        scrubPosition = 0
        isPlaying = false
        isScrubbingPlayback = false
        scrubWasPlayingBeforeDrag = false
        detachTimeObserver()
        player = nil
    }

    private func clampedTime(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return 0 }
        guard sourceDuration.isFinite, sourceDuration > 0 else {
            return max(0, value)
        }
        return min(max(0, value), sourceDuration)
    }

    private func distance(from time: TimeInterval, to word: TranscriptWord) -> TimeInterval {
        if time < word.startTime {
            return word.startTime - time
        }
        if time > word.endTime {
            return time - word.endTime
        }
        return 0
    }

    private func bestDisplayContextText(
        from candidates: [TranscriptWord],
        target: String,
        anchorTime: TimeInterval
    ) -> String? {
        guard !candidates.isEmpty else { return nil }

        if !target.isEmpty {
            let matched = candidates.filter { candidate in
                candidate.text.range(
                    of: target,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
            guard !matched.isEmpty else { return nil }
            return matched.min { lhs, rhs in
                distance(from: anchorTime, to: lhs) < distance(from: anchorTime, to: rhs)
            }?.text
        }

        return candidates.min { lhs, rhs in
            distance(from: anchorTime, to: lhs) < distance(from: anchorTime, to: rhs)
        }?.text
    }

    private func interactiveSeekTolerance() -> CMTime {
        let seconds: TimeInterval
        if sourceDuration >= 3600 {
            seconds = 2.0
        } else if sourceDuration >= 1200 {
            seconds = 1.0
        } else {
            seconds = 0.35
        }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func finalSeekTolerance() -> CMTime {
        let seconds: TimeInterval
        if sourceDuration >= 3600 {
            seconds = 0.75
        } else if sourceDuration >= 1200 {
            seconds = 0.4
        } else {
            seconds = 0.15
        }
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func persistFailureLog(
        error: Error,
        sourceURL: URL,
        formattedMessage: String
    ) -> URL? {
        let entry = TranscriptionFailureLogEntry(
            occurredAt: Date(),
            recognitionMode: recognitionMode.displayLabel,
            sourceURL: sourceURL,
            statusText: statusText,
            query: query,
            containsMatchEnabled: isContainsMatchMode,
            pendingQueue: queue,
            errorType: String(reflecting: type(of: error)),
            errorDescription: error.localizedDescription,
            formattedMessage: formattedMessage
        )

        return try? failureLogWriter.write(entry)
    }

    private func failureMessageWithLogPath(
        formattedMessage: String,
        failureLogURL: URL?
    ) -> String {
        guard let failureLogURL else { return formattedMessage }
        return AppL10n.format("error.failureMessageWithLogPath", formattedMessage, failureLogURL.path)
    }

    private func buildTranscriptionService(for mode: RecognitionMode) -> any TranscriptionService {
        switch mode {
        case .server:
            return SpeechURLTranscriptionService(recognitionStrategy: .serverOnly)
        case .onDevice:
            if SpeechAnalyzerTranscriptionService.isAvailable {
                return SpeechAnalyzerTranscriptionService()
            }
            return FailingTranscriptionService(
                message: AppL10n.text("error.speechAnalyzerUnavailable")
            )
        }
    }
}
