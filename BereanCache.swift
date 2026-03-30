//
//  BereanCache.swift
//  AMENAPP
//
//  NSCache-backed result store for Berean AI post insights.
//  TTL: 10 minutes. Keyed by postId.
//  Prefetch fires on PostCard appear (low-priority detached task).
//

import Foundation

// MARK: - Cached result

struct BereanCachedResult {
    let responseText: String
    let scriptures: [String]
    let scriptureRef: String?
    let scriptureText: String?
    let fetchedAt: Date

    var isExpired: Bool {
        Date().timeIntervalSince(fetchedAt) > 600 // 10 min TTL
    }
}

// MARK: - NSCache wrapper (NSCache requires a class value)

private final class BereanCacheEntry: NSObject {
    let result: BereanCachedResult
    init(_ result: BereanCachedResult) { self.result = result }
}

// MARK: - BereanCache

// P0 FIX: Added @MainActor so all inFlight / prefetchTasks / activePrefetchCount
// mutations are serialised on the main actor. Previously the inFlight guard used
// queue.async(flags:.barrier) which returned *immediately*, letting Task.detached
// be created on EVERY call regardless of the guard — the intended deduplication
// never fired. @MainActor makes the check-and-set atomic by construction and
// removes the custom concurrent DispatchQueue entirely.
@MainActor
final class BereanCache {
    static let shared = BereanCache()
    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 5_000_000 // ~5 MB
    }

    // NSCache is thread-safe internally — no actor annotation needed on it.
    private let cache = NSCache<NSString, BereanCacheEntry>()

    /// postIds whose prefetch Task is currently running.
    private var inFlight = Set<String>()
    /// Live count of running prefetch tasks — capped at maxConcurrentPrefetches.
    private var activePrefetchCount = 0
    /// Maximum concurrent background AI prefetch requests.
    /// Keeps URLSession / Swift cooperative thread-pool pressure bounded.
    private let maxConcurrentPrefetches = 2
    /// Stored so we can cancel on tab navigation or scroll-off.
    private var prefetchTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Read / Write

    func get(postId: String) -> BereanCachedResult? {
        guard let entry = cache.object(forKey: postId as NSString) else { return nil }
        if entry.result.isExpired {
            cache.removeObject(forKey: postId as NSString)
            return nil
        }
        return entry.result
    }

    func store(postId: String, result: BereanCachedResult) {
        cache.setObject(BereanCacheEntry(result), forKey: postId as NSString)
    }

    // MARK: - Cancel

    /// Cancel all in-flight prefetch tasks — call on tab navigation to prevent
    /// stale background AI work from exploding the thread pool after navigation.
    func cancelAllPrefetches() {
        let cancelledCount = prefetchTasks.count
        prefetchTasks.values.forEach { $0.cancel() }
        prefetchTasks.removeAll()
        inFlight.removeAll()
        activePrefetchCount = 0
        if cancelledCount > 0 {
            ScreenCrashLogger.log(.bodyEvaluated("BEREAN_CACHE_CANCEL_ALL"), context: [
                "cancelledCount": "\(cancelledCount)",
                "memoryMB": ScreenCrashLogger.memoryUsageMB,
                "threads": ScreenCrashLogger.threadCount
            ])
        }
    }

    // MARK: - Prefetch

    /// Silently pre-warms the cache for a post while it is on screen.
    /// Deduplicates by postId and limits to maxConcurrentPrefetches concurrent
    /// tasks to prevent URLSession thread-pool explosion.
    func prefetch(postId: String, query: String) {
        // All state reads+writes happen on the main actor — atomic by construction.
        guard !inFlight.contains(postId),
              get(postId: postId) == nil,
              activePrefetchCount < maxConcurrentPrefetches else {
            dlog("⏭️ BereanCache prefetch skipped: postId=\(postId) inFlight=\(inFlight.contains(postId)) cached=\(get(postId: postId) != nil) active=\(activePrefetchCount)/\(maxConcurrentPrefetches)")
            return
        }

        inFlight.insert(postId)
        activePrefetchCount += 1
        ScreenCrashLogger.log(.dataLoadStarted("BEREAN_PREFETCH"), context: [
            "postId": postId,
            "activePrefetches": "\(activePrefetchCount)",
            "inFlightCount": "\(inFlight.count)",
            "memoryMB": ScreenCrashLogger.memoryUsageMB,
            "threads": ScreenCrashLogger.threadCount
        ])

        let task = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            defer {
                // Hop back to main actor to clean up shared mutable state.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.inFlight.remove(postId)
                    self.prefetchTasks.removeValue(forKey: postId)
                    self.activePrefetchCount = max(0, self.activePrefetchCount - 1)
                }
            }

            do {
                let answer = try await BereanAnswerEngine.shared.answer(
                    query: query,
                    context: nil,
                    mode: .ecumenical
                )
                guard !Task.isCancelled else { return }

                let refs = answer.scripture.map { $0.reference }
                let firstRef = answer.scripture.first?.reference
                let firstText = answer.scripture.first?.text

                let result = BereanCachedResult(
                    responseText: answer.response,
                    scriptures: Array(refs.prefix(3)),
                    scriptureRef: firstRef,
                    scriptureText: firstText,
                    fetchedAt: Date()
                )
                // store() is @MainActor — hop to store result.
                await MainActor.run { [weak self] in
                    self?.store(postId: postId, result: result)
                }
                dlog("✚ BereanCache prefetch stored: \(postId)")
                ScreenCrashLogger.log(.dataLoadCompleted("BEREAN_PREFETCH"), context: [
                    "postId": postId,
                    "memoryMB": ScreenCrashLogger.memoryUsageMB,
                    "threads": ScreenCrashLogger.threadCount
                ])
            } catch {
                // Prefetch failures are silent — user will see normal load on tap.
                dlog("⚠️ BereanCache prefetch failed for \(postId): \(error.localizedDescription)")
                ScreenCrashLogger.log(.dataLoadFailed("BEREAN_PREFETCH"), context: [
                    "postId": postId,
                    "error": error.localizedDescription,
                    "memoryMB": ScreenCrashLogger.memoryUsageMB
                ])
            }
        }

        prefetchTasks[postId] = task
    }
}
