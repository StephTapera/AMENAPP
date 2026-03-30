//
//  APIResponseCache.swift
//  AMENAPP
//
//  Feature 59: TTL-based response cache for Firestore reads.
//  Feed posts: 5 min. User profiles: 1 hour. Church data: 24 hours.
//

import Foundation

class APIResponseCache {
    static let shared = APIResponseCache()

    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()

    private init() {}

    struct CacheEntry {
        let data: Any
        let cachedAt: Date
        let ttl: TimeInterval
        var isExpired: Bool { Date().timeIntervalSince(cachedAt) > ttl }
    }

    // MARK: - TTL Constants

    enum CacheTTL {
        static let feedPosts: TimeInterval = 300      // 5 minutes
        static let userProfile: TimeInterval = 3600   // 1 hour
        static let churchData: TimeInterval = 86400   // 24 hours
        static let searchResults: TimeInterval = 600  // 10 minutes
        static let notifications: TimeInterval = 120  // 2 minutes
        static let following: TimeInterval = 1800     // 30 minutes
    }

    // MARK: - Get / Set

    func get<T>(key: String) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = cache[key], !entry.isExpired else {
            cache.removeValue(forKey: key) // Clean up expired
            return nil
        }
        return entry.data as? T
    }

    func set(key: String, data: Any, ttl: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = CacheEntry(data: data, cachedAt: Date(), ttl: ttl)
    }

    func invalidate(key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: key)
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }

    /// Remove all expired entries.
    func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        cache = cache.filter { !$0.value.isExpired }
    }

    // MARK: - Convenience

    func getCachedProfile(userId: String) -> [String: Any]? {
        get(key: "profile_\(userId)")
    }

    func cacheProfile(userId: String, data: [String: Any]) {
        set(key: "profile_\(userId)", data: data, ttl: CacheTTL.userProfile)
    }

    func getCachedFeed(category: String) -> [Any]? {
        get(key: "feed_\(category)")
    }

    func cacheFeed(category: String, posts: [Any]) {
        set(key: "feed_\(category)", data: posts, ttl: CacheTTL.feedPosts)
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}
