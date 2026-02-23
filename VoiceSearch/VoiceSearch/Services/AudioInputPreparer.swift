import AVFoundation
import AudioToolbox
import Foundation

struct PreparedAudioInput: Sendable {
    let url: URL
    let cleanupURL: URL?
}

enum AudioInputPreparationError: Error {
    case invalidInput(String)
}

extension AudioInputPreparationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .invalidInput(message):
            return message
        }
    }
}

struct AudioTrackCandidate: Equatable, Sendable {
    let trackID: CMPersistentTrackID
    let startTime: TimeInterval
    let duration: TimeInterval
    let isPreferredSubtype: Bool
}

struct AudioInputPreparer {
    private static let audioOnlyExtensions: Set<String> = [
        "m4a", "mp3", "wav", "caf", "aac", "aiff", "flac", "ogg", "opus",
    ]

    private static let preferredSubtypes: Set<FourCharCode> = [
        kAudioFormatMPEG4AAC,
        kAudioFormatMPEG4AAC_HE,
        kAudioFormatLinearPCM,
        kAudioFormatAppleLossless,
        kAudioFormatMPEGLayer3,
        kAudioFormatOpus,
        kAudioFormatFLAC,
    ]

    static func prepare(from sourceURL: URL) async throws -> PreparedAudioInput {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioInputPreparationError.invalidInput("No audio track found in input file.")
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let shouldExtract = requiresExtraction(
            fileExtension: sourceURL.pathExtension.lowercased(),
            audioTrackCount: audioTracks.count,
            hasVideoTrack: !videoTracks.isEmpty
        )
        guard shouldExtract else {
            return PreparedAudioInput(url: sourceURL, cleanupURL: nil)
        }

        let candidates = await makeCandidates(from: audioTracks)
        let prioritizedCandidates = prioritizeTrackCandidates(candidates)
        let tracksByID = Dictionary(uniqueKeysWithValues: audioTracks.map { ($0.trackID, $0) })

        var errors: [String] = []
        for candidate in prioritizedCandidates {
            guard let track = tracksByID[candidate.trackID] else { continue }
            do {
                let extractedURL = try await extractAudioTrack(from: track)
                return PreparedAudioInput(url: extractedURL, cleanupURL: extractedURL)
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        let errorMessage = errors.first ?? "Audio extraction failed."
        throw AudioInputPreparationError.invalidInput(errorMessage)
    }

    static func requiresExtraction(
        fileExtension: String,
        audioTrackCount: Int,
        hasVideoTrack: Bool
    ) -> Bool {
        hasVideoTrack || !audioOnlyExtensions.contains(fileExtension.lowercased()) || audioTrackCount > 1
    }

    static func prioritizeTrackCandidates(_ candidates: [AudioTrackCandidate]) -> [AudioTrackCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            if lhs.duration != rhs.duration {
                return lhs.duration > rhs.duration
            }
            if lhs.isPreferredSubtype != rhs.isPreferredSubtype {
                return lhs.isPreferredSubtype && !rhs.isPreferredSubtype
            }
            return lhs.trackID < rhs.trackID
        }
    }

    private static func makeCandidates(from tracks: [AVAssetTrack]) async -> [AudioTrackCandidate] {
        var candidates: [AudioTrackCandidate] = []
        candidates.reserveCapacity(tracks.count)

        for track in tracks {
            let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
            let subtype = formatDescriptions.first.map(CMFormatDescriptionGetMediaSubType)
            let timeRange = (try? await track.load(.timeRange)) ?? .zero

            candidates.append(
                AudioTrackCandidate(
                    trackID: track.trackID,
                    startTime: safeSeconds(timeRange.start),
                    duration: safeSeconds(timeRange.duration),
                    isPreferredSubtype: subtype.map { preferredSubtypes.contains($0) } ?? false
                )
            )
        }

        return candidates
    }

    private static func safeSeconds(_ time: CMTime) -> TimeInterval {
        let value = CMTimeGetSeconds(time)
        return value.isFinite ? value : 0
    }

    private static func extractAudioTrack(from selectedTrack: AVAssetTrack) async throws -> URL {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioInputPreparationError.invalidInput("Failed to prepare audio composition.")
        }

        let selectedRange = try await selectedTrack.load(.timeRange)
        try compositionTrack.insertTimeRange(selectedRange, of: selectedTrack, at: .zero)

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioInputPreparationError.invalidInput("Failed to create audio extractor.")
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: destinationURL)

        exporter.outputURL = destinationURL
        exporter.outputFileType = .m4a
        let exportBox = ExportSessionBox(exporter: exporter)

        try await withCheckedThrowingContinuation { continuation in
            exportBox.exporter.exportAsynchronously {
                switch exportBox.exporter.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(
                        throwing: AudioInputPreparationError.invalidInput(
                            exportBox.exporter.error?.localizedDescription ?? "Audio extraction failed."
                        )
                    )
                case .cancelled:
                    continuation.resume(throwing: AudioInputPreparationError.invalidInput("Audio extraction cancelled."))
                default:
                    continuation.resume(throwing: AudioInputPreparationError.invalidInput("Audio extraction did not complete."))
                }
            }
        }

        let extractedAsset = AVURLAsset(url: destinationURL)
        let extractedAudioTracks = try await extractedAsset.loadTracks(withMediaType: .audio)
        guard !extractedAudioTracks.isEmpty else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw AudioInputPreparationError.invalidInput("Extracted audio track is empty.")
        }

        return destinationURL
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let exporter: AVAssetExportSession

    init(exporter: AVAssetExportSession) {
        self.exporter = exporter
    }
}
