// CachePolicy.swift
// AMEN App — P2 FIX: Centralized cache strategy contract
//
// Before this, each of the ~228 services implemented its own caching
// (TTL, stale check, NSCache, UserDefaults) with no shared vocabulary.
// This protocol gives cache sites a uniform interface so invalidation,
// warming, and size management can be reasoned about consistently.
//
// Adopters: ImageCache, RecommendationIntelligenceService,
//           HomeFeedAlgorithm (UserInterests), SearchService (recent searches)

import Foundation

// MARK: - CachePolicy Protocol

/// Describes the TTL and capacity constraints of a cache.
protocol CachePolicy {
    /// Maximum time an entry is considered valid. `nil` = never expires.
    var ttl: TimeInterval? { get }
    /// Maximum number of entries. `nil` = unlimited (rely on memory pressure).
    var maxEntries: Int? { get }
    /// Maximum total byte size. `nil` = unlimited.
    var maxBytes: Int? { get }
    /// Whether to evict expired entries proactively on every write,
    /// or only lazily on read. Default: lazy.
    var evictsOnWrite: Bool { get }
}

extension CachePolicy {
    var evictsOnWrite: Bool { false }
}

// MARK: - Standard Policies

/// A fixed-TTL policy with an optional entry cap.
struct TTLCachePolicy: CachePolicy {
    let ttl: TimeInterval?
    let maxEntries: Int?
    var maxBytes: Int? { nil }

    /// 10-minute cache, no entry cap — used by RecommendationIntelligenceService.
    static let tenMinutes    = TTLCachePolicy(ttl: 600,   maxEntries: nil)
    /// 1-minute cache — used by FollowStateManager.
    static let oneMinute     = TTLCachePolicy(ttl: 60,    maxEntries: nil)
    /// 24-hour cache — used by HomeFeedAlgorithm UserInterests.
    static let twentyFourHours = TTLCachePolicy(ttl: 86400, maxEntries: nil)
    /// Session cache — entries expire when app backgrounds.
    static let session       = TTLCachePolicy(ttl: nil,   maxEntries: 500)
}

// MARK: - CacheEntry wrapper

/// A value with an associated expiry timestamp for TTL-based caches.
struct CacheEntry<T> {
    let value: T
    let insertedAt: Date

    /// Returns true if the entry is older than `policy.ttl`.
    func isExpired(policy: some CachePolicy) -> Bool {
        guard let ttl = policy.ttl else { return false }
        return Date().timeIntervalSince(insertedAt) > ttl
    }
}

// MARK: - TTLCache

/// Generic in-memory cache backed by a plain dictionary + CachePolicy.
/// Thread safety: wrap access in `@MainActor` or a serial DispatchQueue.
final class TTLCache<Key: Hashable, Value> {
    private var store: [Key: CacheEntry<Value>] = [:]
    private let policy: any CachePolicy

    init(policy: some CachePolicy) {
        self.policy = policy
    }

    func get(_ key: Key) -> Value? {
        guard let entry = store[key] else { return nil }
        if entry.isExpired(policy: policy) {
            store.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func set(_ key: Key, value: Value) {
        // Evict expired entries proactively if policy requests it
        if policy.evictsOnWrite { evictExpired() }

        // Enforce entry cap: remove oldest if at limit
        if let max = policy.maxEntries, store.count >= max {
            store.removeValue(forKey: store.keys.first!)
        }

        store[key] = CacheEntry(value: value, insertedAt: Date())
    }

    func invalidate(_ key: Key) {
        store.removeValue(forKey: key)
    }

    func invalidateAll() {
        store.removeAll()
    }

    private func evictExpired() {
        store = store.filter { !$0.value.isExpired(policy: policy) }
    }

    var count: Int { store.count }
}
