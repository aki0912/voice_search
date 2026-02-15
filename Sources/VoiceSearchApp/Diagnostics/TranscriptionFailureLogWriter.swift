import Foundation

struct TranscriptionFailureLogEntry: Sendable {
    let occurredAt: Date
    let recognitionMode: String
    let sourceURL: URL
    let statusText: String
    let query: String
    let containsMatchEnabled: Bool
    let pendingQueue: [URL]
    let errorType: String
    let errorDescription: String
    let formattedMessage: String
}

protocol TranscriptionFailureLogWriting {
    func write(_ entry: TranscriptionFailureLogEntry) throws -> URL
}

struct FileTranscriptionFailureLogWriter: TranscriptionFailureLogWriting {
    let directoryURL: URL
    private let fileManager: FileManager

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    func write(_ entry: TranscriptionFailureLogEntry) throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let filename = "failure_\(timestampToken(entry.occurredAt))_\(UUID().uuidString).log"
        let destinationURL = directoryURL.appendingPathComponent(filename)
        try render(entry).write(to: destinationURL, atomically: true, encoding: .utf8)
        return destinationURL
    }

    private func timestampToken(_ date: Date) -> String {
        let ms = Int(date.timeIntervalSince1970 * 1000)
        return String(ms)
    }

    private func render(_ entry: TranscriptionFailureLogEntry) -> String {
        let occurredAt = ISO8601DateFormatter().string(from: entry.occurredAt)
        let queueLines = entry.pendingQueue.isEmpty
            ? "- (none)"
            : entry.pendingQueue.map { "- \($0.path)" }.joined(separator: "\n")

        return """
        VoiceSearch Failure Log
        occurredAt: \(occurredAt)
        recognitionMode: \(entry.recognitionMode)
        sourceURL: \(entry.sourceURL.path)
        statusText: \(entry.statusText)
        query: \(entry.query)
        containsMatchEnabled: \(entry.containsMatchEnabled)
        pendingQueueCount: \(entry.pendingQueue.count)
        pendingQueue:
        \(queueLines)
        errorType: \(entry.errorType)
        errorDescription: \(entry.errorDescription)

        formattedMessage:
        \(entry.formattedMessage)
        """
    }
}
