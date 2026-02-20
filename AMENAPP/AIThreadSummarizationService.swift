//
//  AIThreadSummarizationService.swift
//  AMENAPP
//
//  AI-powered thread summarization for long comment threads
//  Uses OpenAI GPT-4o-mini for cost-effective summarization
//

import Foundation
import FirebaseFirestore
import Combine

@MainActor
class AIThreadSummarizationService: ObservableObject {
    static let shared = AIThreadSummarizationService()

    @Published var isGeneratingSummary = false
    @Published var cachedSummaries: [String: ThreadSummary] = [:]

    private let db = Firestore.firestore()
    private let openAI = OpenAIService.shared

    private init() {
        print("✅ AIThreadSummarizationService initialized")
    }

    // MARK: - Models

    struct ThreadSummary: Codable {
        let commentId: String
        let summary: String
        let keyPoints: [String]
        let keyParticipants: [String]
        let sentiment: String
        let totalReplies: Int
        let timestamp: Date

        var isExpired: Bool {
            // Summaries expire after 24 hours
            Date().timeIntervalSince(timestamp) > 86400
        }
    }

    // MARK: - Public Methods

    /// Generate or fetch cached summary for a comment thread
    /// Only summarizes threads with 10+ replies
    func getSummary(for commentId: String, replies: [Comment]) async throws -> ThreadSummary? {
        // Don't summarize short threads
        guard replies.count >= 10 else {
            return nil
        }

        // Check cache first
        if let cached = cachedSummaries[commentId], !cached.isExpired {
            print("📦 [SUMMARY] Using cached summary for comment: \(commentId)")
            return cached
        }

        // Check Firestore cache
        if let firestoreSummary = try await fetchSummaryFromFirestore(commentId: commentId) {
            cachedSummaries[commentId] = firestoreSummary
            return firestoreSummary
        }

        // Generate new summary
        print("🤖 [SUMMARY] Generating new summary for \(replies.count) replies...")
        isGeneratingSummary = true

        do {
            let summary = try await generateSummary(commentId: commentId, replies: replies)

            // Cache in memory and Firestore
            cachedSummaries[commentId] = summary
            try await storeSummaryInFirestore(summary: summary)

            isGeneratingSummary = false
            return summary
        } catch {
            isGeneratingSummary = false
            throw error
        }
    }

    // MARK: - AI Generation

    private func generateSummary(commentId: String, replies: [Comment]) async throws -> ThreadSummary {
        // Prepare thread context for AI
        let threadContext = prepareThreadContext(replies: replies)

        let prompt = """
        Summarize this faith-based comment thread. Provide a concise, encouraging summary.

        Thread with \(replies.count) replies:
        \(threadContext)

        Respond in JSON format:
        {
          "summary": "2-3 sentence summary of key discussion",
          "keyPoints": ["bullet point 1", "bullet point 2", "bullet point 3"],
          "keyParticipants": ["@username1", "@username2"],
          "sentiment": "encouraging" | "prayerful" | "thankful" | "questioning" | "mixed"
        }

        Focus on:
        - Main topics discussed
        - Prayer requests or testimonies shared
        - Questions answered
        - Community support shown

        Keep it brief, positive, and faith-focused.
        """

        // Use OpenAI sync method
        let response = try await openAI.sendMessageSync(prompt)

        // Parse JSON response
        guard let jsonData = response.data(using: String.Encoding.utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let summary = json["summary"] as? String,
              let keyPoints = json["keyPoints"] as? [String],
              let keyParticipants = json["keyParticipants"] as? [String],
              let sentiment = json["sentiment"] as? String else {
            throw NSError(domain: "AIThreadSummarization", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse AI response"])
        }

        return ThreadSummary(
            commentId: commentId,
            summary: summary,
            keyPoints: keyPoints,
            keyParticipants: keyParticipants,
            sentiment: sentiment,
            totalReplies: replies.count,
            timestamp: Date()
        )
    }

    private func prepareThreadContext(replies: [Comment]) -> String {
        // Take first 15 replies to avoid token limits
        let contextReplies = Array(replies.prefix(15))

        var context = ""
        for (index, reply) in contextReplies.enumerated() {
            context += "[\(index + 1)] @\(reply.authorUsername): \(reply.content)\n"
            if reply.amenCount > 0 {
                context += "   → \(reply.amenCount) amens\n"
            }
        }

        if replies.count > 15 {
            context += "\n[... \(replies.count - 15) more replies not shown]"
        }

        return context
    }

    // MARK: - Firestore Caching

    private func fetchSummaryFromFirestore(commentId: String) async throws -> ThreadSummary? {
        do {
            let doc = try await db.collection("threadSummaries").document(commentId).getDocument()

            guard doc.exists,
                  let data = doc.data(),
                  let summary = data["summary"] as? String,
                  let keyPoints = data["keyPoints"] as? [String],
                  let keyParticipants = data["keyParticipants"] as? [String],
                  let sentiment = data["sentiment"] as? String,
                  let totalReplies = data["totalReplies"] as? Int,
                  let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else {
                return nil
            }

            let threadSummary = ThreadSummary(
                commentId: commentId,
                summary: summary,
                keyPoints: keyPoints,
                keyParticipants: keyParticipants,
                sentiment: sentiment,
                totalReplies: totalReplies,
                timestamp: timestamp
            )

            // Check if expired
            if threadSummary.isExpired {
                print("⏰ [SUMMARY] Cached summary expired, will regenerate")
                return nil
            }

            print("✅ [SUMMARY] Fetched cached summary from Firestore")
            return threadSummary
        } catch {
            print("❌ [SUMMARY] Failed to fetch from Firestore: \(error)")
            return nil
        }
    }

    private func storeSummaryInFirestore(summary: ThreadSummary) async throws {
        try await db.collection("threadSummaries").document(summary.commentId).setData([
            "summary": summary.summary,
            "keyPoints": summary.keyPoints,
            "keyParticipants": summary.keyParticipants,
            "sentiment": summary.sentiment,
            "totalReplies": summary.totalReplies,
            "timestamp": Timestamp(date: summary.timestamp)
        ])

        print("💾 [SUMMARY] Stored summary in Firestore")
    }

    // MARK: - Helper Methods

    func clearCache() {
        cachedSummaries.removeAll()
        print("🗑️ [SUMMARY] Cache cleared")
    }

    func invalidateSummary(for commentId: String) {
        cachedSummaries.removeValue(forKey: commentId)

        // Also delete from Firestore
        Task {
            try? await db.collection("threadSummaries").document(commentId).delete()
            print("🗑️ [SUMMARY] Invalidated summary for: \(commentId)")
        }
    }
}

// MARK: - Sentiment Emoji Helper

extension AIThreadSummarizationService.ThreadSummary {
    var sentimentEmoji: String {
        switch sentiment.lowercased() {
        case "encouraging": return "💙"
        case "prayerful": return "🙏"
        case "thankful": return "🙌"
        case "questioning": return "💭"
        case "joyful": return "🎉"
        case "hopeful": return "✨"
        default: return "💬"
        }
    }
}
