//
//  ScripturePrefetchManager.swift
//  AMENAPP
//
//  LRU-based prefetch cache for scripture payloads.
//  Enables near-instant SelahView launch when tapping scripture pills.
//

import Foundation

@MainActor
final class ScripturePrefetchManager {
    static let shared = ScripturePrefetchManager()
    
    private var cache: [String: PrefetchedScripturePayload] = [:]
    private var accessOrder: [String] = [] // LRU tracking
    private let maxCacheSize = 15
    private var activeFetches: Set<String> = []
    
    private init() {}
    
    // MARK: - Public API
    
    /// Prefetch payload for a scripture attachment
    func prefetch(attachment: ScriptureAttachment) {
        let key = PrefetchedScripturePayload.cacheKey(
            reference: attachment.canonicalReference,
            translation: attachment.translation
        )
        
        // Skip if already cached and fresh
        if let existing = cache[key], !existing.isStale {
            touchKey(key)
            return
        }
        
        // Skip if already fetching
        guard !activeFetches.contains(key) else { return }
        activeFetches.insert(key)
        
        Task {
            defer { activeFetches.remove(key) }
            
            var nearbyVerses: [BibleVerse] = []
            
            // Fetch nearby verses for context
            let version = translationToVersion(attachment.translation)
            
            do {
                // Fetch surrounding verses
                let chapter = attachment.chapter
                let verseNum = attachment.verseStart
                
                // Try to get 2 verses before and after
                let beforeRef = "\(attachment.book) \(chapter):\(max(1, verseNum - 2))-\(max(1, verseNum - 1))"
                let afterRef = "\(attachment.book) \(chapter):\(verseNum + 1)-\(verseNum + 2)"
                
                async let beforeFetch = fetchVerseQuietly(reference: beforeRef, version: version)
                async let afterFetch = fetchVerseQuietly(reference: afterRef, version: version)
                
                let (before, after) = await (beforeFetch, afterFetch)
                if let b = before { nearbyVerses.append(b) }
                if let a = after { nearbyVerses.append(a) }
            }
            
            let payload = PrefetchedScripturePayload(
                id: key,
                attachment: attachment,
                nearbyVerses: nearbyVerses,
                chapterTitle: "\(attachment.book) \(attachment.chapter)",
                fetchedAt: Date()
            )
            
            storePayload(payload, forKey: key)
        }
    }
    
    /// Get cached payload if available
    func getCachedPayload(for attachment: ScriptureAttachment) -> PrefetchedScripturePayload? {
        let key = PrefetchedScripturePayload.cacheKey(
            reference: attachment.canonicalReference,
            translation: attachment.translation
        )
        
        guard let payload = cache[key], !payload.isStale else {
            return nil
        }
        
        touchKey(key)
        return payload
    }
    
    /// Evict all stale entries
    func evictStale() {
        let staleKeys = cache.filter { $0.value.isStale }.map { $0.key }
        for key in staleKeys {
            cache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
    }
    
    /// Clear entire cache
    func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
    }
    
    // MARK: - Private
    
    private func storePayload(_ payload: PrefetchedScripturePayload, forKey key: String) {
        // Evict LRU if at capacity
        while cache.count >= maxCacheSize, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
        
        cache[key] = payload
        touchKey(key)
    }
    
    private func touchKey(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
    
    private func fetchVerseQuietly(reference: String, version: ScripturePassage.BibleVersion) async -> BibleVerse? {
        do {
            let passage = try await YouVersionBibleService.shared.fetchVerse(reference: reference, version: version)
            let parsed = ScriptureReferenceParser.parse(passage.reference)
            let bookId = BibleBook.all.first(where: { $0.displayName == parsed.book })?.id ?? parsed.book.lowercased()
            let ref = ScriptureReference(bookId: bookId, chapter: parsed.chapter, startVerse: parsed.verseStart, endVerse: parsed.verseEnd)
            return BibleVerse(reference: ref, number: parsed.verseStart, text: passage.text, translation: version.rawValue)
        } catch {
            return nil
        }
    }
    
    private func translationToVersion(_ translation: String) -> ScripturePassage.BibleVersion {
        switch translation.uppercased() {
        case "ESV": return .esv
        case "NIV": return .niv
        case "KJV": return .kjv
        case "NKJV": return .nkjv
        case "NLT": return .nlt
        case "NASB": return .nasb
        default: return .niv
        }
    }
}
