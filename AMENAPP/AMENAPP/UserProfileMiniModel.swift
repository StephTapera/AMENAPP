//
//  UserProfileMiniModel.swift
//  AMENAPP
//
//  Domain models for the UserProfileViewMini component.
//  Used in Discovery, #OpenTable, Prayer, and Testimonies contexts.
//

import Foundation

// MARK: - Trigger Type

struct UserMiniTrigger: Equatable {
    enum ArtifactType: String, Equatable {
        case openTableThread = "openTableThread"
        case prayerPost      = "prayerPost"
        case testimonyPost   = "testimonyPost"
    }

    /// Viewer's engagement state with the artifact.
    enum ViewerState: String, Equatable {
        case unread, read, replied
        /// Viewer already prayed for this prayer request today.
        case prayedToday
        /// Viewer has viewed this testimony post.
        case viewed
        case unknown

        /// Safely decode unknown raw values from the backend.
        init(rawValue: String) {
            switch rawValue {
            case "unread":     self = .unread
            case "read":       self = .read
            case "replied":    self = .replied
            case "prayedToday": self = .prayedToday
            case "viewed":     self = .viewed
            default:           self = .unknown
            }
        }
    }

    let artifactType: ArtifactType
    let artifactId: String
    let title: String?
    let topic: String?
    let viewerState: ViewerState
}

/// Canonical name used in the spec — identical to UserMiniTrigger.
typealias SuggestionTrigger = UserMiniTrigger

// MARK: - Core Model

struct UserProfileMiniModel: Identifiable, Equatable {
    let id: String                                    // userId
    let username: String
    let displayName: String
    let roleTitle: String?                            // e.g. "Worship Leader · Atlanta"
    let bioShort: String?                             // ≤ 100 chars
    let avatarURL: URL?
    let followerCount: Int?
    let sharedPrayerCount: Int?                       // prayers in common
    let mutualConnectionCount: Int?
    let mutualConnectionPreview: [MiniMutualUser]     // up to 3
    let city: String?
    let pronoun: String?                              // grammatical pronoun: "he/him", "she/her", "they/them"
    let pronunciation: String?                        // name phonetics: "JAY-den", "Eh-ZEE-kyell"
    let badges: [UserMiniBadge]
    let contextReasons: [UserMiniReason]              // engine-derived
    let suggestionSource: UserMiniSuggestionSource
    let credibility: UserMiniCredibility?
    let canMessage: Bool
    var isFollowed: Bool
    var isSavedSuggestion: Bool
    let profileRoute: String?                         // deep-link path if needed
    let trigger: UserMiniTrigger?                     // surface-specific artifact from backend
    let directRelationshipReason: String?
    let recentSharedEngagementReason: String?
    let sharedTopicReason: String?
    let communityReason: String?
    let popularityReason: String?
    let priorityExplanation: String?
    let suggestionScore: Double?
    let testimonyOverlapCount: Int?
    let topicOverlapCount: Int?
    let isProfileUnavailable: Bool
    let isBlocked: Bool
}

// MARK: - Supporting Types

struct MiniMutualUser: Identifiable, Equatable {
    let id: String
    let displayName: String
    let avatarURL: URL?
}

struct UserMiniBadge: Identifiable, Equatable {
    let id: String
    let icon: String          // SF Symbol name
    let label: String
    let color: UserMiniBadgeColor

    enum UserMiniBadgeColor: String, Equatable {
        case neutral, faith, verified, prayer, testimony
    }
}

struct UserMiniReason: Identifiable, Equatable {
    let id: String
    let label: String         // "Shared interest in Prayer"
    let icon: String?         // SF Symbol name (optional)
    let kind: ReasonKind

    enum ReasonKind: String, Equatable {
        case sharedInterest
        case mutualConnections
        case topicOverlap
        case communityOverlap
        case prayerOverlap
        case testimonyOverlap
        case popularInArea
        case engagementCompatibility
    }
}

struct UserMiniCredibility: Equatable {
    let responseLabel: String?    // e.g. "Usually responds"
    let activeLabel: String?      // e.g. "Active today"
}

struct UserMiniContextSnapshot: Equatable {
    let primaryAction: UserMiniPrimaryAction
    let secondaryAction: UserMiniSecondaryAction
    let reasons: [UserMiniReason]
    let explanation: String
    let priorityExplanation: String
    let smartActions: [UserMiniOverflowAction]
    /// False when there is no meaningful contextual signal to display.
    let showContextPanel: Bool
}

// MARK: - Suggestion Source / Context

enum UserMiniSuggestionSource: String, Equatable, CaseIterable {
    case discovery    = "Discovery"
    case openTable    = "OpenTable"
    case prayer       = "Prayer"
    case testimonies  = "Testimonies"
    case findFriends  = "FindFriends"
    case unknown      = "Unknown"

    var displayName: String { rawValue }
}

// MARK: - CTA Actions

enum UserMiniPrimaryAction: Equatable {
    case follow
    /// Open the user's full profile (e.g. already followed in discovery, or blocked/unavailable).
    case viewProfile
    /// Open the shared OpenTable thread — viewer has not read it yet.
    case readThread
    /// Open the shared OpenTable thread — viewer has read but not replied.
    case joinConversation
    case prayTogether
    /// Open a prayer DM scoped to a specific prayer topic.
    case prayForTopic(topic: String)
    case viewTestimony(postId: String?, title: String?)

    var label: String {
        switch self {
        case .follow:            return "Follow"
        case .viewProfile:       return "View Profile"
        case .readThread:        return "Read Thread"
        case .joinConversation:  return "Join"
        case .prayTogether:      return "Pray Together"
        case .prayForTopic(let topic):
            let cap = topic.count > 14 ? String(topic.prefix(14)) + "…" : topic
            return "Pray for \(cap)"
        case .viewTestimony(_, let title):
            if let title {
                let cap = title.count > 18 ? String(title.prefix(18)) + "…" : title
                return "View \(cap)"
            }
            return "View Testimony"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .follow:            return "Follow this person"
        case .viewProfile:       return "View their full profile"
        case .readThread:        return "Read the shared thread"
        case .joinConversation:  return "Join their conversation"
        case .prayTogether:      return "Pray together with this person"
        case .prayForTopic(let topic):
            return "Pray for \(topic)"
        case .viewTestimony(let postId, let title):
            if let title { return "View testimony: \(title)" }
            return postId != nil ? "View their testimony post" : "View testimony"
        }
    }
}

enum UserMiniSecondaryAction: Equatable {
    case message
    case viewProfile
    case saveForLater

    var label: String {
        switch self {
        case .message:      return "Message"
        case .viewProfile:  return "Profile"
        case .saveForLater: return "Save"
        }
    }
}

// MARK: - Overflow Actions

enum UserMiniOverflowAction: String, CaseIterable, Identifiable {
    case viewProfile       = "View Full Profile"
    case saveForLater      = "Save for Later"
    case hideSuggestion    = "Hide Suggestion"
    case seeSimilar        = "See Similar People"
    case report            = "Report Account"
    case shareProfile      = "Share Profile"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .viewProfile:    return "person.crop.circle"
        case .saveForLater:   return "bookmark"
        case .hideSuggestion: return "eye.slash"
        case .seeSimilar:     return "person.2"
        case .report:         return "flag"
        case .shareProfile:   return "square.and.arrow.up"
        }
    }

    var isDestructive: Bool { self == .report }
}

// MARK: - Analytics Event

struct UserMiniAnalyticsEvent {
    enum Kind: String {
        case impression, profileOpen, followTap, followSuccess, followFailure
        case unfollowTap
        case messageTap, messageBlocked, primaryCTATap, secondaryCTATap
        case hideSuggestion, undoHide, saveSuggestion, showMoreTapped, overflowTapped
        case seeSimilar, report, share
    }

    let kind: Kind
    let userId: String
    let viewerId: String?
    let source: UserMiniSuggestionSource
    let ctaType: String?
    let triggerArtifactId: String?
    let position: Int?
    let suggestionScore: Double?
}
