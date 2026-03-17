//
//  BereanCommunityLearning.swift
//  AMENAPP
//
//  Community-powered learning for Berean AI:
//  - Upvote/downvote answers (thumbs up/down)
//  - Track answer quality patterns
//  - Surface "Popular questions this week" from anonymized data
//  - Pastor flagging for theological corrections
//  - Answer quality scoring for continuous improvement
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Community Learning Models

struct AnswerFeedback: Codable, Identifiable {
    let id: String
    let answerId: String           // The BereanAnswer.id that was rated
    let userId: String
    let rating: FeedbackRating
    let reason: String?            // Optional: why they upvoted/downvoted
    let timestamp: Date
    let queryTopic: String         // Anonymized topic (not full query)
    let answerType: String         // e.g., "ragExegesis", "deepThink"

    enum FeedbackRating: String, Codable {
        case helpful = "helpful"
        case notHelpful = "not_helpful"
        case incorrect = "incorrect"      // Specifically flagging bad theology
    }
}

struct PopularQuestion: Codable, Identifiable {
    let id: String
    let topic: String              // Anonymized topic
    let exampleQuery: String       // Representative question (not user's exact words)
    let askCount: Int              // How many users asked about this
    let averageRating: Double      // Average helpfulness rating
    let topAnswer: String?         // Best-rated answer summary
    let weekOf: Date
}

struct PastorFlag: Codable, Identifiable {
    let id: String
    let answerId: String
    let pastorId: String
    let flagType: FlagType
    let correction: String         // What the pastor says should be different
    let suggestedResponse: String? // Optional: what the answer should say
    let timestamp: Date
    let resolved: Bool

    enum FlagType: String, Codable {
        case theologicalError = "theological_error"   // Incorrect doctrine
        case missingContext = "missing_context"        // Needs more nuance
        case denominationalBias = "denominational_bias" // Favors one tradition unfairly
        case insensitive = "insensitive"              // Tone issue
    }
}

struct AnswerQualityScore: Codable {
    let answerId: String
    let helpfulCount: Int
    let notHelpfulCount: Int
    let incorrectCount: Int
    let pastorFlags: Int
    let qualityScore: Double       // 0.0-1.0 computed score
    let lastUpdated: Date
}

// MARK: - Community Learning Service

@MainActor
final class BereanCommunityLearning: ObservableObject {
    static let shared = BereanCommunityLearning()

    @Published var popularQuestions: [PopularQuestion] = []
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private let maxPopularQuestions = 10

    // Local tracking to prevent double-voting
    private var userFeedback: Set<String> = []  // Set of answerId

    private init() {
        loadUserFeedbackHistory()
    }

    // MARK: - Answer Feedback

    /// Submit feedback for a Berean answer
    func submitFeedback(
        answerId: String,
        rating: AnswerFeedback.FeedbackRating,
        reason: String? = nil,
        queryTopic: String,
        answerType: String
    ) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        // Prevent double-voting
        guard !userFeedback.contains(answerId) else {
            print("⚠️ CommunityLearning: Already rated this answer")
            return
        }

        let feedback = AnswerFeedback(
            id: UUID().uuidString,
            answerId: answerId,
            userId: userId,
            rating: rating,
            reason: reason,
            timestamp: Date(),
            queryTopic: queryTopic,
            answerType: answerType
        )

        do {
            // Store feedback
            try db.collection("berean_feedback").document(feedback.id)
                .setData(from: feedback)

            // Update quality score
            await updateQualityScore(answerId: answerId, rating: rating)

            // Update popular questions
            await incrementTopicCount(topic: queryTopic)

            // Track locally
            userFeedback.insert(answerId)
            saveUserFeedbackHistory()

            print("✅ CommunityLearning: Feedback recorded for \(answerId)")
        } catch {
            print("⚠️ CommunityLearning: Failed to save feedback: \(error.localizedDescription)")
        }
    }

    /// Check if user already rated an answer
    func hasRated(answerId: String) -> Bool {
        userFeedback.contains(answerId)
    }

    // MARK: - Quality Scoring

    private func updateQualityScore(answerId: String, rating: AnswerFeedback.FeedbackRating) async {
        let docRef = db.collection("berean_quality_scores").document(answerId)

        do {
            try await db.runTransaction { transaction, errorPointer in
                let doc: DocumentSnapshot
                do {
                    doc = try transaction.getDocument(docRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                var helpful = doc.data()?["helpfulCount"] as? Int ?? 0
                var notHelpful = doc.data()?["notHelpfulCount"] as? Int ?? 0
                var incorrect = doc.data()?["incorrectCount"] as? Int ?? 0

                switch rating {
                case .helpful: helpful += 1
                case .notHelpful: notHelpful += 1
                case .incorrect: incorrect += 1
                }

                let total = helpful + notHelpful + incorrect
                let score: Double = total > 0
                    ? Double(helpful) / Double(total) * (1.0 - Double(incorrect) * 0.3 / Double(total))
                    : 0.5

                transaction.setData([
                    "answerId": answerId,
                    "helpfulCount": helpful,
                    "notHelpfulCount": notHelpful,
                    "incorrectCount": incorrect,
                    "pastorFlags": doc.data()?["pastorFlags"] as? Int ?? 0,
                    "qualityScore": score,
                    "lastUpdated": FieldValue.serverTimestamp()
                ], forDocument: docRef)

                return nil
            }
        } catch {
            print("⚠️ CommunityLearning: Failed to update quality score: \(error.localizedDescription)")
        }
    }

    // MARK: - Popular Questions

    /// Load this week's popular questions
    func loadPopularQuestions() async {
        isLoading = true
        defer { isLoading = false }

        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()

        do {
            let snapshot = try await db.collection("berean_popular_questions")
                .whereField("weekOf", isGreaterThanOrEqualTo: startOfWeek)
                .order(by: "askCount", descending: true)
                .limit(to: maxPopularQuestions)
                .getDocuments()

            popularQuestions = snapshot.documents.compactMap { doc in
                try? doc.data(as: PopularQuestion.self)
            }

            print("✅ CommunityLearning: Loaded \(popularQuestions.count) popular questions")
        } catch {
            print("⚠️ CommunityLearning: Failed to load popular questions: \(error.localizedDescription)")
        }
    }

    private func incrementTopicCount(topic: String) async {
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let docId = "\(topic.lowercased().replacingOccurrences(of: " ", with: "_"))_\(Int(startOfWeek.timeIntervalSince1970))"

        let docRef = db.collection("berean_popular_questions").document(docId)

        do {
            try await db.runTransaction { transaction, errorPointer in
                let doc: DocumentSnapshot
                do {
                    doc = try transaction.getDocument(docRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }

                if doc.exists {
                    let currentCount = doc.data()?["askCount"] as? Int ?? 0
                    transaction.updateData(["askCount": currentCount + 1], forDocument: docRef)
                } else {
                    transaction.setData([
                        "id": docId,
                        "topic": topic,
                        "exampleQuery": "What does the Bible say about \(topic)?",
                        "askCount": 1,
                        "averageRating": 0.0,
                        "topAnswer": NSNull(),
                        "weekOf": startOfWeek
                    ], forDocument: docRef)
                }

                return nil
            }
        } catch {
            print("⚠️ CommunityLearning: Failed to update topic count: \(error.localizedDescription)")
        }
    }

    // MARK: - Pastor Flagging

    /// Allow verified pastors to flag answers for correction
    func submitPastorFlag(
        answerId: String,
        flagType: PastorFlag.FlagType,
        correction: String,
        suggestedResponse: String? = nil
    ) async {
        guard let pastorId = Auth.auth().currentUser?.uid else { return }

        let flag = PastorFlag(
            id: UUID().uuidString,
            answerId: answerId,
            pastorId: pastorId,
            flagType: flagType,
            correction: correction,
            suggestedResponse: suggestedResponse,
            timestamp: Date(),
            resolved: false
        )

        do {
            try db.collection("berean_pastor_flags").document(flag.id)
                .setData(from: flag)

            // Increment pastor flag count on quality score
            let scoreRef = db.collection("berean_quality_scores").document(answerId)
            try await scoreRef.updateData([
                "pastorFlags": FieldValue.increment(Int64(1))
            ])

            print("✅ CommunityLearning: Pastor flag submitted for \(answerId)")
        } catch {
            print("⚠️ CommunityLearning: Failed to submit pastor flag: \(error.localizedDescription)")
        }
    }

    // MARK: - Quality Insights

    /// Get the quality score for an answer
    func getQualityScore(answerId: String) async -> AnswerQualityScore? {
        do {
            let doc = try await db.collection("berean_quality_scores")
                .document(answerId).getDocument()
            return try? doc.data(as: AnswerQualityScore.self)
        } catch {
            return nil
        }
    }

    /// Get aggregate quality stats
    func getAggregateStats() async -> (averageScore: Double, totalFeedback: Int, pastorFlags: Int)? {
        do {
            let snapshot = try await db.collection("berean_quality_scores")
                .order(by: "lastUpdated", descending: true)
                .limit(to: 100)
                .getDocuments()

            let scores = snapshot.documents.compactMap { doc in
                try? doc.data(as: AnswerQualityScore.self)
            }

            guard !scores.isEmpty else { return nil }

            let avgScore = scores.map { $0.qualityScore }.reduce(0, +) / Double(scores.count)
            let totalFeedback = scores.map { $0.helpfulCount + $0.notHelpfulCount + $0.incorrectCount }.reduce(0, +)
            let totalFlags = scores.map { $0.pastorFlags }.reduce(0, +)

            return (avgScore, totalFeedback, totalFlags)
        } catch {
            return nil
        }
    }

    // MARK: - Local Persistence

    private func loadUserFeedbackHistory() {
        if let data = UserDefaults.standard.array(forKey: "berean_user_feedback") as? [String] {
            userFeedback = Set(data)
        }
    }

    private func saveUserFeedbackHistory() {
        UserDefaults.standard.set(Array(userFeedback), forKey: "berean_user_feedback")
    }
}
