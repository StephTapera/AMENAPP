// ContentMetadataExtractor.swift
// AMEN App — Community Around Content OS
//
// Fetches rich link metadata for a URL using LinkPresentation (LPMetadataProvider).
// Returns (title, subtitle, thumbnailURL) or nil values on failure.
// Has a 5-second timeout; never throws to its caller.
//
// Must run on the main actor: LPMetadataProvider requires main-thread dispatch.

import Foundation
import SwiftUI
import LinkPresentation

// MARK: - ContentMetadataExtractor

@MainActor
final class ContentMetadataExtractor {

    // MARK: - Constants

    private static let metadataTimeoutSeconds: TimeInterval = 5.0

    // MARK: - Public API

    /// Fetches LinkPresentation metadata for the given URL string.
    /// Always returns without throwing — failures produce nil values.
    /// - Parameter urlString: The raw URL to fetch metadata for.
    /// - Returns: A tuple of (title, subtitle, thumbnailURL), each of which may be nil.
    static func extract(
        from urlString: String
    ) async -> (title: String?, subtitle: String?, thumbnailURL: String?) {
        guard let url = URL(string: urlString) else {
            dlog("[ContentMetadataExtractor] invalid URL string: \(urlString)")
            return (nil, nil, nil)
        }

        do {
            let metadata = try await fetchWithTimeout(url: url)
            let title = metadata.title
            let subtitle = extractSubtitle(from: metadata)
            let thumbnailURL = await extractThumbnailURL(from: metadata)
            dlog("[ContentMetadataExtractor] extracted — title=\(title ?? "nil") subtitle=\(subtitle ?? "nil")")
            return (title, subtitle, thumbnailURL)
        } catch is CancellationError {
            dlog("[ContentMetadataExtractor] metadata fetch cancelled for \(urlString)")
            return (nil, nil, nil)
        } catch {
            dlog("[ContentMetadataExtractor] metadata fetch failed for \(urlString): \(error.localizedDescription)")
            return (nil, nil, nil)
        }
    }

    /// Returns a human-readable fallback title for cases where metadata could not be fetched.
    static func titleFallback(for kind: ContentObjectKind, rawURL: String) -> String {
        switch kind {
        case .song:          return "Shared Song"
        case .podcast:       return "Shared Podcast"
        case .book:          return "Shared Book"
        case .bibleVerse:    return rawURL.isEmpty ? "Bible Verse" : rawURL
        case .sermon:        return "Shared Sermon"
        case .video:         return "Shared Video"
        case .course:        return "Shared Course"
        case .event:         return "Shared Event"
        case .prayerRequest: return "Prayer Request"
        case .article:       return "Shared Article"
        case .testimony:     return "Shared Testimony"
        case .userPost:      return "Shared Post"
        }
    }

    // MARK: - Private helpers

    /// Wraps LPMetadataProvider in a Task with a timeout race.
    private static func fetchWithTimeout(url: URL) async throws -> LPLinkMetadata {
        try await withThrowingTaskGroup(of: LPLinkMetadata.self) { group in
            // Metadata fetch task.
            group.addTask {
                try await LPMetadataProvider().startFetchingMetadata(for: url)
            }

            // Timeout task.
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(metadataTimeoutSeconds * 1_000_000_000))
                throw MetadataExtractionError.timeout
            }

            // Return the first result (metadata or timeout error).
            defer { group.cancelAll() }
            return try await group.next() ?? { throw MetadataExtractionError.noResult }()
        }
    }

    /// Pulls a subtitle / description string from LPLinkMetadata.
    /// LPLinkMetadata doesn't expose a dedicated description field, so we fall back to
    /// the remote URL's host as a lightweight substitute.
    private static func extractSubtitle(from metadata: LPLinkMetadata) -> String? {
        // LPLinkMetadata.value is not public API; use the URL host as a serviceable subtitle.
        return metadata.url?.host
    }

    /// Converts the provider's image to a local-file URL string suitable for AsyncImage.
    /// Saves the image to a temp file if needed, returning the path string.
    private static func extractThumbnailURL(from metadata: LPLinkMetadata) async -> String? {
        guard let imageProvider = metadata.imageProvider else { return nil }
        return await withCheckedContinuation { continuation in
            imageProvider.loadObject(ofClass: URL.self) { object, error in
                if let url = object as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - MetadataExtractionError

private enum MetadataExtractionError: LocalizedError {
    case timeout
    case noResult

    var errorDescription: String? {
        switch self {
        case .timeout:   return "Metadata fetch timed out."
        case .noResult:  return "No metadata result returned."
        }
    }
}

// MARK: - LPMetadataProvider async bridge

private extension LPMetadataProvider {
    /// Async/await bridge for `startFetchingMetadata(for:completionHandler:)`.
    func startFetchingMetadata(for url: URL) async throws -> LPLinkMetadata {
        try await withCheckedThrowingContinuation { continuation in
            self.startFetchingMetadata(for: url) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let metadata = metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: MetadataExtractionError.noResult)
                }
            }
        }
    }
}
