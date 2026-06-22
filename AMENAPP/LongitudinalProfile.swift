// LongitudinalProfile.swift — AMEN App
// Model for Longitudinal Self / Your Journey feature

import Foundation
import FirebaseFirestore

// MARK: - LongitudinalProfile

struct LongitudinalProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var growthArcs: [GrowthArc]
    var topicEvolution: [TopicSnapshot]
    var milestones: [JourneyMilestone]
    var lastAnalyzedAt: Date?
    var currentChapter: String
    var isSharedPublicly: Bool

    enum CodingKeys: String, CodingKey {
        case id, userId, growthArcs, topicEvolution, milestones,
             lastAnalyzedAt, currentChapter, isSharedPublicly
    }

    static let empty = LongitudinalProfile(
        userId: "",
        growthArcs: [],
        topicEvolution: [],
        milestones: [],
        lastAnalyzedAt: nil,
        currentChapter: "A New Chapter",
        isSharedPublicly: false
    )
}

// MARK: - GrowthArc

struct GrowthArc: Identifiable, Codable {
    var id: String
    var fromState: String           // e.g. "Doubt"
    var toState: String             // e.g. "Faith"
    var sfSymbol: String            // SF Symbol name representing the arc
    var startDate: Date?
    var endDate: Date?
    var relatedPostIds: [String]
    var summary: String

    enum CodingKeys: String, CodingKey {
        case id, fromState, toState, sfSymbol, startDate, endDate, relatedPostIds, summary
    }

    static let samples: [GrowthArc] = [
        GrowthArc(id: "1", fromState: "Doubt", toState: "Faith",
                  sfSymbol: "arrow.up.heart.fill",
                  startDate: Calendar.current.date(byAdding: .month, value: -18, to: Date()),
                  endDate: Calendar.current.date(byAdding: .month, value: -6, to: Date()),
                  relatedPostIds: [], summary: "A season of wrestling with God that led to deeper trust."),
        GrowthArc(id: "2", fromState: "Isolation", toState: "Community",
                  sfSymbol: "person.3.fill",
                  startDate: Calendar.current.date(byAdding: .month, value: -12, to: Date()),
                  endDate: Calendar.current.date(byAdding: .month, value: -3, to: Date()),
                  relatedPostIds: [], summary: "Finding belonging in the body of Christ."),
    ]
}

// MARK: - TopicSnapshot

struct TopicSnapshot: Identifiable, Codable {
    var id: String
    var year: Int
    var topTopics: [String]
    var emotionalColor: String      // "gold" | "blue" | "purple" | "green"
    var aiChapterTitle: String
    var topPostIds: [String]
    var scriptureOfYear: String?

    enum CodingKeys: String, CodingKey {
        case id, year, topTopics, emotionalColor, aiChapterTitle, topPostIds, scriptureOfYear
    }
}

// MARK: - JourneyMilestone

struct JourneyMilestone: Identifiable, Codable {
    var id: String
    var title: String
    var description: String
    var date: Date?
    var sfSymbol: String
    var postId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, date, sfSymbol, postId
    }
}
