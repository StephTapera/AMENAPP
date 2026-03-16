//
//  RecommendedUsersAIService.swift
//  AMENAPP
//
//  Feature 10: AI-powered "People You May Know" based on graph distance,
//  shared church, similar prayer themes, and mutual engagement.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class RecommendedUsersAIService: ObservableObject {
    static let shared = RecommendedUsersAIService()

    @Published var recommendations: [UserRecommendation] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var lastFetchDate: Date?

    private init() {}

    struct UserRecommendation: Identifiable {
        let id: String // userId
        let name: String
        let username: String
        let profileImageURL: String?
        let matchScore: Int // 0-100
        let matchReason: String // "3 mutual friends · Same church"
        let mutualFriendCount: Int
        let sharedInterests: [String]
    }

    /// Fetch personalized user recommendations.
    func fetchRecommendations() async {
        // Cache: only refresh every 6 hours
        if let last = lastFetchDate, Date().timeIntervalSince(last) < 21600 {
            return
        }

        guard let uid = Auth.auth().currentUser?.uid else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // Get current user's following list
            let followingSnap = try await db.collection("users").document(uid)
                .collection("following").getDocuments()
            let followingIDs = Set(followingSnap.documents.map { $0.documentID })

            // Get friends-of-friends (2nd degree connections)
            var candidateScores: [String: (score: Int, reasons: [String], mutuals: Int)] = [:]

            for friendID in followingIDs.prefix(20) { // Cap to avoid N+1
                let friendFollowingSnap = try await db.collection("users").document(friendID)
                    .collection("following").limit(to: 30).getDocuments()

                for doc in friendFollowingSnap.documents {
                    let candidateID = doc.documentID
                    guard candidateID != uid, !followingIDs.contains(candidateID) else { continue }

                    var entry = candidateScores[candidateID] ?? (score: 0, reasons: [], mutuals: 0)
                    entry.score += 15 // 15 points per mutual connection
                    entry.mutuals += 1
                    entry.reasons.append("mutual")
                    candidateScores[candidateID] = entry
                }
            }

            // Get current user's interests for theme matching
            let interests = HomeFeedAlgorithm.shared.userInterests
            let userTopics = Set(interests.engagedTopics.keys.map { $0.lowercased() })

            // Score and resolve top candidates
            let sortedCandidates = candidateScores
                .sorted { $0.value.score > $1.value.score }
                .prefix(15)

            var results: [UserRecommendation] = []

            for (candidateID, scoring) in sortedCandidates {
                guard let userDoc = try? await db.collection("users").document(candidateID).getDocument(),
                      let data = userDoc.data() else { continue }

                let name = data["displayName"] as? String ?? "Unknown"
                let username = data["username"] as? String ?? ""
                let photo = data["profileImageURL"] as? String
                let candidateInterests = data["interests"] as? [String] ?? []
                let shared = candidateInterests.filter { userTopics.contains($0.lowercased()) }

                var totalScore = scoring.score
                totalScore += shared.count * 10 // 10 points per shared interest

                let reasonParts: [String] = [
                    scoring.mutuals > 0 ? "\(scoring.mutuals) mutual" : nil,
                    !shared.isEmpty ? "Shares: \(shared.prefix(2).joined(separator: ", "))" : nil,
                ].compactMap { $0 }

                results.append(UserRecommendation(
                    id: candidateID,
                    name: name,
                    username: username,
                    profileImageURL: photo,
                    matchScore: min(100, totalScore),
                    matchReason: reasonParts.joined(separator: " · "),
                    mutualFriendCount: scoring.mutuals,
                    sharedInterests: shared
                ))
            }

            results.sort { $0.matchScore > $1.matchScore }
            recommendations = Array(results.prefix(10))
            lastFetchDate = Date()

        } catch {
            dlog("Recommended users fetch failed: \(error)")
        }
    }
}
