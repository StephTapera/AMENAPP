// SpacesFilterService.swift
// AMENAPP — Spaces Chat Core (Agent B)
//
// Computes SpaceFilterSignals for the Spaces list view (Agent C).
//
// Unread count strategy:
//   - `lastSeenAt(spaceId:)` stores a Unix-timestamp in UserDefaults.
//   - A thread counts as unread if its `lastMessageAt > lastSeenAt`.
//   - `markSeen(spaceId:)` updates lastSeenAt to now.
//
// VIP strategy (v1):
//   - VIP = spaces the user has manually starred.
//   - Stored as Set<String> (spaceIds) in UserDefaults under key `vipSpaceIds`.
//   - Toggled via `toggleVIP(spaceId:)`.
//
// Architecture rules:
//   - No Firestore reads — derives signals from already-loaded ThreadSummary data.
//   - No Combine. Pure computation + UserDefaults.
//   - Thread-safe: all writes to UserDefaults happen on the calling actor (callers
//     are @MainActor in practice).

import Foundation

// MARK: - SpacesFilterService

final class SpacesFilterService {

    // MARK: - Singleton

    static let shared = SpacesFilterService()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastSeenPrefix = "spacesLastSeen_"
        static let vipSpaceIds    = "vipSpaceIds"
    }

    // MARK: - Init

    init() {}

    // MARK: - Signals

    /// Computes `SpaceFilterSignals` for a space from already-loaded thread summaries.
    /// No additional Firestore reads are triggered.
    func signals(
        for spaceId: String,
        threads: [ThreadSummary]
    ) -> SpaceFilterSignals {
        let seen = lastSeenAt(spaceId: spaceId)

        // Unread = threads with lastMessageAt after lastSeenAt.
        let unreadThreads = threads.filter { thread in
            thread.lastMessageAt > seen
        }
        let unreadCount = unreadThreads.reduce(0) { $0 + $1.unreadCount }

        // External = any thread with at least one external member.
        let hasExternal = threads.contains { $0.hasExternalMembers }

        // Latest message across all threads.
        let latestThread = threads.max(by: { $0.lastMessageAt < $1.lastMessageAt })

        return SpaceFilterSignals(
            spaceId: spaceId,
            hasUnread: !unreadThreads.isEmpty,
            unreadCount: max(0, unreadCount),
            hasExternalMembers: hasExternal,
            latestMessagePreview: latestThread?.lastMessagePreview,
            latestMessageAt: latestThread?.lastMessageAt,
            isVIP: vipSpaceIds.contains(spaceId)
        )
    }

    // MARK: - Last Seen

    /// Returns the last time the user opened any thread in this space.
    /// Defaults to `.distantPast` if never seen (so all messages appear unread).
    func lastSeenAt(spaceId: String) -> Date {
        let ts = UserDefaults.standard.double(forKey: Keys.lastSeenPrefix + spaceId)
        guard ts > 0 else { return .distantPast }
        return Date(timeIntervalSince1970: ts)
    }

    /// Stamps the current time as the last-seen timestamp for a space.
    /// Call when the user opens the space or marks a thread as read.
    func markSeen(spaceId: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.lastSeenPrefix + spaceId)
    }

    // MARK: - VIP

    /// Current set of starred space IDs.
    var vipSpaceIds: Set<String> {
        get {
            let arr = UserDefaults.standard.array(forKey: Keys.vipSpaceIds) as? [String] ?? []
            return Set(arr)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: Keys.vipSpaceIds)
        }
    }

    /// Toggles the VIP (starred) status of a space.
    func toggleVIP(spaceId: String) {
        var ids = vipSpaceIds
        if ids.contains(spaceId) {
            ids.remove(spaceId)
        } else {
            ids.insert(spaceId)
        }
        vipSpaceIds = ids
    }

    /// Returns true if the space is currently starred.
    func isVIP(spaceId: String) -> Bool {
        vipSpaceIds.contains(spaceId)
    }

    // MARK: - Batch Signals

    /// Computes filter signals for a list of (spaceId, threads) pairs.
    /// Useful when Agent C needs signals for every space in one pass.
    func batchSignals(
        _ spacesWithThreads: [(spaceId: String, threads: [ThreadSummary])]
    ) -> [SpaceFilterSignals] {
        spacesWithThreads.map { entry in
            signals(for: entry.spaceId, threads: entry.threads)
        }
    }
}
