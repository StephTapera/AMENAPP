// ActivitySummaryService.swift
// AMENAPP
//
// Reads precomputed UserActivitySummary documents from Firestore.
// Never writes — writes happen exclusively via Cloud Functions.

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ActivitySummaryService {

    static let shared = ActivitySummaryService()

    private let db = Firestore.firestore()
    private var cache: [String: UserActivitySummary] = [:]

    private init() {}

    // MARK: - Fetch Single

    func fetchSummary(for userId: String) async -> UserActivitySummary? {
        if let cached = cache[userId] {
            return cached
        }
        do {
            let doc = try await db.collection("user_activity_summary").document(userId).getDocument()
            guard let data = doc.data() else { return nil }
            let summary = try parse(data: data, userId: userId)
            cache[userId] = summary
            return summary
        } catch {
            dlog("[ActivitySummary] fetch error for \(userId): \(error)")
            return nil
        }
    }

    // MARK: - Batch Fetch

    func fetchSummaries(for userIds: [String]) async -> [String: UserActivitySummary] {
        guard !userIds.isEmpty else { return [:] }

        var result: [String: UserActivitySummary] = [:]
        var missing: [String] = []

        for uid in userIds {
            if let cached = cache[uid] {
                result[uid] = cached
            } else {
                missing.append(uid)
            }
        }

        // Firestore `in` query limit is 30
        let chunks = missing.socialGraphChunked(into: 30)
        await withTaskGroup(of: [String: UserActivitySummary].self) { group in
            for chunk in chunks {
                group.addTask {
                    await self.fetchChunk(chunk)
                }
            }
            for await partial in group {
                result.merge(partial) { $1 }
            }
        }

        // Populate cache
        for (uid, summary) in result {
            cache[uid] = summary
        }

        return result
    }

    private func fetchChunk(_ userIds: [String]) async -> [String: UserActivitySummary] {
        do {
            let snap = try await db.collection("user_activity_summary")
                .whereField(FieldPath.documentID(), in: userIds)
                .getDocuments()
            var result: [String: UserActivitySummary] = [:]
            for doc in snap.documents {
                if let summary = try? parse(data: doc.data(), userId: doc.documentID) {
                    result[doc.documentID] = summary
                }
            }
            return result
        } catch {
            dlog("[ActivitySummary] chunk fetch error: \(error)")
            return [:]
        }
    }

    // MARK: - Invalidate

    func invalidate(userId: String) {
        cache.removeValue(forKey: userId)
    }

    func invalidateAll() {
        cache.removeAll()
    }

    // MARK: - Parse

    private func parse(data: [String: Any], userId: String) throws -> UserActivitySummary {
        var summary = UserActivitySummary(userId: userId)
        summary.postCount7d = data["postCount7d"] as? Int ?? 0
        summary.prayerCount7d = data["prayerCount7d"] as? Int ?? 0
        summary.noteCount7d = data["noteCount7d"] as? Int ?? 0
        summary.latestPostSnippet = data["latestPostSnippet"] as? String
        summary.latestPostId = data["latestPostId"] as? String
        summary.topicTags = data["topicTags"] as? [String] ?? []
        summary.activeStreak = data["activeStreak"] as? Int ?? 0
        summary.lastPostAt = (data["lastPostAt"] as? Timestamp)?.dateValue()
        summary.lastPrayerAt = (data["lastPrayerAt"] as? Timestamp)?.dateValue()
        summary.lastNoteAt = (data["lastNoteAt"] as? Timestamp)?.dateValue()
        summary.lastActiveAt = (data["lastActiveAt"] as? Timestamp)?.dateValue()
        summary.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        return summary
    }
}

// MARK: - Array Chunk Helper

extension Array {
    func socialGraphChunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
