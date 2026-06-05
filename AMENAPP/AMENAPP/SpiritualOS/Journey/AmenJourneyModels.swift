// AmenJourneyModels.swift
// AMEN Spiritual Journey Engine — Data Models
//
// Defines the canonical types for the personalized spiritual journey layer.
// Firestore paths are documented on each model.
// No social metrics. No public visibility. All data is private by default.

import Foundation
import SwiftUI

// MARK: - SpiritualJourneyStage

enum SpiritualJourneyStage: String, CaseIterable, Codable {
    case newBeliever       = "new_believer"
    case returningToFaith  = "returning_to_faith"
    case marriage          = "marriage"
    case parenting         = "parenting"
    case leadership        = "leadership"
    case entrepreneurship  = "entrepreneurship"
    case recovery          = "recovery"
    case missions          = "missions"
    case youngAdult        = "young_adult"
    case student           = "student"
    case careerGrowth      = "career_growth"
    case prayer            = "prayer"
    case bibleStudy        = "bible_study"
    case volunteerism      = "volunteerism"
    case churchLeadership  = "church_leadership"
    case custom            = "custom"

    // MARK: Display

    var displayName: String {
        switch self {
        case .newBeliever:      return "New Believer"
        case .returningToFaith: return "Returning to Faith"
        case .marriage:         return "Marriage"
        case .parenting:        return "Parenting"
        case .leadership:       return "Leadership"
        case .entrepreneurship: return "Entrepreneurship"
        case .recovery:         return "Recovery"
        case .missions:         return "Missions"
        case .youngAdult:       return "Young Adult"
        case .student:          return "Student"
        case .careerGrowth:     return "Career Growth"
        case .prayer:           return "Prayer"
        case .bibleStudy:       return "Bible Study"
        case .volunteerism:     return "Volunteerism"
        case .churchLeadership: return "Church Leadership"
        case .custom:           return "My Own Journey"
        }
    }

    // MARK: Icon (SF Symbol)

    var iconName: String {
        switch self {
        case .newBeliever:      return "sparkles"
        case .returningToFaith: return "arrow.uturn.left.circle.fill"
        case .marriage:         return "heart.fill"
        case .parenting:        return "figure.2.and.child.holdinghands"
        case .leadership:       return "person.bust.fill"
        case .entrepreneurship: return "briefcase.fill"
        case .recovery:         return "leaf.fill"
        case .missions:         return "globe.americas.fill"
        case .youngAdult:       return "person.fill"
        case .student:          return "graduationcap.fill"
        case .careerGrowth:     return "chart.line.uptrend.xyaxis"
        case .prayer:           return "hands.sparkles.fill"
        case .bibleStudy:       return "book.fill"
        case .volunteerism:     return "hand.raised.fill"
        case .churchLeadership: return "building.columns.fill"
        case .custom:           return "pencil.circle.fill"
        }
    }

    // MARK: Description

    var description: String {
        switch self {
        case .newBeliever:
            return "Just started your walk with Christ"
        case .returningToFaith:
            return "Coming back to your faith foundation"
        case .marriage:
            return "Building a Christ-centered marriage"
        case .parenting:
            return "Raising children in faith"
        case .leadership:
            return "Growing as a leader in life and ministry"
        case .entrepreneurship:
            return "Building something with purpose and integrity"
        case .recovery:
            return "Healing and restoration through faith"
        case .missions:
            return "Serving locally or globally for the Kingdom"
        case .youngAdult:
            return "Navigating adulthood with faith at the center"
        case .student:
            return "Learning and growing through school years"
        case .careerGrowth:
            return "Pursuing excellence and calling in your career"
        case .prayer:
            return "Deepening your prayer life and intimacy with God"
        case .bibleStudy:
            return "Going deeper into Scripture and theology"
        case .volunteerism:
            return "Serving your community and local church"
        case .churchLeadership:
            return "Leading and shepherding within the local church"
        case .custom:
            return "Describe your journey in your own words"
        }
    }

    // MARK: Color

    /// Each stage has a distinct but tasteful color. All are muted enough
    /// not to clash on white card surfaces.
    var color: Color {
        switch self {
        case .newBeliever:      return Color(red: 0.27, green: 0.62, blue: 0.96)  // sky blue
        case .returningToFaith: return Color(red: 0.40, green: 0.76, blue: 0.65)  // seafoam
        case .marriage:         return Color(red: 0.92, green: 0.45, blue: 0.58)  // rose
        case .parenting:        return Color(red: 0.98, green: 0.72, blue: 0.36)  // warm amber
        case .leadership:       return Color(red: 0.42, green: 0.36, blue: 0.88)  // deep violet
        case .entrepreneurship: return Color(red: 0.18, green: 0.58, blue: 0.78)  // teal
        case .recovery:         return Color(red: 0.30, green: 0.72, blue: 0.48)  // soft emerald
        case .missions:         return Color(red: 0.85, green: 0.52, blue: 0.26)  // terracotta
        case .youngAdult:       return Color(red: 0.56, green: 0.42, blue: 0.92)  // lavender
        case .student:          return Color(red: 0.24, green: 0.52, blue: 0.88)  // indigo-blue
        case .careerGrowth:     return Color(red: 0.18, green: 0.68, blue: 0.60)  // jade
        case .prayer:           return Color(red: 0.66, green: 0.48, blue: 0.92)  // soft purple
        case .bibleStudy:       return Color(red: 0.83, green: 0.69, blue: 0.22)  // amenGold
        case .volunteerism:     return Color(red: 0.28, green: 0.74, blue: 0.56)  // mint
        case .churchLeadership: return Color(red: 0.52, green: 0.32, blue: 0.82)  // royal purple
        case .custom:           return Color(red: 0.60, green: 0.60, blue: 0.62)  // neutral slate
        }
    }

    // MARK: Relevant search terms for Firestore queries

    var relevantSearchTerms: [String] {
        switch self {
        case .newBeliever:
            return ["new believer", "baptism", "first steps", "foundation", "salvation"]
        case .returningToFaith:
            return ["returning", "prodigal", "rededication", "restoration", "renewal"]
        case .marriage:
            return ["marriage", "spouse", "wedding", "covenant", "husband", "wife", "couples"]
        case .parenting:
            return ["parenting", "children", "family", "motherhood", "fatherhood", "kids"]
        case .leadership:
            return ["leadership", "mentoring", "influence", "vision", "character", "authority"]
        case .entrepreneurship:
            return ["entrepreneur", "business", "calling", "stewardship", "work", "purpose"]
        case .recovery:
            return ["recovery", "addiction", "healing", "restoration", "redemption", "sobriety"]
        case .missions:
            return ["missions", "evangelism", "outreach", "global", "justice", "serve"]
        case .youngAdult:
            return ["young adult", "college", "twenties", "identity", "relationships", "independence"]
        case .student:
            return ["student", "school", "college", "university", "academic", "youth"]
        case .careerGrowth:
            return ["career", "vocation", "calling", "work", "promotion", "excellence", "finances"]
        case .prayer:
            return ["prayer", "intercession", "fasting", "devotional", "quiet time", "spiritual disciplines"]
        case .bibleStudy:
            return ["bible study", "scripture", "theology", "hermeneutics", "commentary", "devotional"]
        case .volunteerism:
            return ["volunteer", "serve", "community", "outreach", "giving", "hospitality"]
        case .churchLeadership:
            return ["church leader", "pastor", "elder", "deacon", "ministry", "shepherd", "preaching"]
        case .custom:
            return []
        }
    }
}

// MARK: - UserJourneyProfile

/// The user's current journey profile.
/// Firestore path: users/{userId}/journeyProfile (document)
struct UserJourneyProfile: Codable {
    /// The primary journey stage driving content recommendations.
    var primaryStage: SpiritualJourneyStage

    /// Up to 2 secondary stages for supplemental recommendations.
    var secondaryStages: [SpiritualJourneyStage]

    /// Only populated when primaryStage == .custom.
    var customDescription: String?

    var setAt: Date
    var updatedAt: Date

    init(
        primaryStage: SpiritualJourneyStage,
        secondaryStages: [SpiritualJourneyStage] = [],
        customDescription: String? = nil,
        setAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.primaryStage = primaryStage
        self.secondaryStages = Array(secondaryStages.prefix(2))
        self.customDescription = customDescription
        self.setAt = setAt
        self.updatedAt = updatedAt
    }
}

// MARK: - JourneyProgressItem

/// Tracks a single piece of in-progress or completed content.
/// Firestore path: users/{userId}/journeyProgress (collection)
struct JourneyProgressItem: Identifiable, Codable {
    let id: String
    /// "study", "discussion", "mentorship", "event", "prayer"
    var type: String
    var title: String
    var resourceId: String
    /// 0.0 to 1.0
    var progressFraction: Double
    var lastAccessedAt: Date
    var completed: Bool

    var typeIcon: String {
        switch type {
        case "study":       return "book.fill"
        case "discussion":  return "bubble.left.and.bubble.right.fill"
        case "mentorship":  return "person.badge.plus.fill"
        case "event":       return "calendar"
        case "prayer":      return "hands.sparkles.fill"
        default:            return "circle.fill"
        }
    }
}

// MARK: - PersonalGrowthSnapshot

/// Aggregated private growth metrics. Never shared or made public.
/// Firestore path: users/{userId}/growthSnapshot (document)
struct PersonalGrowthSnapshot: Codable {
    var studiesCompleted: Int
    var studiesInProgress: Int
    var prayerSessionsThisMonth: Int
    var mentorshipSessionsTotal: Int
    var communitiesJoined: Int
    var eventsAttended: Int
    var notesWritten: Int
    var discussionsParticipated: Int
    var computedAt: Date

    /// The 2 highest-count metric labels — computed by AmenJourneyEngine.
    var strongAreas: [String]

    /// The 2 lowest-count metric labels — computed by AmenJourneyEngine.
    var growthOpportunities: [String]

    static let empty = PersonalGrowthSnapshot(
        studiesCompleted: 0,
        studiesInProgress: 0,
        prayerSessionsThisMonth: 0,
        mentorshipSessionsTotal: 0,
        communitiesJoined: 0,
        eventsAttended: 0,
        notesWritten: 0,
        discussionsParticipated: 0,
        computedAt: Date(),
        strongAreas: [],
        growthOpportunities: []
    )
}
