import Foundation
import AppKit
import UniformTypeIdentifiers

public enum ItemProviderURLLoadError: Error {
    case missingURL
    case unsupportedRepresentation
}

public extension NSItemProvider {
    func loadDroppedURL() async throws -> URL {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return try await withCheckedThrowingContinuation { continuation in
                loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    if let url = item as? URL {
                        continuation.resume(returning: url)
                        return
                    }

                    if let urlData = item as? Data,
                       let urlString = String(data: urlData, encoding: .utf8),
                       let url = URL(string: urlString) ?? URL(fileURLWithPath: urlString.removingPercentEncoding ?? urlString) {
                        continuation.resume(returning: url)
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

                    continuation.resume(throwing: ItemProviderURLLoadError.unsupportedRepresentation)
                }
            }
        }

        throw ItemProviderURLLoadError.missingURL
    }
}
