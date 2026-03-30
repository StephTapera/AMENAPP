//
//  SermonRelevanceEngine.swift
//  AMENAPP
//
//  Matches sermon content from church notes to user interests,
//  prayer topics, and current spiritual needs for personalized recommendations.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class SermonRelevanceEngine: ObservableObject {
    static let shared = SermonRelevanceEngine()
    private let db = Firestore.firestore()
    private init() {}

    struct SermonRecommendation: Identifiable {
        let id: String
        let title: String
        let churchName: String
        let previewText: String
        let relevanceScore: Float
        let matchReasons: [String]
        let date: Date
    }

    // MARK: - Get Recommendations

    func getRecommendations(limit: Int = 5) async -> [SermonRecommendation] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }

        // 1. Get user's interest profile
        let interests = await getUserInterests(uid: uid)

        // 2. Get recent church notes (shared/public ones)
        let notes = await fetchPublicNotes(limit: 50)

        // 3. Score and rank
        var scored: [(note: NoteData, score: Float, reasons: [String])] = []

        for note in notes {
            let (score, reasons) = scoreNote(note, interests: interests)
            if score > 0.1 {
                scored.append((note, score, reasons))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { item in
                SermonRecommendation(
                    id: item.note.id,
                    title: item.note.title,
                    churchName: item.note.churchName,
                    previewText: String(item.note.content.prefix(150)),
                    relevanceScore: item.score,
                    matchReasons: item.reasons,
                    date: item.note.date
                )
            }
    }

    // MARK: - Scoring

    private struct NoteData {
        let id: String
        let title: String
        let content: String
        let churchName: String
        let tags: [String]
        let date: Date
    }

    private func scoreNote(_ note: NoteData, interests: UserInterestProfile) -> (Float, [String]) {
        let lower = note.content.lowercased()
        var score: Float = 0
        var reasons: [String] = []

        // Theme matching
        for theme in interests.prayerThemes {
            if lower.contains(theme.lowercased()) {
                score += 0.3
                reasons.append("Related to your prayer for \(theme)")
            }
        }

        // Topic matching
        for topic in interests.topInterests {
            if lower.contains(topic.lowercased()) {
                score += 0.2
                reasons.append("Covers \(topic)")
            }
        }

        // Scripture overlap
        for scripture in interests.recentScriptures {
            if lower.contains(scripture.lowercased()) {
                score += 0.25
                reasons.append("References \(scripture)")
            }
        }

        // Recency bonus
        let daysSince = abs(note.date.timeIntervalSinceNow) / 86400
        if daysSince < 7 {
            score += 0.15
        } else if daysSince < 30 {
            score += 0.05
        }

        // Tag matching
        for tag in note.tags {
            if interests.topInterests.contains(where: { $0.lowercased() == tag.lowercased() }) {
                score += 0.15
                reasons.append("Tagged with \(tag)")
            }
        }

        return (min(1.0, score), reasons)
    }

    // MARK: - User Interests

    private struct UserInterestProfile {
        var prayerThemes: [String]
        var topInterests: [String]
        var recentScriptures: [String]
    }

    private func getUserInterests(uid: String) async -> UserInterestProfile {
        var themes: [String] = []
        var interests: [String] = []
        var scriptures: [String] = []

        // Get prayer themes
        if let prayerHistory = UserDefaults.standard.data(forKey: "prayerHistory_v1"),
           let decoded = try? JSONDecoder().decode(PrayerAlgorithm.PrayerHistory.self, from: prayerHistory) {
            themes = Array(decoded.prayerTopics.sorted(by: { $0.value > $1.value }).prefix(5).map(\.key))
        }

        // Get user's top post topics
        if let snapshot = try? await db.collection("posts")
            .whereField("authorId", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments() {
            var topicCounts: [String: Int] = [:]
            for doc in snapshot.documents {
                if let topic = doc.data()["topicTag"] as? String {
                    topicCounts[topic, default: 0] += 1
                }
            }
            interests = Array(topicCounts.sorted(by: { $0.value > $1.value }).prefix(5).map(\.key))
        }

        // Get recent Berean scripture references
        if let snapshot = try? await db.collection("users").document(uid)
            .collection("bereanConversations")
            .order(by: "updatedAt", descending: true)
            .limit(to: 10)
            .getDocuments() {
            for doc in snapshot.documents {
                if let refs = doc.data()["scriptureReferences"] as? [String] {
                    scriptures.append(contentsOf: refs)
                }
            }
            scriptures = Array(Set(scriptures).prefix(10))
        }

        return UserInterestProfile(
            prayerThemes: themes,
            topInterests: interests,
            recentScriptures: scriptures
        )
    }

    // MARK: - Fetch Notes

    private func fetchPublicNotes(limit: Int) async -> [NoteData] {
        guard let snapshot = try? await db.collection("churchNotes")
            .whereField("isPublic", isEqualTo: true)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments() else { return [] }

        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            return NoteData(
                id: doc.documentID,
                title: data["title"] as? String ?? "Sermon Notes",
                content: data["content"] as? String ?? "",
                churchName: data["churchName"] as? String ?? "Unknown Church",
                tags: data["tags"] as? [String] ?? [],
                date: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }
}
