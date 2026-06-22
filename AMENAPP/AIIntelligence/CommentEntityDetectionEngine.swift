// CommentEntityDetectionEngine.swift
// AMENAPP — Smart Comments Wave 3
//
// Client-side entity pre-detection. Fast local pre-check; server is authoritative.
// Results are used for optimistic UI only — never as a moderation gate.
//
// INVARIANT: crisisSignal entities are NEVER surfaced to UI — for internal routing only.

import Foundation

@MainActor
final class CommentEntityDetectionEngine {

    // MARK: - Public API

    /// Detects entities in the given comment body.
    /// Returns an empty array when `commentEntityDetectionEnabled` is OFF.
    /// Max 10 entities returned per comment.
    static func detect(in body: String) -> [DetectedEntity] {
        guard AMENFeatureFlags.shared.commentEntityDetectionEnabled else { return [] }
        guard !body.isEmpty else { return [] }

        var entities: [DetectedEntity] = []

        // Bible references: e.g. "John 3:16", "1 Corinthians 13:4-7", "Ps 23:1"
        entities.append(contentsOf: detectBibleReferences(in: body))

        // URLs
        entities.append(contentsOf: detectLinks(in: body))

        // Prayer request (first occurrence only)
        if let entity = detectFirstMatch(
            pattern: #"(?i)\b(pray for|prayer request|please pray)\b"#,
            kind: .prayerRequest,
            in: body
        ) {
            entities.append(entity)
        }

        // Testimony (first occurrence only)
        if let entity = detectFirstMatch(
            pattern: #"(?i)\b(testimony|God answered|miracle)\b"#,
            kind: .testimony,
            in: body
        ) {
            entities.append(entity)
        }

        // Question sentences (first occurrence only — sentence ending with ?)
        if let entity = detectFirstQuestion(in: body) {
            entities.append(entity)
        }

        // Crisis signal — detected but NEVER surfaced; for routing only
        if let entity = detectFirstMatch(
            pattern: #"(?i)\b(suicid|self.harm|end my life|kill myself|hurt myself|hopeless|can't go on)\b"#,
            kind: .crisisSignal,
            in: body
        ) {
            entities.append(entity)
        }

        // Deduplicate (same kind + overlapping range) and cap at 10
        let deduped = deduplicate(entities)
        return Array(deduped.prefix(10))
    }

    // MARK: - Bible Reference Detection

    private static func detectBibleReferences(in body: String) -> [DetectedEntity] {
        // Pattern covers: "John 3:16", "1 Cor. 13:4-7", "Psalm 23:1", "1 Timothy 3:16-17"
        let pattern = #"(\d?\s?[A-Za-z]+\.?\s?\d+:\d+(-\d+)?)"#
        return detectAll(pattern: pattern, kind: .bibleReference, in: body)
    }

    // MARK: - Link Detection

    private static func detectLinks(in body: String) -> [DetectedEntity] {
        // Standard URL pattern: http/https or bare www.
        let pattern = #"(https?://[^\s]+|www\.[^\s]+)"#
        return detectAll(pattern: pattern, kind: .link, in: body)
    }

    // MARK: - Question Detection (first sentence ending in ?)

    private static func detectFirstQuestion(in body: String) -> DetectedEntity? {
        // Split into rough sentences; look for a ? terminator
        let sentencePattern = #"[^.!?]*\?"#
        guard let regex = try? NSRegularExpression(pattern: sentencePattern, options: []) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else {
            return nil
        }
        let rawText = nsBody.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }
        return DetectedEntity(
            kind: .question,
            rawText: rawText,
            startIndex: match.range.location,
            endIndex: match.range.location + match.range.length,
            metadata: [:]
        )
    }

    // MARK: - Generic Helpers

    private static func detectAll(pattern: String, kind: DetectedEntityKind, in body: String) -> [DetectedEntity] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        let matches = regex.matches(in: body, options: [], range: range)
        return matches.compactMap { match -> DetectedEntity? in
            let rawText = nsBody.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { return nil }
            return DetectedEntity(
                kind: kind,
                rawText: rawText,
                startIndex: match.range.location,
                endIndex: match.range.location + match.range.length,
                metadata: [:]
            )
        }
    }

    private static func detectFirstMatch(pattern: String, kind: DetectedEntityKind, in body: String) -> DetectedEntity? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else {
            return nil
        }
        let rawText = nsBody.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }
        return DetectedEntity(
            kind: kind,
            rawText: rawText,
            startIndex: match.range.location,
            endIndex: match.range.location + match.range.length,
            metadata: [:]
        )
    }

    /// Removes entities with duplicate kinds when they are not links or bibleReferences
    /// (which may legitimately appear multiple times). For unique-per-comment kinds, keeps first.
    private static func deduplicate(_ entities: [DetectedEntity]) -> [DetectedEntity] {
        let allowMultiple: Set<DetectedEntityKind> = [.bibleReference, .bibleVerse, .link, .musicMention, .videoLink]
        var seen: Set<DetectedEntityKind> = []
        var result: [DetectedEntity] = []
        for entity in entities {
            if allowMultiple.contains(entity.kind) {
                result.append(entity)
            } else if !seen.contains(entity.kind) {
                seen.insert(entity.kind)
                result.append(entity)
            }
        }
        return result
    }

    private init() {}
}
