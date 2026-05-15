import Foundation
import SwiftUI

// MARK: - Enums

enum FeedDirectionIntentType: String, Codable, CaseIterable {
    case increaseTopic, decreaseTopic, emotionalRegulation, spiritualGrowth
    case worship, bibleStudy, localChurch, reduceConflict, reducePolitics
    case reduceOutrage, creatorAffinity, timeBasedPreference, sabbathRest
    case notificationPreference, safetyConcern, unknown
}

enum FeedDirectionDuration: String, Codable, CaseIterable {
    case session, now, today, week, always
    var displayName: String {
        switch self {
        case .session: return "This session"
        case .now: return "For now"
        case .today: return "Today"
        case .week: return "This week"
        case .always: return "Always"
        }
    }
}

enum FeedDirectionIntensity: String, Codable, CaseIterable {
    case light, medium, strong
    var displayName: String {
        switch self { case .light: return "Light"; case .medium: return "Medium"; case .strong: return "Strong" }
    }
}

enum FeedDirectionVisibility: String, Codable {
    case privateOnly, applyAndPost
}

enum FeedSurface: String, Codable, CaseIterable {
    case home, media, suggestedCreators, notifications, church, search
    var displayName: String {
        switch self {
        case .home: return "Home"
        case .media: return "Media"
        case .suggestedCreators: return "Creators"
        case .notifications: return "Notifications"
        case .church: return "Church"
        case .search: return "Search"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"; case .media: return "film"; case .suggestedCreators: return "person.2"
        case .notifications: return "bell"; case .church: return "building.columns"; case .search: return "magnifyingglass"
        }
    }
}

enum FeedDirectionLocalCategory: String, Codable {
    case moreOfTopic, lessOfTopic, emotionalState, spiritualIntent
    case temporalPreference, contentSafety, creatorPreference, feedMode, unknown
}

enum FeedDirectionApplyState: Equatable {
    case idle, loading, success(SubmitFeedDirectionResponse), failed(String)
}

enum FeedMode: String, Codable, CaseIterable, Identifiable {
    case berean, worship, calmFeed, focus, community, sundayRest
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .berean: return "Berean Mode"
        case .worship: return "Worship Mode"
        case .calmFeed: return "Calm Feed"
        case .focus: return "Focus Mode"
        case .community: return "Community Mode"
        case .sundayRest: return "Sunday Rest"
        }
    }
    var icon: String {
        switch self {
        case .berean: return "book.closed"
        case .worship: return "music.note"
        case .calmFeed: return "leaf"
        case .focus: return "eye"
        case .community: return "person.3"
        case .sundayRest: return "moon.stars"
        }
    }
    var description: String {
        switch self {
        case .berean: return "Scripture-first, theological depth, slower pacing"
        case .worship: return "Music-forward, ambient visuals, reflective"
        case .calmFeed: return "Low stimulation, calming content, reduced motion"
        case .focus: return "Educational only, reduced animations"
        case .community: return "Local church, friends, prayer circles"
        case .sundayRest: return "Minimal stimulation, church-first, no infinite scroll pressure"
        }
    }
}

// MARK: - Detection

struct FeedDirectionDetectionResult: Equatable {
    let isDetected: Bool
    let confidence: Double
    let triggerPhrase: String?
    let detectedCategory: FeedDirectionLocalCategory?
    let suggestedSummary: String?

    static let empty = FeedDirectionDetectionResult(
        isDetected: false, confidence: 0, triggerPhrase: nil,
        detectedCategory: nil, suggestedSummary: nil
    )
}

// MARK: - Drafts and Requests

struct FeedDirectionDraft: Codable, Equatable {
    let rawText: String
    var interpretedSummary: String?
    var intentType: FeedDirectionIntentType
    var duration: FeedDirectionDuration
    var intensity: FeedDirectionIntensity
    var visibility: FeedDirectionVisibility
    var affectedSurfaces: [FeedSurface]
}

struct ComposerFeedDirectionContext: Codable {
    let source: String
    let timezone: String
    let localHour: Int
    let isSunday: Bool
    let reduceMotionEnabled: Bool
    let reduceTransparencyEnabled: Bool
}

struct SubmitFeedDirectionRequest: Codable {
    let rawText: String
    let composerContext: ComposerFeedDirectionContext
    let duration: FeedDirectionDuration
    let intensity: FeedDirectionIntensity
    let visibility: FeedDirectionVisibility
    let affectedSurfaces: [FeedSurface]
    let clientDetectionConfidence: Double
}

struct SubmitFeedDirectionResponse: Codable, Equatable {
    let signalId: String
    let interpretedSummary: String
    let intentType: FeedDirectionIntentType
    let topicsIncreased: [String]
    let topicsDecreased: [String]
    let modesActivated: [String]
    let affectedSurfaces: [FeedSurface]
    let duration: FeedDirectionDuration
    let intensity: FeedDirectionIntensity
    let safetyNotice: String?
    let confirmationTitle: String
    let confirmationBullets: [String]
}

struct WhyThisPostResponse: Codable {
    let postId: String
    let title: String
    let reasons: [String]
    let feedSignals: [String]
    let preferenceSignals: [String]
    let safetyNotes: [String]
    let canAdjust: Bool
}

struct FeedRankingContext: Codable {
    let activePreferenceSignalIds: [String]
    let activeModes: [String]
    let suppressedTopics: [String]
    let boostedTopics: [String]
    let localHour: Int
    let isSunday: Bool
    let feedHealthMode: String?
}

struct FeedIntelligenceSignal: Codable, Identifiable {
    let id: String
    let interpretedSummary: String
    let intentType: FeedDirectionIntentType
    let duration: FeedDirectionDuration
    let intensity: FeedDirectionIntensity
    let affectedSurfaces: [FeedSurface]
    let status: String
    let createdAt: Date?
    let expiresAt: Date?
}

struct FeedIntelligenceSummary: Codable {
    let activeSignals: [FeedIntelligenceSignal]
    let activeModes: [String]
    let boostedTopics: [String: Double]
    let suppressedTopics: [String: Double]
    let feedHealth: FeedHealthState
}

struct FeedHealthState: Codable {
    var reduceOutrage: Bool
    var reduceRapidCuts: Bool
    var preferCalmContent: Bool
    var preserveDiversity: Bool
}

// MARK: - Notification

extension Notification.Name {
    static let feedIntelligenceDidUpdate = Notification.Name("amen.feedIntelligenceDidUpdate")
}
