import Foundation
import AppKit
import UniformTypeIdentifiers

public enum ItemProviderURLLoadError: Error {
    case missingURL
    case unsupportedRepresentation
}

public extension NSItemProvider {
    @MainActor
    func loadDroppedURL() async throws -> URL {
        let preferredTypes: [UTType] = [.fileURL, .movie, .audio, .item, .data]

        for type in preferredTypes where hasItemConformingToTypeIdentifier(type.identifier) {
            if let url = try await loadURLFromItem(typeIdentifier: type.identifier) {
                return url
            }
            if let url = try await loadURLFromFileRepresentation(typeIdentifier: type.identifier) {
                return url
            }
        }

        for identifier in registeredTypeIdentifiers {
            if let url = try await loadURLFromItem(typeIdentifier: identifier) {
                return url
            }
            if let url = try await loadURLFromFileRepresentation(typeIdentifier: identifier) {
                return url
            }
        }

        throw ItemProviderURLLoadError.missingURL
    }

    @MainActor
    private func loadURLFromItem(typeIdentifier: String) async throws -> URL? {
        guard hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let urlData = item as? Data,
                   let urlString = String(data: urlData, encoding: .utf8) {
                    if let url = URL(string: urlString) {
                        continuation.resume(returning: url)
                        return
                    }
                    continuation.resume(returning: URL(fileURLWithPath: urlString.removingPercentEncoding ?? urlString))
                    return
                }

                if let urlString = item as? String, let url = URL(string: urlString) {
                    continuation.resume(returning: url)
                    return
                }
                if let urlString = item as? String {
                    continuation.resume(returning: URL(fileURLWithPath: urlString))
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    @MainActor
    private func loadURLFromFileRepresentation(typeIdentifier: String) async throws -> URL? {
        guard hasItemConformingToTypeIdentifier(typeIdentifier) else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }

                // file representation URL can be temporary; copy to our temp dir.
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
