// AmenConversationOSService.swift
// AMEN Conversation OS — Firebase Service Layer
//
// All AI operations route through Firebase Cloud Functions (server-side only).
// Permissions, moderation, and compression all happen on the backend.
// This client layer: validates flags, authenticates, calls, decodes.

import Foundation
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class AmenConversationOSService: ObservableObject {
    static let shared = AmenConversationOSService()

    private let functions = Functions.functions()
    private let flags = AMENFeatureFlags.shared

    // MARK: - Generate Catch-Up Recap

    func generateCatchUpRecap(
        spaceId: String,
        surface: ConversationOSSurface,
        unreadCount: Int,
        lastVisitedAt: Date?
    ) async throws -> ConversationSummary {
        guard flags.conversationOSEnabled, flags.catchUpRecapsEnabled else {
            throw ConversationOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ConversationOSError.unauthenticated
        }

        var payload: [String: Any] = [
            "spaceId": spaceId,
            "surface": surface.rawValue,
            "userId": uid,
            "unreadCount": unreadCount
        ]
        if let lastVisitedAt {
            payload["lastVisitedAt"] = ISO8601DateFormatter().string(from: lastVisitedAt)
        }

        let result = try await functions.httpsCallable("generateCatchUpRecap").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw ConversationOSError.invalidResponse
        }
        return try decodeSummary(from: data)
    }

    // MARK: - Generate Topic Clusters

    func generateTopicClusters(
        spaceId: String,
        threadId: String?,
        surface: ConversationOSSurface
    ) async throws -> [ConversationTopicCluster] {
        guard flags.conversationOSEnabled, flags.topicClusteringEnabled else {
            throw ConversationOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ConversationOSError.unauthenticated
        }

        var payload: [String: Any] = [
            "spaceId": spaceId,
            "surface": surface.rawValue,
            "userId": uid
        ]
        if let threadId { payload["threadId"] = threadId }

        let result = try await functions.httpsCallable("generateTopicClusters").call(payload)
        guard let clusters = (result.data as? [String: Any])?["clusters"] as? [[String: Any]] else {
            return []
        }
        return clusters.compactMap { decodeCluster(from: $0) }
    }

    // MARK: - Extract Action Items

    func extractActionItems(threadId: String, spaceId: String) async throws -> [ConversationActionItem] {
        guard flags.conversationOSEnabled, flags.actionExtractionEnabled else {
            throw ConversationOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ConversationOSError.unauthenticated
        }

        let payload: [String: Any] = [
            "threadId": threadId,
            "spaceId": spaceId,
            "userId": uid
        ]

        let result = try await functions.httpsCallable("extractConversationActions").call(payload)
        guard let actions = (result.data as? [String: Any])?["actions"] as? [[String: Any]] else {
            return []
        }
        return actions.compactMap { decodeActionItem(from: $0) }
    }

    // MARK: - Personalized Summary

    func getPersonalizedSummary(request: PersonalizedSummaryRequest) async throws -> ConversationSummary {
        guard flags.conversationOSEnabled, flags.personalizedInsightsEnabled else {
            throw ConversationOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ConversationOSError.unauthenticated
        }

        var payload: [String: Any] = [
            "spaceId": request.spaceId,
            "surface": request.surface.rawValue,
            "userId": uid,
            "userRole": request.userRole.rawValue,
            "orgType": request.orgType.rawValue,
            "unreadCount": request.unreadCount,
            "followedTopics": request.followedTopics,
            "preferredLength": request.preferredLength.rawValue
        ]
        if let lastVisitedAt = request.lastVisitedAt {
            payload["lastVisitedAt"] = ISO8601DateFormatter().string(from: lastVisitedAt)
        }

        let result = try await functions.httpsCallable("getPersonalizedSummary").call(payload)
        guard let data = result.data as? [String: Any] else {
            throw ConversationOSError.invalidResponse
        }
        return try decodeSummary(from: data)
    }

    // MARK: - Organizational Memory

    func queryOrganizationalMemory(orgId: String, query: String) async throws -> ConversationOrganizationalMemory? {
        guard flags.conversationOSEnabled, flags.organizationalMemoryEnabled else {
            throw ConversationOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ConversationOSError.unauthenticated
        }

        let payload: [String: Any] = ["orgId": orgId, "query": query, "userId": uid]
        let result = try await functions.httpsCallable("queryOrganizationalMemory").call(payload)
        guard let data = (result.data as? [String: Any])?["memory"] as? [String: Any] else {
            return nil
        }
        return decodeOrgMemory(from: data)
    }

    // MARK: - Action Status

    func updateActionStatus(actionId: String, status: ConversationActionStatus, spaceId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ConversationOSError.unauthenticated }
        let payload: [String: Any] = ["actionId": actionId, "status": status.rawValue, "spaceId": spaceId, "userId": uid]
        try await functions.httpsCallable("updateConversationActionStatus").call(payload)
    }

    // MARK: - Decision

    func confirmDecision(decisionId: String, spaceId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ConversationOSError.unauthenticated }
        let payload: [String: Any] = ["decisionId": decisionId, "action": "confirm", "spaceId": spaceId, "userId": uid]
        try await functions.httpsCallable("updateConversationDecision").call(payload)
    }

    func challengeDecision(decisionId: String, spaceId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ConversationOSError.unauthenticated }
        let payload: [String: Any] = ["decisionId": decisionId, "action": "challenge", "spaceId": spaceId, "userId": uid]
        try await functions.httpsCallable("updateConversationDecision").call(payload)
    }

    // MARK: - Dismiss

    func dismissSummary(summaryId: String, spaceId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ConversationOSError.unauthenticated }
        let payload: [String: Any] = ["summaryId": summaryId, "spaceId": spaceId, "userId": uid]
        try await functions.httpsCallable("dismissConversationSummary").call(payload)
    }

    // MARK: - Decode Helpers

    private func decodeSummary(from data: [String: Any]) throws -> ConversationSummary {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder.amenISO8601.decode(ConversationSummary.self, from: jsonData)
    }

    private func decodeCluster(from data: [String: Any]) -> ConversationTopicCluster? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        return try? JSONDecoder.amenISO8601.decode(ConversationTopicCluster.self, from: jsonData)
    }

    private func decodeActionItem(from data: [String: Any]) -> ConversationActionItem? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        return try? JSONDecoder.amenISO8601.decode(ConversationActionItem.self, from: jsonData)
    }

    private func decodeOrgMemory(from data: [String: Any]) -> ConversationOrganizationalMemory? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        return try? JSONDecoder.amenISO8601.decode(ConversationOrganizationalMemory.self, from: jsonData)
    }
}

// MARK: - Error

enum ConversationOSError: Error, LocalizedError {
    case featureDisabled
    case unauthenticated
    case invalidResponse
    case sensitiveSpaceBlocked
    case permissionDenied(String)
    case moderationFailed
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .featureDisabled:          return "This feature is not currently available."
        case .unauthenticated:          return "You must be signed in."
        case .invalidResponse:          return "Unable to process the response. Please try again."
        case .sensitiveSpaceBlocked:    return "AI summaries are not available in this space."
        case .permissionDenied(let m):  return m
        case .moderationFailed:         return "Content could not be processed safely."
        case .rateLimited:              return "Too many requests. Please try again shortly."
        }
    }
}

// MARK: - JSONDecoder Helper

private extension JSONDecoder {
    static let amenISO8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
