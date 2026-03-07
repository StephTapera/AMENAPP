//
//  LinkPreviewService.swift
//  AMENAPP
//
//  Link preview metadata fetch, cache, and Bible-URL detection.
//  Uses one LPMetadataProvider per request so fetches can run
//  concurrently and be individually cancelled.
//

import Foundation
import SwiftUI
import Combine
import LinkPresentation

// MARK: - Preview type

enum LinkPreviewType: String, Codable {
    case link   // Standard URL preview
    case verse  // Bible verse card
}

// MARK: - Metadata model

struct LinkPreviewMetadata: Codable, Identifiable, Equatable {
    let id: String          // == url.absoluteString
    let url: URL
    let previewType: LinkPreviewType
    let title: String?
    let description: String?
    let imageURL: URL?
    let siteName: String?
    // Verse-specific
    let verseReference: String?
    let verseText: String?

    init(
        url: URL,
        previewType: LinkPreviewType = .link,
        title: String? = nil,
        description: String? = nil,
        imageURL: URL? = nil,
        siteName: String? = nil,
        verseReference: String? = nil,
        verseText: String? = nil
    ) {
        self.id = url.absoluteString
        self.url = url
        self.previewType = previewType
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.siteName = siteName
        self.verseReference = verseReference
        self.verseText = verseText
    }
}

// MARK: - Service

@MainActor
final class LinkPreviewService: ObservableObject {
    static let shared = LinkPreviewService()

    // In-memory cache: url string → metadata
    private var cache: [String: LinkPreviewMetadata] = [:]
    // In-flight task per URL to avoid duplicate fetches
    private var inFlight: [String: Task<LinkPreviewMetadata, Error>] = [:]

    private init() { loadDiskCache() }

    // MARK: - Public API

    /// Detect first HTTP/S URL in text.
    func detectFirstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)
            .flatMap { Range($0.range, in: text) }
            .flatMap { URL(string: String(text[$0])) }
            .flatMap { $0.scheme == "http" || $0.scheme == "https" ? $0 : nil }
    }

    /// All HTTP/S URLs in text (for chat send-time attachment building).
    func detectURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap { Range($0.range, in: text).flatMap { URL(string: String(text[$0])) } }
            .filter { $0.scheme == "http" || $0.scheme == "https" }
    }

    /// Fetch metadata (cache-first, deduped in-flight).
    func fetchMetadata(for url: URL) async throws -> LinkPreviewMetadata {
        let key = url.absoluteString

        // 1. Cache hit
        if let cached = cache[key] { return cached }

        // 2. De-duplicate: reuse existing task
        if let existing = inFlight[key] { return try await existing.value }

        // 3. Bible URL → fast local path
        if let ref = BibleURLParser.extractReference(from: url) {
            let meta = LinkPreviewMetadata(
                url: url,
                previewType: .verse,
                title: ref.displayReference,
                siteName: url.host,
                verseReference: ref.displayReference,
                verseText: nil   // caller can enrich via YouVersionBibleService if desired
            )
            store(meta, for: key)
            return meta
        }

        // 4. Standard LPMetadataProvider fetch
        let task = Task<LinkPreviewMetadata, Error> { [weak self] in
            let provider = LPMetadataProvider()
            provider.shouldFetchSubresources = false  // privacy: no script execution
            provider.timeout = 10

            let lp = try await provider.startFetchingMetadata(for: url)

            // Fetch the image data and convert to a data: URL so it survives
            // cross-process boundary (Widget Extension, etc.)
            var imageURL: URL? = nil
            if let imageProvider = lp.imageProvider {
                imageURL = await withCheckedContinuation { cont in
                    imageProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                        if let img = obj as? UIImage,
                           let jpeg = img.jpegData(compressionQuality: 0.7) {
                            // Store thumbnail on disk; vend file URL
                            let filename = key
                                .replacingOccurrences(of: "/", with: "_")
                                .replacingOccurrences(of: ":", with: "_")
                                .prefix(80)
                            let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                                .appendingPathComponent("link_thumbs", isDirectory: true)
                            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                            let file = dir.appendingPathComponent(String(filename) + ".jpg")
                            try? jpeg.write(to: file)
                            cont.resume(returning: file)
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            }

            let meta = LinkPreviewMetadata(
                url: url,
                previewType: .link,
                title: lp.title,
                description: nil,
                imageURL: imageURL,
                siteName: lp.originalURL?.host ?? url.host
            )

            await MainActor.run { [meta] in
                self?.store(meta, for: key)
                self?.inFlight.removeValue(forKey: key)
            }
            return meta
        }

        inFlight[key] = task

        do {
            return try await task.value
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }

    /// Cancel any in-flight fetch for a URL (e.g. user removed preview).
    func cancelFetch(for url: URL) {
        let key = url.absoluteString
        inFlight[key]?.cancel()
        inFlight.removeValue(forKey: key)
    }

    /// Synchronous cache lookup — use in feed rendering to avoid re-fetch.
    func getCached(for url: URL) -> LinkPreviewMetadata? { cache[url.absoluteString] }

    // MARK: - Private

    private func store(_ meta: LinkPreviewMetadata, for key: String) {
        cache[key] = meta
        saveDiskCache()
    }

    // MARK: - Disk cache (Codable JSON, thumbnails on disk already)

    private var cacheFileURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("link_preview_meta_cache.json")
    }

    private func loadDiskCache() {
        Task.detached(priority: .background) { [weak self] in
            guard let self,
                  let data = try? Data(contentsOf: await self.cacheFileURL),
                  let decoded = try? JSONDecoder().decode([String: LinkPreviewMetadata].self, from: data) else { return }
            await MainActor.run { self.cache = decoded }
        }
    }

    private func saveDiskCache() {
        let snapshot = cache
        let url = cacheFileURL
        Task.detached(priority: .background) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url)
        }
    }
}

// MARK: - Bible URL Parser

struct BibleURLParser {

    struct ParsedVerseReference {
        let displayReference: String   // "John 3:16"
        let book: String
        let chapter: Int
        let verseStart: Int
        let verseEnd: Int?
    }

    // Known Bible-app domains
    private static let bibleDomains: Set<String> = [
        "bible.com", "www.bible.com",
        "youversion.com", "www.youversion.com",
        "biblegateway.com", "www.biblegateway.com",
        "blueletterbible.org", "www.blueletterbible.org",
        "biblehub.com", "www.biblehub.com",
        "esv.org", "www.esv.org",
        "bibleref.com", "www.bibleref.com",
    ]

    static func isBibleURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return bibleDomains.contains(host) || host.hasSuffix("bible.com")
    }

    /// Attempt to extract a verse reference from the URL path/query.
    /// Returns nil if no verse reference could be parsed.
    static func extractReference(from url: URL) -> ParsedVerseReference? {
        guard isBibleURL(url) else { return nil }

        // Decode the full URL string for pattern matching
        let raw = url.absoluteString.removingPercentEncoding ?? url.absoluteString

        return parseVerseFromString(raw)
    }

    /// Also useful for extracting references from pasted URL text in the composer.
    static func parseVerseFromString(_ text: String) -> ParsedVerseReference? {
        // Pattern covers:
        //   John+3:16  John%203:16  John.3.16  john-3-16  John_3_16
        //   Gen 1:1-3  Ephesians 2:8-9
        let pattern = #"(?i)\b(Genesis|Gen|Exodus|Exod?|Leviticus|Lev|Numbers|Num|Deuteronomy|Deut?|Joshua|Josh?|Judges|Judg?|Ruth|1\s*Samuel|1\s*Sam|2\s*Samuel|2\s*Sam|1\s*Kings?|2\s*Kings?|1\s*Chronicles?|1\s*Chron?|2\s*Chronicles?|2\s*Chron?|Ezra|Nehemiah|Neh|Esther|Esth?|Job|Psalms?|Ps(?:alm)?|Proverbs?|Prov?|Ecclesiastes|Eccl?|Song\s*of\s*Solomon|Song|Isaiah|Isa?|Jeremiah|Jer|Lamentations|Lam|Ezekiel|Ezek?|Daniel|Dan|Hosea|Hos|Joel|Amos|Obadiah|Obad?|Jonah|Jon|Micah|Mic|Nahum|Nah|Habakkuk|Hab|Zephaniah|Zeph?|Haggai|Hag|Zechariah|Zech?|Malachi|Mal|Matthew|Matt?|Mark|Luke|John|Acts|Romans|Rom|1\s*Corinthians?|1\s*Cor|2\s*Corinthians?|2\s*Cor|Galatians?|Gal|Ephesians?|Eph|Philippians?|Phil|Colossians?|Col|1\s*Thessalonians?|1\s*Thess?|2\s*Thessalonians?|2\s*Thess?|1\s*Timothy|1\s*Tim|2\s*Timothy|2\s*Tim|Titus|Tit|Philemon|Phlm?|Hebrews?|Heb|James|Jas|1\s*Peter|1\s*Pet|2\s*Peter|2\s*Pet|1\s*John|2\s*John|3\s*John|Jude|Revelation|Rev)\s*[\s\.\+_-]?(\d{1,3})[\s\.\+_:%-](\d{1,3})(?:[-–](\d{1,3}))?"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else { return nil }

        let bookRange = Range(match.range(at: 1), in: text)
        let chapterRange = Range(match.range(at: 2), in: text)
        let verseStartRange = Range(match.range(at: 3), in: text)
        let verseEndRange = match.range(at: 4).location != NSNotFound ? Range(match.range(at: 4), in: text) : nil

        guard let bRange = bookRange, let cRange = chapterRange, let vsRange = verseStartRange else { return nil }

        let book = String(text[bRange])
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "%20", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard let chapter = Int(String(text[cRange])),
              let verseStart = Int(String(text[vsRange])) else { return nil }
        let verseEnd = verseEndRange.flatMap { Int(String(text[$0])) }

        var ref = "\(book) \(chapter):\(verseStart)"
        if let ve = verseEnd { ref += "-\(ve)" }

        return ParsedVerseReference(
            displayReference: ref,
            book: book,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd
        )
    }
}
