// AmenSmartLinkService.swift
// AMENAPP
//
// Client-side smart link detection service.
// URL pattern matching and scripture reference detection only —
// all metadata resolution is performed server-side via Cloud Function.
//
// Usage:
//   let kind = AmenSmartLinkDetector.detect(urlString: "https://youtube.com/watch?v=abc")
//   let refs  = AmenSmartLinkDetector.detectScriptureReferences(in: composerText)

import Foundation
import Combine
import SwiftUI

// MARK: - AmenLinkResolutionState

enum AmenLinkResolutionState: Equatable {
    case idle
    case detecting
    case loading
    case resolved(AmenMediaAttachment)
    case failed(String)
}

// MARK: - AmenSmartLinkDetector

/// Stateless client-side detector. Performs URL pattern matching and
/// scripture reference detection with no network calls.
struct AmenSmartLinkDetector {

    // MARK: - URL Kind Detection

    /// Returns the detected `AmenMediaKind` for the given URL, or `nil` if
    /// the string is not a valid URL or no pattern matches.
    static func detect(urlString: String) -> AmenMediaKind? {
        guard let url = URL(string: urlString) else { return nil }
        return detect(url: url)
    }

    /// Returns the detected `AmenMediaKind` for the given URL, or `nil` if
    /// no pattern matches.
    static func detect(url: URL) -> AmenMediaKind? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()

        // ---- Video ----
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .video
        }
        if host == "vimeo.com" || host.hasSuffix(".vimeo.com") {
            return .video
        }

        // ---- Podcast ----
        if host == "open.spotify.com" && path.contains("/episode/") {
            return .podcast
        }
        if host == "podcasts.apple.com" || host.hasSuffix(".podcasts.apple.com") {
            return .podcast
        }

        // ---- Music ----
        if host == "open.spotify.com" &&
            (path.contains("/track/") || path.contains("/album/")) {
            return .music
        }
        if host == "music.apple.com" || host.hasSuffix(".music.apple.com") {
            return .music
        }

        // ---- Book ----
        if host.contains("goodreads.com") {
            return .book
        }
        if host.contains("books.google.com") {
            return .book
        }
        if host.contains("amazon.com") || host.contains("amazon.co.") {
            return amazonKind(path: path)
        }

        // ---- Scripture ----
        if host == "bible.com" || host.hasSuffix(".bible.com") ||
           host.contains("youversion.com") {
            return .scripture
        }

        // ---- Generic fallback for any https URL ----
        if url.scheme == "https" || url.scheme == "http" {
            return .link
        }

        return nil
    }

    // MARK: - Timestamp Extraction

    /// Extracts a start time from common URL timestamp parameters and returns
    /// the value in milliseconds, or `nil` if no timestamp is present.
    ///
    /// Supported formats: `?t=90`, `?t=1m30s`, `?start=90`, `#t=90`
    static func extractStartMs(from url: URL) -> Int? {
        // Check query items first
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let queryItems = components.queryItems ?? []
            for item in queryItems {
                let key = item.name.lowercased()
                if (key == "t" || key == "start"), let value = item.value {
                    return parseTimestampToMs(value)
                }
            }
            // Check fragment (#t=90)
            if let fragment = components.fragment {
                let fragmentParts = fragment.components(separatedBy: "=")
                if fragmentParts.count == 2,
                   fragmentParts[0].lowercased() == "t" {
                    return parseTimestampToMs(fragmentParts[1])
                }
            }
        }
        return nil
    }

    // MARK: - Scripture Reference Detection

    /// Detects scripture references in free text and returns an array of
    /// (reference, range) tuples ordered by their position in the string.
    ///
    /// Supported formats:
    ///   "John 3:16", "1 John 3:16", "Genesis 1:1-3",
    ///   "Ps 23", "Psalm 23:1-6", "1 Cor 13:4-7"
    static func detectScriptureReferences(
        in text: String
    ) -> [(reference: String, range: Range<String.Index>)] {
        guard !text.isEmpty else { return [] }

        let pattern = scriptureRegexPattern
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)

        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let reference = String(text[range]).trimmingCharacters(in: .whitespaces)
            return (reference: reference, range: range)
        }
    }

    // MARK: - Private Helpers

    private static func amazonKind(path: String) -> AmenMediaKind {
        // Amazon book detection: path contains "/dp/" with book category hints
        // or explicit book-related path segments
        let bookPatterns = ["/dp/", "/books/", "/kindle-ebooks/", "/christian-books/"]
        let isBook = bookPatterns.contains { path.contains($0) }
        return isBook ? .book : .product
    }

    /// Parses timestamp strings like "90", "1m30s", "1:30" into milliseconds.
    private static func parseTimestampToMs(_ value: String) -> Int? {
        // Plain integer seconds: "90"
        if let seconds = Int(value) {
            return seconds * 1000
        }

        // "1m30s" format
        let minsSecsPattern = #"(?:(\d+)m)?(?:(\d+)s?)?"#
        if let regex = try? NSRegularExpression(pattern: minsSecsPattern),
           let match = regex.firstMatch(
               in: value,
               range: NSRange(value.startIndex..., in: value)
           ) {
            var totalMs = 0
            if let minuteRange = Range(match.range(at: 1), in: value),
               let minutes = Int(value[minuteRange]) {
                totalMs += minutes * 60 * 1000
            }
            if let secondRange = Range(match.range(at: 2), in: value),
               let seconds = Int(value[secondRange]) {
                totalMs += seconds * 1000
            }
            if totalMs > 0 { return totalMs }
        }

        return nil
    }

    /// Regex pattern covering major Bible book names and common abbreviations,
    /// followed by an optional chapter:verse reference.
    private static let scriptureRegexPattern: String = {
        // Numbered books (1-3 prefix)
        let numberedBooks =
            "(?:1st?|2nd?|3rd?|I{1,3}|[123])\\s*" +
            "(?:John|Samuel|Sam|Kings|Kgs|Chronicles|Chr|Corinthians|Cor|" +
            "Thessalonians|Thess|Thes|Timothy|Tim|Peter|Pet|Macabees|Mac|" +
            "Esdras|Maccabees)"

        // Standard books (no numeric prefix)
        let standardBooks =
            "Genesis|Gen|Exodus|Exod|Exo|Leviticus|Lev|Numbers|Num|" +
            "Deuteronomy|Deut|Deu|Joshua|Josh|Judges|Judg|Ruth|" +
            "Ezra|Nehemiah|Neh|Esther|Est|Job|" +
            "Psalms?|Psa?|Proverbs|Prov|Pro|Ecclesiastes|Eccl|Ecc|" +
            "Song of Solomon|Song of Songs?|SOS|Song|" +
            "Isaiah|Isa|Jeremiah|Jer|Lamentations|Lam|Ezekiel|Ezek|Eze|Daniel|Dan|" +
            "Hosea|Hos|Joel|Amos|Obadiah|Obad|Jonah|Jon|Micah|Mic|Nahum|Nah|" +
            "Habakkuk|Hab|Zephaniah|Zeph|Haggai|Hag|Zechariah|Zech|Malachi|Mal|" +
            "Matthew|Matt|Mat|Mark|Luke|Luk|John|Acts|Romans|Rom|" +
            "Galatians|Gal|Ephesians|Eph|Philippians|Phil|Colossians|Col|" +
            "Philemon|Phlm|Hebrews|Heb|James|Jas|Jude|Revelation|Rev"

        // Full pattern: (numbered | standard) chapter[:verse[-endVerse]]
        let bookGroup = "(?:\(numberedBooks)|\(standardBooks))"
        let chapterVerse = "\\d+(?::\\d+(?:-\\d+)?)?"
        return "\\b\(bookGroup)\\.?\\s+\(chapterVerse)\\b"
    }()
}

// MARK: - AmenSmartAttachmentManager

/// Manages the paste-to-detect pipeline for the post composer.
/// Processes text changes, resolves URLs via stub server simulation,
/// and maintains the ordered list of pending attachments.
@MainActor
final class AmenSmartAttachmentManager: ObservableObject {

    // MARK: Published State

    @Published var resolutionState: AmenLinkResolutionState = .idle
    @Published var pendingAttachments: [AmenMediaAttachment] = []

    // MARK: Private State

    private var processingTask: Task<Void, Never>?
    /// Tracks URLs already resolved so re-typing the same URL is a no-op.
    private var resolvedURLs: Set<String> = []

    // MARK: - Text Processing

    /// Called whenever the composer text changes.
    /// Detects URLs and scripture references, then resolves novel ones.
    func processText(_ text: String) async {
        // Cancel any in-flight detection
        processingTask?.cancel()

        processingTask = Task {
            guard !Task.isCancelled else { return }

            resolutionState = .detecting

            // 1. Extract all URLs from text
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let urlMatches = detector?.matches(in: text, options: [], range: fullRange) ?? []

            let urls: [URL] = urlMatches.compactMap { match in
                guard let range = Range(match.range, in: text) else { return nil }
                return URL(string: String(text[range]))
            }

            // 2. Detect scripture references in plain text
            let scriptureRefs = AmenSmartLinkDetector.detectScriptureReferences(in: text)

            guard !Task.isCancelled else { return }

            // 3. Resolve novel URLs
            var didResolveAny = false
            for url in urls {
                let urlString = url.absoluteString
                guard !resolvedURLs.contains(urlString) else { continue }
                guard let kind = AmenSmartLinkDetector.detect(url: url) else { continue }

                resolutionState = .loading
                let attachment = await resolveURL(url, kind: kind)

                guard !Task.isCancelled else { return }

                resolvedURLs.insert(urlString)
                pendingAttachments.append(attachment)
                resolutionState = .resolved(attachment)
                didResolveAny = true
            }

            // 4. Resolve novel scripture text references (only first unresolved one)
            if !didResolveAny, let firstRef = scriptureRefs.first {
                let refKey = "scripture:\(firstRef.reference)"
                if !resolvedURLs.contains(refKey) {
                    resolutionState = .loading
                    let attachment = stubScriptureAttachment(reference: firstRef.reference)
                    resolvedURLs.insert(refKey)
                    pendingAttachments.append(attachment)
                    resolutionState = .resolved(attachment)
                }
            }

            if !didResolveAny && scriptureRefs.isEmpty {
                resolutionState = .idle
            }
        }

        await processingTask?.value
    }

    // MARK: - Attachment Management

    func addAttachment(_ attachment: AmenMediaAttachment) {
        guard !pendingAttachments.contains(where: { $0.id == attachment.id }) else { return }
        pendingAttachments.append(attachment)
    }

    func removeAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func moveAttachment(from source: IndexSet, to destination: Int) {
        pendingAttachments.move(fromOffsets: source, toOffset: destination)
    }

    func clearAll() {
        pendingAttachments.removeAll()
        resolvedURLs.removeAll()
        resolutionState = .idle
        processingTask?.cancel()
    }

    // MARK: - Stub Resolution (simulates server response)

    /// Returns a realistic stub `AmenMediaAttachment` for the given URL and kind.
    /// Replace with actual Cloud Function call in production.
    private func resolveURL(_ url: URL, kind: AmenMediaKind) async -> AmenMediaAttachment {
        // Simulate network latency
        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s

        let startMs = AmenSmartLinkDetector.extractStartMs(from: url) ?? 0

        switch kind {
        case .video:
            return stubVideoAttachment(url: url, startMs: startMs)
        case .podcast:
            return stubPodcastAttachment(url: url)
        case .music:
            return stubMusicAttachment(url: url)
        case .article:
            return stubArticleAttachment(url: url)
        case .book:
            return stubBookAttachment(url: url)
        case .product:
            return stubProductAttachment(url: url)
        case .scripture:
            return stubScriptureAttachment(reference: "John 3:16")
        case .link:
            return stubLinkAttachment(url: url)
        }
    }

    // MARK: Stub Builders

    private func stubVideoAttachment(url: URL, startMs: Int) -> AmenMediaAttachment {
        let videoID = extractYouTubeID(from: url) ?? "dQw4w9WgXcQ"
        return AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .video,
            sourceURL: url.absoluteString,
            title: "The Power of Faith — Sunday Sermon",
            subtitle: "Grace Community Church",
            thumbnailURL: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg",
            accentHex: "FF0000",
            playable: AmenPlayableInfo(
                transport: .youtubeEmbed,
                mediaURL: url.absoluteString,
                durationMs: 3_720_000,
                startMs: startMs
            ),
            timeline: AmenMediaTimeline(
                segmentKind: .chapter,
                segments: [
                    AmenTimedSegment(id: 0, startMs: 0, endMs: 600_000, label: "Introduction", words: nil, thumbnailURL: nil),
                    AmenTimedSegment(id: 1, startMs: 600_000, endMs: 2_100_000, label: "Main Scripture", words: nil, thumbnailURL: nil),
                    AmenTimedSegment(id: 2, startMs: 2_100_000, endMs: nil, label: "Application", words: nil, thumbnailURL: nil),
                ],
                isWordSynced: false
            ),
            videoDetails: AmenVideoDetails(
                channelName: "Grace Community Church",
                youtubeVideoID: videoID,
                hasChapters: true
            )
        )
    }

    private func stubPodcastAttachment(url: URL) -> AmenMediaAttachment {
        AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .podcast,
            sourceURL: url.absoluteString,
            title: "Walking By Faith, Not By Sight — Ep. 142",
            subtitle: "The Daily Grace Podcast",
            thumbnailURL: nil,
            accentHex: "9B59B6",
            playable: AmenPlayableInfo(
                transport: .nativeAudio,
                mediaURL: url.absoluteString,
                durationMs: 2_820_000,
                startMs: 0
            ),
            podcastDetails: AmenPodcastDetails(
                showName: "The Daily Grace Podcast",
                episodeNumber: 142,
                speedOptions: [0.75, 1.0, 1.25, 1.5, 2.0]
            )
        )
    }

    private func stubMusicAttachment(url: URL) -> AmenMediaAttachment {
        AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .music,
            sourceURL: url.absoluteString,
            title: "Oceans (Where Feet May Fail)",
            subtitle: "Hillsong UNITED · Zion",
            thumbnailURL: nil,
            accentHex: "1DB954",
            playable: AmenPlayableInfo(
                transport: .external,
                mediaURL: url.absoluteString,
                durationMs: 428_000,
                startMs: 0
            ),
            musicDetails: AmenMusicDetails(
                artists: ["Hillsong UNITED"],
                albumArtURL: nil,
                displayMode: .compact
            )
        )
    }

    private func stubArticleAttachment(url: URL) -> AmenMediaAttachment {
        let domain = url.host ?? "thegospelcoalition.org"
        return AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .article,
            sourceURL: url.absoluteString,
            title: "Five Ways to Deepen Your Daily Scripture Reading",
            subtitle: domain,
            thumbnailURL: nil,
            accentHex: nil,
            articleDetails: AmenArticleDetails(
                sourceName: "The Gospel Coalition",
                faviconURL: "https://\(domain)/favicon.ico",
                readingTimeMinutes: 4,
                excerpt: "Consistency in Bible reading transforms not just what we know, but who we are becoming."
            )
        )
    }

    private func stubBookAttachment(url: URL) -> AmenMediaAttachment {
        AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .book,
            sourceURL: url.absoluteString,
            title: "Mere Christianity",
            subtitle: "C.S. Lewis",
            thumbnailURL: nil,
            accentHex: "8B4513",
            bookDetails: AmenBookDetails(
                authorName: "C.S. Lewis",
                coverURL: nil,
                isbn: "9780060652920",
                rating: 4.8,
                blurb: "A timeless defense of the Christian faith, originally delivered as radio broadcasts during World War II."
            )
        )
    }

    private func stubProductAttachment(url: URL) -> AmenMediaAttachment {
        AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .product,
            sourceURL: url.absoluteString,
            title: "ESV Study Bible, Large Print",
            subtitle: "Crossway",
            thumbnailURL: nil,
            accentHex: nil,
            productDetails: AmenProductDetails(
                merchantName: "Amazon",
                imageURL: nil,
                isAffiliate: true,
                safetyLabel: nil
            )
        )
    }

    private func stubScriptureAttachment(reference: String) -> AmenMediaAttachment {
        AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .scripture,
            sourceURL: nil,
            title: reference,
            subtitle: "NIV",
            thumbnailURL: nil,
            accentHex: "D4AF37",
            scriptureDetails: AmenScriptureDetails(
                reference: reference,
                verseText: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
                translation: "NIV",
                youVersionDeepLink: "youversion://bible?reference=\(reference.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? reference)"
            )
        )
    }

    private func stubLinkAttachment(url: URL) -> AmenMediaAttachment {
        let domain = url.host ?? url.absoluteString
        return AmenMediaAttachment(
            id: UUID().uuidString,
            kind: .link,
            sourceURL: url.absoluteString,
            title: "Shared Link",
            subtitle: domain,
            thumbnailURL: nil,
            accentHex: nil,
            linkDetails: AmenLinkDetails(
                domain: domain,
                ogTitle: "A resource worth reading",
                ogDescription: "Shared via AMEN",
                ogImageURL: nil
            )
        )
    }

    // MARK: - URL Utilities

    private func extractYouTubeID(from url: URL) -> String? {
        // youtu.be/ID
        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.dropFirst().first
        }
        // youtube.com/watch?v=ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        return nil
    }
}
