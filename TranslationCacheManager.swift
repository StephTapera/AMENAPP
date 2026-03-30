// TranslationCacheManager.swift
// AMEN App — Translation System
//
// Three-tier caching strategy:
//   L1: In-memory LRU (session-scoped, ~500 entries, instant)
//   L2: UserDefaults/disk (recently viewed, survives app restart, ~50 entries)
//   L3: Firestore global cache (cross-user dedup, cost optimization)
//
// Cache key: SHA256(normalizedText + "|" + sourceLang + "|" + targetLang + "|" + engineVersion)

import Foundation
import CryptoKit
import FirebaseFirestore

// MARK: - Cache Manager

@MainActor
final class TranslationCacheManager {

    static let shared = TranslationCacheManager()

    // MARK: - L1: In-Memory Cache (LRU, 500 cap)

    private var memoryCache: [String: MemoryCacheEntry] = [:]
    private var memoryCacheOrder: [String] = []
    private let memoryCacheMaxSize = 500

    // MARK: - L2: Disk Cache (UserDefaults, 50 entries)

    private let diskCacheKey = "amen.translation.diskCache"
    private let diskCacheMaxSize = 50
    private var diskCache: [String: DiskCacheEntry] = [:]

    // MARK: - L3: Firestore Cache

    private let db = Firestore.firestore()
    private let firestoreCacheCollection = "translations"

    // MARK: - Init

    private init() {
        loadDiskCache()
    }

    // MARK: - Public API

    /// Look up a translation across all cache tiers.
    /// Returns immediately from L1/L2, async for L3.
    func lookup(cacheKey: String) async -> String? {
        // L1: Memory
        if let entry = memoryCache[cacheKey], !entry.isExpired {
            touchMemoryEntry(cacheKey)
            return entry.translatedText
        }

        // L2: Disk
        if let entry = diskCache[cacheKey], !entry.isExpired {
            // Promote to L1
            insertMemory(cacheKey: cacheKey, translatedText: entry.translatedText)
            return entry.translatedText
        }

        // L3: Firestore (async)
        return await lookupFirestore(cacheKey: cacheKey)
    }

    /// Store a translation in all cache tiers.
    func store(
        cacheKey: String,
        originalText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        engine: TranslationEngine,
        isPublicContent: Bool
    ) async {
        // L1
        insertMemory(cacheKey: cacheKey, translatedText: translatedText)

        // L2
        insertDisk(cacheKey: cacheKey, translatedText: translatedText, isPublicContent: isPublicContent)

        // L3 — only for public content to respect privacy
        if isPublicContent {
            await storeFirestore(
                cacheKey: cacheKey,
                originalText: originalText,
                translatedText: translatedText,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                engine: engine
            )
        }
    }

    /// Invalidate a cache entry (e.g. post was edited)
    func invalidate(cacheKey: String) async {
        memoryCache.removeValue(forKey: cacheKey)
        memoryCacheOrder.removeAll(where: { $0 == cacheKey })
        diskCache.removeValue(forKey: cacheKey)
        saveDiskCache()
        await invalidateFirestore(cacheKey: cacheKey)
    }

    /// Build a deterministic cache key from content
    static func buildCacheKey(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        engineVersion: TranslationEngine = .gcpV3
    ) -> String {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let raw = "\(normalized)|\(sourceLanguage)|\(targetLanguage)|\(engineVersion.rawValue)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - L1 Memory Cache Helpers

    private struct MemoryCacheEntry {
        let translatedText: String
        let storedAt: Date
        // 1-hour TTL for in-memory entries
        var isExpired: Bool { Date().timeIntervalSince(storedAt) > 3600 }
    }

    private func insertMemory(cacheKey: String, translatedText: String) {
        if memoryCache.count >= memoryCacheMaxSize {
            evictLRUMemoryEntry()
        }
        memoryCache[cacheKey] = MemoryCacheEntry(translatedText: translatedText, storedAt: Date())
        memoryCacheOrder.removeAll(where: { $0 == cacheKey })
        memoryCacheOrder.append(cacheKey)
    }

    private func touchMemoryEntry(_ cacheKey: String) {
        memoryCacheOrder.removeAll(where: { $0 == cacheKey })
        memoryCacheOrder.append(cacheKey)
    }

    private func evictLRUMemoryEntry() {
        guard let oldest = memoryCacheOrder.first else { return }
        memoryCacheOrder.removeFirst()
        memoryCache.removeValue(forKey: oldest)
    }

    // MARK: - L2 Disk Cache Helpers

    private struct DiskCacheEntry: Codable {
        let cacheKey: String
        let translatedText: String
        let storedAt: Date
        let isPublicContent: Bool
        // 7-day TTL for disk entries
        var isExpired: Bool { Date().timeIntervalSince(storedAt) > 7 * 86400 }
    }

    private func insertDisk(cacheKey: String, translatedText: String, isPublicContent: Bool) {
        var mutableCache = diskCache

        // Evict oldest if at capacity
        if mutableCache.count >= diskCacheMaxSize {
            let oldest = mutableCache
                .sorted { $0.value.storedAt < $1.value.storedAt }
                .first?.key
            if let k = oldest { mutableCache.removeValue(forKey: k) }
        }

        mutableCache[cacheKey] = DiskCacheEntry(
            cacheKey: cacheKey,
            translatedText: translatedText,
            storedAt: Date(),
            isPublicContent: isPublicContent
        )
        diskCache = mutableCache
        saveDiskCache()
    }

    private func saveDiskCache() {
        guard let data = try? JSONEncoder().encode(diskCache) else { return }
        UserDefaults.standard.set(data, forKey: diskCacheKey)
    }

    private func loadDiskCache() {
        guard let data = UserDefaults.standard.data(forKey: diskCacheKey),
              let decoded = try? JSONDecoder().decode([String: DiskCacheEntry].self, from: data)
        else { return }
        // Prune expired entries on load
        diskCache = decoded.filter { !$0.value.isExpired }
    }

    // MARK: - L3 Firestore Cache Helpers

    private func lookupFirestore(cacheKey: String) async -> String? {
        do {
            let doc = try await db
                .collection(firestoreCacheCollection)
                .document(cacheKey)
                .getDocument()

            guard doc.exists,
                  let data = doc.data(),
                  let translatedText = data["translatedText"] as? String
            else { return nil }

            // Promote to L1 and L2
            insertMemory(cacheKey: cacheKey, translatedText: translatedText)
            let isPublic = data["isPublicContent"] as? Bool ?? true
            insertDisk(cacheKey: cacheKey, translatedText: translatedText, isPublicContent: isPublic)

            // Update access metadata (fire-and-forget)
            Task.detached(priority: .background) { [weak self] in
                try? await self?.db
                    .collection(self?.firestoreCacheCollection ?? "translations")
                    .document(cacheKey)
                    .updateData([
                        "lastAccessedAt": FieldValue.serverTimestamp(),
                        "accessCount": FieldValue.increment(Int64(1))
                    ])
            }

            return translatedText
        } catch {
            // L3 miss — not an error, just not cached
            return nil
        }
    }

    private func storeFirestore(
        cacheKey: String,
        originalText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        engine: TranslationEngine
    ) async {
        let entry: [String: Any] = [
            "cacheKey": cacheKey,
            "originalText": originalText,
            "translatedText": translatedText,
            "sourceLanguage": sourceLanguage,
            "targetLanguage": targetLanguage,
            "engineVersion": engine.rawValue,
            "characterCount": originalText.count,
            "isPublicContent": true,
            "createdAt": FieldValue.serverTimestamp(),
            "lastAccessedAt": FieldValue.serverTimestamp(),
            "accessCount": 1
        ]

        // Use merge to avoid overwriting if parallel writers race
        try? await db
            .collection(firestoreCacheCollection)
            .document(cacheKey)
            .setData(entry, merge: false)
    }

    private func invalidateFirestore(cacheKey: String) async {
        try? await db
            .collection(firestoreCacheCollection)
            .document(cacheKey)
            .delete()
    }
}
