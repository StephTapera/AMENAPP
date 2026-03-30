//
//  VergeModels.swift
//  AMENAPP
//
//  Codable Firestore models for the Verge live-room feature.
//

import SwiftUI
import FirebaseFirestore

// MARK: - VergeRoomType

enum VergeRoomType: String, Codable, CaseIterable {
    case openDiscussion  = "openDiscussion"
    case qa              = "qa"
    case workshop        = "workshop"
    case study           = "study"
    case coaching        = "coaching"

    var label: String {
        switch self {
        case .openDiscussion: return "Open Discussion"
        case .qa:             return "Q&A"
        case .workshop:       return "Workshop"
        case .study:          return "Bible Study"
        case .coaching:       return "Coaching"
        }
    }

    var icon: String {
        switch self {
        case .openDiscussion: return "bubble.left.and.bubble.right.fill"
        case .qa:             return "questionmark.circle.fill"
        case .workshop:       return "hammer.fill"
        case .study:          return "book.fill"
        case .coaching:       return "figure.mind.and.body"
        }
    }
}

// MARK: - VergeRoomStatus

enum VergeRoomStatus: String, Codable, CaseIterable {
    case waiting  = "waiting"
    case live     = "live"
    case ended    = "ended"
    case archived = "archived"

    var label: String {
        switch self {
        case .waiting:  return "Waiting"
        case .live:     return "Live"
        case .ended:    return "Ended"
        case .archived: return "Archived"
        }
    }

    var colorHex: String {
        switch self {
        case .waiting:  return "F59E0B"
        case .live:     return "EF4444"
        case .ended:    return "6B7280"
        case .archived: return "374151"
        }
    }

    var color: Color {
        Color(hex: colorHex)
    }
}

// MARK: - VergeMessageType

enum VergeMessageType: String, Codable, CaseIterable {
    case text      = "text"
    case reaction  = "reaction"
    case question  = "question"
    case poll      = "poll"
    case aiInsight = "aiInsight"

    var accentColor: Color {
        switch self {
        case .text:      return .white
        case .reaction:  return Color(hex: "F59E0B")
        case .question:  return Color(hex: "06B6D4")
        case .poll:      return Color(hex: "6B48FF")
        case .aiInsight: return Color(hex: "C084FC")
        }
    }
}

// MARK: - VergeRoom

struct VergeRoom: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var workspaceId: String
    var title: String
    var description: String
    var type: VergeRoomType
    var status: VergeRoomStatus
    var hostId: String
    var participantIds: [String]
    var maxParticipants: Int
    var scheduledAt: Date?
    var startedAt: Date?
    var endedAt: Date?
    var isRecorded: Bool
    var transcriptURL: String?
    var aiSummary: String?
    var isMonetized: Bool
    var ticketPrice: Double?
    var subscribersOnly: Bool
    var createdAt: Date?

    // MARK: Computed

    var isLive: Bool { status == .live }

    var isUpcoming: Bool { status == .waiting && scheduledAt != nil }

    var participantCount: Int { participantIds.count }

    /// Formatted "Starts in Xh Ym" helper (returns nil if no scheduledAt or already past)
    var startsInLabel: String? {
        guard let date = scheduledAt, date > Date() else { return nil }
        let diff = date.timeIntervalSinceNow
        let hours = Int(diff) / 3600
        let mins  = (Int(diff) % 3600) / 60
        if hours > 0 { return "Starts in \(hours)h \(mins)m" }
        return "Starts in \(mins)m"
    }
}

// MARK: - VergeMessage

struct VergeMessage: Identifiable, Codable {
    @DocumentID var id: String?
    var roomId: String
    var workspaceId: String
    var authorId: String
    var authorName: String
    var content: String
    var type: VergeMessageType
    var replyToId: String?
    var reactions: [String: Int]
    var isPinned: Bool
    var aiFlag: String?
    var createdAt: Date?
}

// MARK: - VergeCreatorProfile

struct VergeCreatorProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var workspaceId: String
    var subscriptionPrice: Double?
    var subscriberCount: Int
    var monthlyRevenue: Double
    var tipsEnabled: Bool
    var totalTipsReceived: Double
    var isVerified: Bool
    var aiRevenueProjection: Double
    var aiNextMove: String
}

// MARK: - VergeSubscription

struct VergeSubscription: Identifiable, Codable {
    @DocumentID var id: String?
    var subscriberId: String
    var creatorId: String
    var workspaceId: String
    var price: Double
    var status: String
    var startedAt: Date?
    var renewsAt: Date?
}
