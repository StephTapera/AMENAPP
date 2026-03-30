//
//  BereanUserContext.swift
//  AMENAPP
//
//  Fetches lightweight user context from Firestore and composes it into
//  a system prompt block. This gives Berean awareness of the user's faith
//  journey — recent prayers, church notes, interests, and maturity level —
//  so responses feel personal rather than generic.
//
//  Architecture:
//  - Fetches once per conversation start (not per message).
//  - Caches for 10 minutes to avoid redundant reads.
//  - All Firestore reads are limited to 3-5 documents max.
//  - The composed context block is ~200-400 tokens.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BereanUserContext: ObservableObject {

    static let shared = BereanUserContext()

    // MARK: - Cached Context

    @Published private(set) var contextBlock: String = ""
    @Published private(set) var isLoading = false

    private var lastFetchTime: Date?
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Public API

    /// Returns the composed context block, fetching fresh data if the cache is stale.
    func getContextBlock() async -> String {
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTTL,
           !contextBlock.isEmpty {
            return contextBlock
        }
        await refreshContext()
        return contextBlock
    }

    /// Forces a fresh fetch regardless of cache.
    func refreshContext() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            contextBlock = ""
            return
        }

        isLoading = true
        defer { isLoading = false }

        async let userProfile = fetchUserProfile(uid: uid)
        async let recentPrayers = fetchRecentPrayers(uid: uid)
        async let recentNotes = fetchRecentChurchNotes(uid: uid)
        async let recentPosts = fetchRecentPostTopics(uid: uid)

        let profile = await userProfile
        let prayers = await recentPrayers
        let notes = await recentNotes
        let posts = await recentPosts

        contextBlock = composeContextBlock(
            profile: profile,
            prayers: prayers,
            notes: notes,
            postTopics: posts
        )
        lastFetchTime = Date()

        dlog("📋 [BereanUserContext] Context refreshed (\(contextBlock.count) chars)")
    }

    /// Clears cached context (call on logout).
    func reset() {
        contextBlock = ""
        lastFetchTime = nil
    }

    // MARK: - Firestore Fetchers

    private struct UserContextProfile {
        var displayName: String = ""
        var interests: [String] = []
        var goals: [String] = []
        var preferredPrayerTime: String?
        var bio: String?
    }

    private func fetchUserProfile(uid: String) async -> UserContextProfile {
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            guard let data = doc.data() else { return UserContextProfile() }

            return UserContextProfile(
                displayName: data["displayName"] as? String ?? "",
                interests: data["interests"] as? [String] ?? [],
                goals: data["goals"] as? [String] ?? [],
                preferredPrayerTime: data["preferredPrayerTime"] as? String,
                bio: data["bio"] as? String
            )
        } catch {
            dlog("⚠️ [BereanUserContext] Failed to fetch profile: \(error.localizedDescription)")
            return UserContextProfile()
        }
    }

    private func fetchRecentPrayers(uid: String) async -> [String] {
        do {
            // Prayer posts are stored in the main posts collection with category "prayer"
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: uid)
                .whereField("category", isEqualTo: "prayer")
                .order(by: "timestamp", descending: true)
                .limit(to: 3)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                let data = doc.data()
                // Use content field, truncate to keep context small
                if let content = data["content"] as? String {
                    return String(content.prefix(120))
                }
                return nil
            }
        } catch {
            dlog("⚠️ [BereanUserContext] Failed to fetch prayers: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchRecentChurchNotes(uid: String) async -> [(title: String, scripture: String?)] {
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("churchNotes")
                .order(by: "date", descending: true)
                .limit(to: 3)
                .getDocuments()

            return snapshot.documents.compactMap { doc in
                let data = doc.data()
                let title = data["title"] as? String ?? data["sermonTitle"] as? String ?? ""
                let scripture = data["scripture"] as? String
                guard !title.isEmpty else { return nil }
                return (title: title, scripture: scripture)
            }
        } catch {
            dlog("⚠️ [BereanUserContext] Failed to fetch church notes: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchRecentPostTopics(uid: String) async -> [String] {
        do {
            let snapshot = try await db.collection("posts")
                .whereField("authorId", isEqualTo: uid)
                .order(by: "timestamp", descending: true)
                .limit(to: 5)
                .getDocuments()

            // Extract topic tags or first few words of content
            var topics: [String] = []
            for doc in snapshot.documents {
                let data = doc.data()
                if let tag = data["topicTag"] as? String, !tag.isEmpty {
                    if !topics.contains(tag) { topics.append(tag) }
                } else if let content = data["content"] as? String {
                    let firstWords = content.split(separator: " ").prefix(6).joined(separator: " ")
                    if !firstWords.isEmpty { topics.append(firstWords) }
                }
                if topics.count >= 3 { break }
            }
            return topics
        } catch {
            dlog("⚠️ [BereanUserContext] Failed to fetch post topics: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Context Composition

    private func composeContextBlock(
        profile: UserContextProfile,
        prayers: [String],
        notes: [(title: String, scripture: String?)],
        postTopics: [String]
    ) -> String {
        var parts: [String] = []

        // User identity
        if !profile.displayName.isEmpty {
            parts.append("The user's name is \(profile.displayName).")
        }

        // Interests and goals from onboarding
        if !profile.interests.isEmpty {
            parts.append("Their faith interests include: \(profile.interests.joined(separator: ", ")).")
        }
        if !profile.goals.isEmpty {
            parts.append("Their spiritual goals: \(profile.goals.joined(separator: ", ")).")
        }

        // Prayer time preference
        if let prayerTime = profile.preferredPrayerTime, !prayerTime.isEmpty {
            parts.append("They prefer to pray in the \(prayerTime).")
        }

        // Recent prayer requests
        if !prayers.isEmpty {
            let prayerSummary = prayers.enumerated().map { idx, p in
                "  \(idx + 1). \(p)"
            }.joined(separator: "\n")
            parts.append("Their recent prayer requests:\n\(prayerSummary)")
        }

        // Recent church notes
        if !notes.isEmpty {
            let notesSummary = notes.map { note in
                if let scripture = note.scripture, !scripture.isEmpty {
                    return "  - \"\(note.title)\" (\(scripture))"
                }
                return "  - \"\(note.title)\""
            }.joined(separator: "\n")
            parts.append("Recent church notes/sermons they attended:\n\(notesSummary)")
        }

        // Recent post topics
        if !postTopics.isEmpty {
            parts.append("Topics they've recently posted about: \(postTopics.joined(separator: ", ")).")
        }

        guard !parts.isEmpty else { return "" }

        return """
        <user_context>
        Use this context to personalize your responses. Reference their journey naturally — \
        don't list these facts back, but let them inform your tone and suggestions.
        \(parts.joined(separator: "\n"))
        </user_context>
        """
    }
}
