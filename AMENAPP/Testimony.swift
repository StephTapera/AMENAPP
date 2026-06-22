// Testimony.swift
// AMENAPP — Witness Network models

import Foundation
import FirebaseFirestore

// MARK: - Testimony

struct Testimony: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var authorDisplayName: String
    var content: String
    var createdAt: Timestamp

    // AI-generated fields (populated by Cloud Function on write)
    var aiThemes: [String]              // e.g. ["addiction_recovery", "grief", "healing"]
    var aiEmotionalTone: String         // "hopeful" | "vulnerable" | "triumphant" | "peaceful" | "urgent"
    var aiSpiritualMaturity: String     // "new_believer" | "growing" | "mature" | "leader"
    var aiScriptureReferences: [String] // ["John 3:16", "Psalm 23"]
    var aiOutcome: String               // "still_in_process" | "breakthrough" | "restored" | "healed"
    var aiMatchScore: Double            // 0.0 – 1.0, per-user relevance

    var isVerified: Bool
    var viewCount: Int
    var impactReports: Int
    var prayerCount: Int
    var reportCount: Int

    // Initializer with safe defaults for optional AI fields that arrive from Firestore
    init(
        id: String? = nil,
        userId: String,
        authorDisplayName: String,
        content: String,
        createdAt: Timestamp = Timestamp(date: Date()),
        aiThemes: [String] = [],
        aiEmotionalTone: String = "",
        aiSpiritualMaturity: String = "",
        aiScriptureReferences: [String] = [],
        aiOutcome: String = "",
        aiMatchScore: Double = 0.0,
        isVerified: Bool = false,
        viewCount: Int = 0,
        impactReports: Int = 0,
        prayerCount: Int = 0,
        reportCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.authorDisplayName = authorDisplayName
        self.content = content
        self.createdAt = createdAt
        self.aiThemes = aiThemes
        self.aiEmotionalTone = aiEmotionalTone
        self.aiSpiritualMaturity = aiSpiritualMaturity
        self.aiScriptureReferences = aiScriptureReferences
        self.aiOutcome = aiOutcome
        self.aiMatchScore = aiMatchScore
        self.isVerified = isVerified
        self.viewCount = viewCount
        self.impactReports = impactReports
        self.prayerCount = prayerCount
        self.reportCount = reportCount
    }
}

// MARK: - Testimony Match Result

struct TestimonyMatchResult {
    var relevanceScore: Double
    var keyMoments: [String]
    var bridge: String
    var scriptureTheme: String
}

// MARK: - Prayer Request

struct WitnessPrayerRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var content: String
    var themes: [String]
    var emotionalState: String
    var urgencyLevel: String            // "immediate" | "ongoing" | "interceding_for_others"
    var isAnonymous: Bool
    var createdAt: Timestamp
    var aiMatchedTestimonies: [String]  // IDs of testimonies routed to this user

    init(
        id: String? = nil,
        userId: String,
        content: String,
        themes: [String] = [],
        emotionalState: String = "",
        urgencyLevel: String = "ongoing",
        isAnonymous: Bool = false,
        createdAt: Timestamp = Timestamp(date: Date()),
        aiMatchedTestimonies: [String] = []
    ) {
        self.id = id
        self.userId = userId
        self.content = content
        self.themes = themes
        self.emotionalState = emotionalState
        self.urgencyLevel = urgencyLevel
        self.isAnonymous = isAnonymous
        self.createdAt = createdAt
        self.aiMatchedTestimonies = aiMatchedTestimonies
    }
}

// MARK: - User Prayer Context (used for AI matching calls)

struct UserPrayerContext {
    var prayerThemes: [String]
    var emotionalState: String
    var recentRequests: [WitnessPrayerRequest]

    func toPromptString() -> String {
        let themes = prayerThemes.joined(separator: ", ")
        let requests = recentRequests.prefix(3).map { "- \($0.content)" }.joined(separator: "\n")
        return """
        Current emotional state: \(emotionalState)
        Prayer themes: \(themes)
        Recent prayer requests:
        \(requests)
        """
    }
}