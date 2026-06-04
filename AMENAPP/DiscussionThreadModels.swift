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
    var postType: String              // "general" | "political" | …
    var isLocked: Bool
    var commentCount: Int
    var bereanSummaryRef: String?     // Firestore path to latest BereanThreadSummary
    var createdAt: Timestamp
    var updatedAt: Timestamp
}

// MARK: - Comment

struct DiscussionComment: Identifiable, Codable {
    @DocumentID var id: String?
    var threadId: String
    var authorId: String
    var authorDisplayName: String
    var authorAvatarURL: String?
    var body: String
    var helpfulCount: Int
    var isDeleted: Bool
    var destination: String           // "public" | "reflection" | "churchNotes"
    var createdAt: Timestamp

    enum CodingKeys: String, CodingKey {
        case id, threadId, authorId, authorDisplayName, authorAvatarURL,
             body, helpfulCount, isDeleted, destination, createdAt
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
