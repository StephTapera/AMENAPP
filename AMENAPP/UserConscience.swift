// UserConscience.swift
// AMENAPP — Conscience Feed model

import Foundation
import FirebaseFirestore

// MARK: - UserConscience

// SOUL DATA — handle with care
struct UserConscience: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String

    // Set during onboarding
    var statedValues: [String]              // ["present father", "grow in faith", "less screen time"]
    var statedIdentityStatement: String     // "I want to be a man of peace who leads his family well"
    var spiritualGoals: [String]            // ["read Bible daily", "lead a small group"]
    var offLimitsTopics: [String]           // content user wants filtered out
    var dailyIntentionTime: String          // "09:00" — morning intention check-in time

    // Tracked by app
    var dailyUsageMinutes: Int
    var lastSessionAt: Timestamp?
    var consecutiveDaysEngaged: Int
    var contentEngagedThemes: [String]      // themes user actually clicks on
    var driftScore: Double                  // 0.0 = aligned, 1.0 = fully drifted
    var lastDriftWarningAt: Timestamp?

    // AI-generated
    var weeklyConscience: String            // AI reflection on the user's week
    var currentFocusSuggestion: String      // AI recommendation for this week
    var nextScripture: String               // verse AI selected for current state

    init(
        id: String? = nil,
        userId: String,
        statedValues: [String] = [],
        statedIdentityStatement: String = "",
        spiritualGoals: [String] = [],
        offLimitsTopics: [String] = [],
        dailyIntentionTime: String = "09:00",
        dailyUsageMinutes: Int = 0,
        lastSessionAt: Timestamp? = nil,
        consecutiveDaysEngaged: Int = 0,
        contentEngagedThemes: [String] = [],
        driftScore: Double = 0.0,
        lastDriftWarningAt: Timestamp? = nil,
        weeklyConscience: String = "",
        currentFocusSuggestion: String = "",
        nextScripture: String = ""
    ) {
        self.id = id
        self.userId = userId
        self.statedValues = statedValues
        self.statedIdentityStatement = statedIdentityStatement
        self.spiritualGoals = spiritualGoals
        self.offLimitsTopics = offLimitsTopics
        self.dailyIntentionTime = dailyIntentionTime
        self.dailyUsageMinutes = dailyUsageMinutes
        self.lastSessionAt = lastSessionAt
        self.consecutiveDaysEngaged = consecutiveDaysEngaged
        self.contentEngagedThemes = contentEngagedThemes
        self.driftScore = driftScore
        self.lastDriftWarningAt = lastDriftWarningAt
        self.weeklyConscience = weeklyConscience
        self.currentFocusSuggestion = currentFocusSuggestion
        self.nextScripture = nextScripture
    }
}

// MARK: - Activity Log (used for conscience AI calls)

struct ActivityLog: Identifiable {
    var id: String = UUID().uuidString
    var theme: String
    var durationMinutes: Int
    var timestamp: Date

    func toSummaryString() -> String {
        "[\(theme) — \(durationMinutes)m]"
    }
}

extension Array where Element == ActivityLog {
    func toSummaryString() -> String {
        guard !isEmpty else { return "No activity logged." }
        return map { $0.toSummaryString() }.joined(separator: "\n")
    }
}
