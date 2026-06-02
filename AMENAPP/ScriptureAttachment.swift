//
//  ScriptureAttachment.swift
//  AMENAPP
//
//  Structured scripture attachment model for posts and drafts.
//  Replaces flat string-based verse storage with rich metadata.
//

import Foundation

// MARK: - Scripture Attachment

/// Structured model for a scripture attachment on a post or draft.
struct ScriptureAttachment: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let book: String
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int?
    let translation: String
    let canonicalReference: String   // e.g. "John 3:16" or "Romans 8:28-30"
    let displayReference: String     // formatted for display
    let previewText: String
    let source: AttachmentSource
    let createdAt: Date
    
    /// How the attachment was created
    enum AttachmentSource: String, Codable {
        case manualSearch
        case inlineSuggestion
        case recent
        case replace
        case quickAttach
        case popular
    }
    
    /// Whether this is a verse range (e.g. Romans 8:28-30)
    var isRange: Bool { verseEnd != nil && verseEnd != verseStart }
    
    /// Create from a BibleVerse (bridge from existing system)
    static func from(verse: BibleVerse, source: AttachmentSource = .manualSearch) -> ScriptureAttachment {
        let refString = verse.reference.displayString
        let bookName = verse.reference.book?.displayName ?? verse.reference.bookId.capitalized
        return ScriptureAttachment(
            id: UUID().uuidString,
            book: bookName,
            chapter: verse.reference.chapter,
            verseStart: verse.number,
            verseEnd: nil,
            translation: "",
            canonicalReference: refString,
            displayReference: refString,
            previewText: verse.text,
            source: source,
            createdAt: Date()
        )
    }

    /// Create from a BereanScriptureChip (inline suggestion path)
    static func from(chip: BereanScriptureChip, source: AttachmentSource = .inlineSuggestion) -> ScriptureAttachment {
        let parsed = ScriptureReferenceParser.parse(chip.reference)
        return ScriptureAttachment(
            id: UUID().uuidString,
            book: parsed.book,
            chapter: parsed.chapter,
            verseStart: parsed.verseStart,
            verseEnd: parsed.verseEnd,
            translation: chip.translation,
            canonicalReference: chip.reference,
            displayReference: chip.reference,
            previewText: chip.text,
            source: source,
            createdAt: Date()
        )
    }

    /// Convert back to BibleVerse for compatibility with existing drawer system
    var asBibleVerse: BibleVerse {
        let bookId = BibleBook.all.first(where: { $0.displayName == book })?.id ?? book.lowercased()
        let ref = ScriptureReference(bookId: bookId, chapter: chapter, startVerse: verseStart, endVerse: verseEnd)
        return BibleVerse(reference: ref, number: verseStart, text: previewText)
    }
    
    /// Firestore-compatible dictionary
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "book": book,
            "chapter": chapter,
            "verseStart": verseStart,
            "translation": translation,
            "canonicalReference": canonicalReference,
            "displayReference": displayReference,
            "previewText": previewText,
            "source": source.rawValue,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        if let verseEnd = verseEnd {
            data["verseEnd"] = verseEnd
        }
        return data
    }
    
    /// Reconstruct from Firestore data
    static func from(firestoreData data: [String: Any]) -> ScriptureAttachment? {
        guard let id = data["id"] as? String,
              let book = data["book"] as? String,
              let chapter = data["chapter"] as? Int,
              let verseStart = data["verseStart"] as? Int,
              let translation = data["translation"] as? String,
              let canonicalReference = data["canonicalReference"] as? String,
              let displayReference = data["displayReference"] as? String,
              let previewText = data["previewText"] as? String else {
            return nil
        }
        
        let sourceRaw = data["source"] as? String ?? "manualSearch"
        let source = AttachmentSource(rawValue: sourceRaw) ?? .manualSearch
        let timestamp = data["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970
        
        return ScriptureAttachment(
            id: id,
            book: book,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: data["verseEnd"] as? Int,
            translation: translation,
            canonicalReference: canonicalReference,
            displayReference: displayReference,
            previewText: previewText,
            source: source,
            createdAt: Date(timeIntervalSince1970: timestamp)
        )
    }
    
    /// Backwards-compatible: create from legacy verseReference + verseText strings
    static func from(legacyReference: String, legacyText: String?) -> ScriptureAttachment? {
        guard !legacyReference.isEmpty else { return nil }
        let parsed = ScriptureReferenceParser.parse(legacyReference)
        return ScriptureAttachment(
            id: UUID().uuidString,
            book: parsed.book,
            chapter: parsed.chapter,
            verseStart: parsed.verseStart,
            verseEnd: parsed.verseEnd,
            translation: "NIV",
            canonicalReference: legacyReference,
            displayReference: legacyReference,
            previewText: legacyText ?? "",
            source: .manualSearch,
            createdAt: Date()
        )
    }
}

// MARK: - Reference Parser

struct ScriptureReferenceParser {
    struct ParsedReference {
        let book: String
        let chapter: Int
        let verseStart: Int
        let verseEnd: Int?
    }
    
    /// Parse a reference string like "John 3:16" or "Romans 8:28-30" or "1 Corinthians 13:4-8"
    static func parse(_ reference: String) -> ParsedReference {
        let trimmed = reference
            .replacingOccurrences(of: "(NIV)", with: "")
            .replacingOccurrences(of: "(ESV)", with: "")
            .replacingOccurrences(of: "(KJV)", with: "")
            .replacingOccurrences(of: "(NKJV)", with: "")
            .replacingOccurrences(of: "(NLT)", with: "")
            .replacingOccurrences(of: "(NASB)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern: optional number + book name + chapter:verse[-verse]
        let pattern = #"^([1-3]?\s?[A-Za-z]+(?:\s[A-Za-z]+)?)\s+(\d+):(\d+)(?:\s?[-–]\s?(\d+))?$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            // Fallback: just return what we can
            return ParsedReference(book: trimmed, chapter: 1, verseStart: 1, verseEnd: nil)
        }
        
        let book = extractGroup(match, 1, from: trimmed) ?? trimmed
        let chapter = Int(extractGroup(match, 2, from: trimmed) ?? "1") ?? 1
        let verseStart = Int(extractGroup(match, 3, from: trimmed) ?? "1") ?? 1
        let verseEnd: Int? = {
            guard let endStr = extractGroup(match, 4, from: trimmed) else { return nil }
            return Int(endStr)
        }()
        
        return ParsedReference(book: book.trimmingCharacters(in: .whitespaces), chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
    }
    
    private static func extractGroup(_ match: NSTextCheckingResult, _ group: Int, from string: String) -> String? {
        guard group < match.numberOfRanges else { return nil }
        let range = match.range(at: group)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: string) else { return nil }
        return String(string[swiftRange])
    }
}

// MARK: - Prefetched Scripture Payload

/// Lightweight cached payload for instant SelahView launch
struct PrefetchedScripturePayload: Identifiable {
    let id: String  // cache key: "book_chapter:verse_translation"
    let attachment: ScriptureAttachment
    let nearbyVerses: [BibleVerse]
    let chapterTitle: String?
    let fetchedAt: Date
    
    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > 300 // 5 minutes
    }
    
    static func cacheKey(reference: String, translation: String) -> String {
        "\(reference)_\(translation)".lowercased().replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Verse Suggestion Context

/// Context for generating smart verse suggestions
struct VerseSuggestionContext {
    let draftText: String
    let recentVerses: [ScriptureAttachment]
    let activeTopicTag: String?
    let inferredTheme: VerseTopic?
    let confidence: Double
    
    static let empty = VerseSuggestionContext(
        draftText: "",
        recentVerses: [],
        activeTopicTag: nil,
        inferredTheme: nil,
        confidence: 0
    )
}

// MARK: - Recent Verse History

/// Manages recently used verse history (persisted locally)
@MainActor
final class RecentVerseHistory: ObservableObject {
    static let shared = RecentVerseHistory()
    
    @Published private(set) var recentVerses: [ScriptureAttachment] = []
    
    private let storageKey = "amen_recent_verse_history"
    private let maxHistory = 20
    
    private init() {
        loadHistory()
    }
    
    func addVerse(_ attachment: ScriptureAttachment) {
        // Remove duplicate if exists
        recentVerses.removeAll { $0.canonicalReference == attachment.canonicalReference }
        // Insert at front
        recentVerses.insert(attachment, at: 0)
        // Trim to max
        if recentVerses.count > maxHistory {
            recentVerses = Array(recentVerses.prefix(maxHistory))
        }
        saveHistory()
    }
    
    func clearHistory() {
        recentVerses = []
        saveHistory()
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScriptureAttachment].self, from: data) else {
            return
        }
        recentVerses = decoded
    }
    
    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(recentVerses) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
