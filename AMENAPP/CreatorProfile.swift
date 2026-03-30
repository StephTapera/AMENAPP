// CreatorProfile.swift — AMEN App
// Models for Creator Economic Graph

import Foundation
import FirebaseFirestore

// MARK: - CreatorProfile

struct CreatorProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var monthlyRevenue: Double
    var lifetimeEarnings: Double
    var subscriberCount: Int
    var subscriptionPrice: Double?
    var subscriptionBenefits: [String]
    var tipsEnabled: Bool
    var digitalGoods: [DigitalGood]
    var aiRevenueProjection: Double
    var aiNextMoveRecommendation: String
    var trustScore: Double              // 0.0 – 1.0
    var verificationStatus: VerificationStatus
    var revenueHistory: [RevenuePoint]  // last 6 months

    enum VerificationStatus: String, Codable {
        case unverified, pending, verified
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, monthlyRevenue, lifetimeEarnings, subscriberCount,
             subscriptionPrice, subscriptionBenefits, tipsEnabled, digitalGoods,
             aiRevenueProjection, aiNextMoveRecommendation, trustScore,
             verificationStatus, revenueHistory
    }

    static let empty = CreatorProfile(
        userId: "",
        monthlyRevenue: 0,
        lifetimeEarnings: 0,
        subscriberCount: 0,
        subscriptionPrice: nil,
        subscriptionBenefits: [],
        tipsEnabled: true,
        digitalGoods: [],
        aiRevenueProjection: 0,
        aiNextMoveRecommendation: "Post consistently to grow your audience.",
        trustScore: 0.5,
        verificationStatus: .unverified,
        revenueHistory: []
    )
}

// MARK: - DigitalGood

struct DigitalGood: Identifiable, Codable {
    var id: String
    var title: String
    var description: String
    var price: Double
    var fileURL: String?
    var thumbnailURL: String?
    var salesCount: Int
    var type: GoodType

    enum GoodType: String, Codable, CaseIterable {
        case prayerJournal, devotional, music, artwork, ebook, other
        var label: String {
            switch self {
            case .prayerJournal: return "Prayer Journal"
            case .devotional: return "Devotional"
            case .music: return "Music"
            case .artwork: return "Artwork"
            case .ebook: return "eBook"
            case .other: return "Digital Good"
            }
        }
        var icon: String {
            switch self {
            case .prayerJournal: return "hands.sparkles.fill"
            case .devotional: return "book.closed.fill"
            case .music: return "music.note"
            case .artwork: return "paintpalette.fill"
            case .ebook: return "doc.richtext.fill"
            case .other: return "square.grid.2x2.fill"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, price, fileURL, thumbnailURL, salesCount, type
    }
}

// MARK: - RevenuePoint (for chart)

struct RevenuePoint: Identifiable, Codable {
    var id: String
    var month: String       // "Jan", "Feb", etc.
    var amount: Double

    enum CodingKeys: String, CodingKey {
        case id, month, amount
    }
}

// MARK: - ContentSafetyLog

struct ContentSafetyLog: Identifiable, Codable {
    @DocumentID var id: String?
    var contentId: String
    var contentType: String
    var authorId: String
    var safetyScore: Double
    var flaggedCategories: [String]
    var decision: SafetyDecision
    var aiReasoning: String
    var reviewedAt: Date?
    var appealedAt: Date?
    var appealText: String?
    var appealOutcome: String?

    enum SafetyDecision: String, Codable {
        case approved, warned, blocked, appealed, underReview
    }

    enum CodingKeys: String, CodingKey {
        case id, contentId, contentType, authorId, safetyScore, flaggedCategories,
             decision, aiReasoning, reviewedAt, appealedAt, appealText, appealOutcome
    }
}

// MARK: - CoCreationSession

struct CoCreationSession: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var type: SessionType
    var hostId: String
    var hostName: String?
    var collaboratorIds: [String]
    var canvasState: String         // JSON-encoded content
    var isLive: Bool
    var isOpenToAnyone: Bool
    var maxCollaborators: Int
    var aiSuggestions: [String]
    var createdAt: Date?
    var endedAt: Date?

    enum SessionType: String, Codable, CaseIterable {
        case song, prayer, scriptureStudy, plan, creativeWriting

        var label: String {
            switch self {
            case .song: return "Song / Lyrics"
            case .prayer: return "Prayer"
            case .scriptureStudy: return "Scripture Study"
            case .plan: return "Ministry Plan"
            case .creativeWriting: return "Creative Writing"
            }
        }

        var icon: String {
            switch self {
            case .song: return "music.note"
            case .prayer: return "hands.sparkles.fill"
            case .scriptureStudy: return "book.fill"
            case .plan: return "map.fill"
            case .creativeWriting: return "pencil.and.outline"
            }
        }

        var gradient: [String] { // color hex names
            switch self {
            case .song: return ["6B48FF", "C084FC"]
            case .prayer: return ["3B82F6", "06B6D4"]
            case .scriptureStudy: return ["F59E0B", "EF4444"]
            case .plan: return ["10B981", "3B82F6"]
            case .creativeWriting: return ["EC4899", "F59E0B"]
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, type, hostId, hostName, collaboratorIds, canvasState,
             isLive, isOpenToAnyone, maxCollaborators, aiSuggestions, createdAt, endedAt
    }
}
