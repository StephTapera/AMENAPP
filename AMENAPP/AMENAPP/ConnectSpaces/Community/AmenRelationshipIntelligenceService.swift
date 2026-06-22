// AmenRelationshipIntelligenceService.swift
// AMEN ConnectSpaces — Community Intelligence Layer
// Built 2026-06-03
//
// Service + model layer for the AI-driven host management dashboard.
// All CF calls use FirebaseFunctions; no client-side ML or key exposure.

import Foundation
import FirebaseFunctions

// MARK: - Models

struct CommunityDigest: Codable {
    var totalNewMessages: Int
    var activeTopics: [String]
    var unansweredQuestions: [DigestQuestion]
    var prayerRequestsNeedingAttention: [DigestPrayerRequest]
}

struct DigestQuestion: Identifiable, Codable {
    var id: String
    var text: String
    var authorFirstName: String
    var askedDaysAgo: Int
}

struct DigestPrayerRequest: Identifiable, Codable {
    var id: String
    var text: String
    var authorFirstName: String
    var postedDaysAgo: Int
}

enum MemberAction: String, Codable {
    case welcome
    case followUp
    case checkIn
    case recognizeLeadership

    var label: String {
        switch self {
        case .welcome:              return "Welcome"
        case .followUp:             return "Follow Up"
        case .checkIn:              return "Check In"
        case .recognizeLeadership:  return "Recognize"
        }
    }

    var icon: String {
        switch self {
        case .welcome:              return "hand.wave"
        case .followUp:             return "text.bubble"
        case .checkIn:              return "heart"
        case .recognizeLeadership:  return "star"
        }
    }
}

struct MemberInsight: Identifiable, Codable {
    var id: String
    var userId: String
    var displayName: String
    var reason: String
    var recommendedAction: MemberAction
}

// MARK: - Health Metrics

struct SpaceHealthMetrics: Codable {
    var vitalityScore: Int              // 0–100
    var memberRetentionPct: Double
    var avgEventAttendance: Double
    var prayerEngagementRate: Double    // avg responses per request
    var discussionHealthAvg: Double     // avg replies per thread
    var mentorshipCompletionsThisMonth: Int
    var trend: String                   // "growing" | "stable" | "declining"
}

// MARK: - Service

@MainActor
final class AmenRelationshipIntelligenceService {

    static let shared = AmenRelationshipIntelligenceService()
    private let functions = Functions.functions()

    private init() {}

    // MARK: - Digest

    func fetchDigest(spaceId: String) async throws -> CommunityDigest {
        let payload: [String: Any] = ["spaceId": spaceId]
        let result = try await functions
            .httpsCallable("getCommunityAIDigest")
            .call(payload)

        guard let raw = result.data as? [String: Any] else {
            throw IntelligenceError.invalidResponse
        }

        return try CommunityDigest(from: raw)
    }

    // MARK: - Member Insights

    func fetchMemberInsights(spaceId: String) async throws -> [MemberInsight] {
        let payload: [String: Any] = ["spaceId": spaceId]
        let result = try await functions
            .httpsCallable("getMemberInsights")
            .call(payload)

        guard let rawList = result.data as? [[String: Any]] else {
            throw IntelligenceError.invalidResponse
        }

        return rawList.compactMap { MemberInsight(from: $0) }
    }

    // MARK: - Mark Followed Up

    func markMemberFollowedUp(spaceId: String, userId: String) async throws {
        let payload: [String: Any] = ["spaceId": spaceId, "userId": userId]
        _ = try await functions
            .httpsCallable("markMemberFollowedUp")
            .call(payload)
    }

    // MARK: - Dismiss Insight

    func dismissInsight(spaceId: String, insightId: String) async throws {
        let payload: [String: Any] = ["spaceId": spaceId, "insightId": insightId]
        _ = try await functions
            .httpsCallable("dismissCommunityInsight")
            .call(payload)
    }

    // MARK: - Space Health Metrics

    func fetchHealthMetrics(spaceId: String) async throws -> SpaceHealthMetrics {
        let payload: [String: Any] = ["spaceId": spaceId]
        let result = try await functions
            .httpsCallable("getSpaceHealthMetrics")
            .call(payload)

        guard let raw = result.data as? [String: Any] else {
            throw IntelligenceError.invalidResponse
        }

        return SpaceHealthMetrics(from: raw)
    }
}

// MARK: - Error

enum IntelligenceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an unexpected response. Please try again."
        }
    }
}

// MARK: - Codable helpers (dictionary → struct)

private extension CommunityDigest {
    init(from dict: [String: Any]) throws {
        self.totalNewMessages = dict["totalNewMessages"] as? Int ?? 0
        self.activeTopics = dict["activeTopics"] as? [String] ?? []

        let rawQuestions = dict["unansweredQuestions"] as? [[String: Any]] ?? []
        self.unansweredQuestions = rawQuestions.compactMap { DigestQuestion(from: $0) }

        let rawPrayer = dict["prayerRequestsNeedingAttention"] as? [[String: Any]] ?? []
        self.prayerRequestsNeedingAttention = rawPrayer.compactMap { DigestPrayerRequest(from: $0) }
    }
}

private extension DigestQuestion {
    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let text = dict["text"] as? String else { return nil }
        self.id = id
        self.text = text
        self.authorFirstName = dict["authorFirstName"] as? String ?? ""
        self.askedDaysAgo = dict["askedDaysAgo"] as? Int ?? 0
    }
}

private extension DigestPrayerRequest {
    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let text = dict["text"] as? String else { return nil }
        self.id = id
        self.text = text
        self.authorFirstName = dict["authorFirstName"] as? String ?? ""
        self.postedDaysAgo = dict["postedDaysAgo"] as? Int ?? 0
    }
}

private extension MemberInsight {
    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let userId = dict["userId"] as? String,
              let displayName = dict["displayName"] as? String,
              let reason = dict["reason"] as? String else { return nil }
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.reason = reason
        let actionRaw = dict["recommendedAction"] as? String ?? ""
        self.recommendedAction = MemberAction(rawValue: actionRaw) ?? .checkIn
    }
}

private extension SpaceHealthMetrics {
    init(from dict: [String: Any]) {
        self.vitalityScore = dict["vitalityScore"] as? Int ?? 0
        self.memberRetentionPct = dict["memberRetentionPct"] as? Double ?? 0
        self.avgEventAttendance = dict["avgEventAttendance"] as? Double ?? 0
        self.prayerEngagementRate = dict["prayerEngagementRate"] as? Double ?? 0
        self.discussionHealthAvg = dict["discussionHealthAvg"] as? Double ?? 0
        self.mentorshipCompletionsThisMonth = dict["mentorshipCompletionsThisMonth"] as? Int ?? 0
        self.trend = dict["trend"] as? String ?? "stable"
    }
}
