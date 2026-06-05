// DiscussionThreadModels.swift — AMEN App
// Firestore-matched models for the discussion thread system.
// Schema: threads/{threadId}/comments/{commentId}
//         threads/{threadId}/bereanSummaries/{summaryId}

import Foundation
import FirebaseFirestore
import SwiftUI

// MARK: - Thread

struct DiscussionThread: Identifiable, Codable {
    @DocumentID var id: String?
    var postId: String
    var postTitle: String?
    var postType: String              // "text" | "video" | "audio" | "image" | "discussion"
    var postAuthorUID: String?        // UID of the original post author (used for host-only features)
    var transcriptRef: String?        // Storage path to text transcript; enables parity path
    var isLocked: Bool
    var lockedReason: String?
    var commentCount: Int
    var bereanSummaryRef: String?     // Firestore path to latest BereanThreadSummary
    var spaceId: String?              // non-nil → space-scoped discussion thread
    var channelType: String?          // SpaceDiscussionChannelType raw value
    var createdAt: Timestamp
    var updatedAt: Timestamp
}

// MARK: - Comment

struct DiscussionComment: Identifiable, Codable {
    @DocumentID var id: String?
    var threadId: String
    var authorUID: String
    var authorDisplayName: String
    var authorAvatarURL: String?
    var parentCommentId: String?
    var depth: Int
    var body: String
    var verseKeys: [String]
    var helpfulCount: Int
    var isAcceptedAnswer: Bool
    var isDeleted: Bool
    var destination: String           // "public" | "reflection" | "churchNotes"
    var createdAt: Timestamp
    var updatedAt: Timestamp?

    enum CodingKeys: String, CodingKey {
        case id, threadId, authorUID, authorDisplayName, authorAvatarURL,
             parentCommentId, depth, body, verseKeys,
             helpfulCount, isAcceptedAnswer, isDeleted, destination,
             createdAt, updatedAt
    }
}

// MARK: - Berean Summary

struct BereanThreadSummary: Identifiable, Codable {
    @DocumentID var id: String?
    var summary: String
    var agreementPoints: [String]
    var openQuestions: [String]
    var biblicalRefs: [String]        // OSIS keys e.g. "JHN.3.16"
    var studyQuestions: [String]
    var isMock: Bool
    var tokenCount: Int
    var createdAt: Timestamp
}

// MARK: - Reputation

enum DiscussionReputationTier: String, Codable, Equatable {
    case elder, berean, seeker, none

    var label: String {
        switch self {
        case .elder:  return "Elder"
        case .berean: return "Berean"
        case .seeker: return "Seeker"
        case .none:   return ""
        }
    }

    var icon: String {
        switch self {
        case .elder:  return "crown.fill"
        case .berean: return "book.fill"
        case .seeker: return "magnifyingglass"
        case .none:   return ""
        }
    }

    var color: Color {
        switch self {
        case .elder:  return Color(hex: "#C9A84C")
        case .berean: return .blue
        case .seeker: return .green
        case .none:   return .clear
        }
    }
}

// MARK: - Duplicate result

enum DiscussionDuplicateResult: Equatable {
    case clean
    case addAngle      // similar angle exists — encourage a new angle
    case isDuplicate   // nearly identical — suggest supporting existing comment
}

// MARK: - Comment destination

enum DiscussionDestination: String, CaseIterable {
    case `public`      = "public"
    case reflection    = "reflection"

    var label: String {
        switch self {
        case .public:     return "Public"
        case .reflection: return "Reflection"
        }
    }

    var icon: String {
        switch self {
        case .public:     return "bubble.left.fill"
        case .reflection: return "lock.fill"
        }
    }
}

// MARK: - Space Discussion Channel Type

enum SpaceDiscussionChannelType: String, CaseIterable, Codable, Identifiable {
    case general   = "general"
    case questions = "questions"
    case prayer    = "prayer"
    case wins      = "wins"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:   return "General"
        case .questions: return "Questions"
        case .prayer:    return "Prayer"
        case .wins:      return "Wins"
        }
    }

    var icon: String {
        switch self {
        case .general:   return "text.bubble"
        case .questions: return "questionmark.circle"
        case .prayer:    return "hands.sparkles"
        case .wins:      return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .general:   return Color.white.opacity(0.7)
        case .questions: return Color(hex: "#5A9CF8")
        case .prayer:    return Color(hex: "#C9A84C")
        case .wins:      return Color(hex: "#4CAF50")
        }
    }
}
