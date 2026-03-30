// ArkService.swift
// AMENAPP — Ark Protocol service layer

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - ArkService

final class ArkService {

    static let shared = ArkService()
    private init() {}

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Communities

    /// Fetches a paginated list of Ark communities.
    func fetchCommunities(limit: Int = 20) async throws -> [ArkCommunity] {
        let snap = try await db.collection("arkCommunities")
            .order(by: "memberCount", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ArkCommunity.self) }
    }

    /// Fetches a single community by ID.
    func fetchCommunity(id: String) async throws -> ArkCommunity? {
        let doc = try await db.collection("arkCommunities").document(id).getDocument()
        return try? doc.data(as: ArkCommunity.self)
    }

    /// Creates a new Ark community. Returns the new document ID.
    func createCommunity(_ community: ArkCommunity) async throws -> String {
        let ref = try db.collection("arkCommunities").addDocument(from: community)
        return ref.documentID
    }

    // MARK: - Members

    /// Fetches membership record for a user in a community.
    func fetchMember(userId: String, communityId: String) async throws -> ArkMember? {
        let doc = try await db.collection("arkCommunities")
            .document(communityId)
            .collection("members")
            .document(userId)
            .getDocument()
        return try? doc.data(as: ArkMember.self)
    }

    /// Writes a new member record (called after covenant signing).
    func joinCommunity(member: ArkMember, communityId: String) async throws {
        guard let userId = member.userId.isEmpty ? nil : member.userId else { return }
        // SECURITY NOTE: memberCount increment is handled server-side in a Cloud Function
        // triggered on arkCommunities/{id}/members write to avoid client-side races.
        try db.collection("arkCommunities")
            .document(communityId)
            .collection("members")
            .document(userId)
            .setData(from: member)
    }

    // MARK: - Posts

    /// Fetches posts in a community, newest first, pending AI moderation check.
    func fetchPosts(communityId: String, limit: Int = 30) async throws -> [ArkPost] {
        let snap = try await db.collection("arkCommunities")
            .document(communityId)
            .collection("posts")
            .whereField("aiModerationStatus", isEqualTo: "approved")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ArkPost.self) }
    }

    /// Submits a new post with pending_review status.
    /// The AI moderation call happens immediately before Firestore write.
    func submitPost(_ post: ArkPost, community: ArkCommunity) async throws {
        guard !post.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let communityId = community.id else { return }

        // Run moderation before saving
        let moderation = await moderatePost(post, community: community)
        var finalPost = post
        finalPost = ArkPost(
            id: post.id,
            userId: post.userId,
            content: post.content,
            createdAt: post.createdAt,
            aiModerationStatus: moderation?.status ?? "pending_review",
            aiModerationReason: moderation?.reason,
            aiCovenantViolations: moderation?.violations.isEmpty == false ? moderation?.violations : nil,
            communityReports: post.communityReports,
            isAnonymous: post.isAnonymous
        )

        try db.collection("arkCommunities")
            .document(communityId)
            .collection("posts")
            .addDocument(from: finalPost)
    }

    // MARK: - AI: Covenant Moderation

    /// Contextual post moderation using Claude. Returns nil if AI is unavailable;
    /// callers should default to "pending_review" status in that case.
    // COST NOTE: one call per post submission. Consider batching for high-volume communities.
    func moderatePost(_ post: ArkPost, community: ArkCommunity) async -> ModerationResult? {
        let system = """
        You are a wise, grace-filled community moderator for a faith-based space.
        You are embedded in AMEN, a faith-centered community platform.
        You approach moderation with dignity, charity, and care.
        Assume good faith unless clearly otherwise.
        Consider tone, intent, and covenant context — not just surface keywords.
        Never shame. Speak truth with grace. Frame warnings in restoration, not condemnation.
        """

        let principlesList = community.covenantPrinciples
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let user = """
        COMMUNITY COVENANT PRINCIPLES:
        \(principlesList)

        POST TO REVIEW:
        "\(post.content)"

        Review this post against the community covenant.
        Respond ONLY in valid JSON:
        {
          "status": "approved",
          "violations": [],
          "reason": "",
          "suggestedEdit": null,
          "graceNote": ""
        }

        status must be one of: "approved", "flagged", "removed"
        violations: list of covenant principle names broken (empty array if approved)
        reason: brief explanation
        suggestedEdit: optional improved version of the post, or null
        graceNote: if flagged/removed, a kind message to the author framed in restoration
        """

        guard let result = try? await functions.httpsCallable("bereanChatProxy")
            .call(["systemPrompt": system, "userMessage": user, "maxTokens": 400]),
              let dict = result.data as? [String: Any],
              let text = dict["text"] as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return ModerationResult(
            status: json["status"] as? String ?? "pending_review",
            violations: json["violations"] as? [String] ?? [],
            reason: json["reason"] as? String ?? "",
            suggestedEdit: json["suggestedEdit"] as? String,
            graceNote: json["graceNote"] as? String ?? ""
        )
    }

    // MARK: - Ark Score

    /// Applies a scored event delta to the member's Ark Score in Firestore.
    func updateArkScore(userId: String, communityId: String, event: ArkScoreEvent) async throws {
        let memberRef = db.collection("arkCommunities")
            .document(communityId)
            .collection("members")
            .document(userId)

        let doc = try await memberRef.getDocument()
        guard var member = try? doc.data(as: ArkMember.self) else { return }

        var breakdown = member.arkScoreBreakdown
        let delta = event.delta

        // Apply delta to the affected dimension, clamped 0–100
        switch event.dimension {
        case .truthfulness:
            breakdown.truthfulness = clamp(breakdown.truthfulness + delta)
        case .encouragement:
            breakdown.encouragement = clamp(breakdown.encouragement + delta)
        case .conflictGrace:
            breakdown.conflictGrace = clamp(breakdown.conflictGrace + delta)
        case .consistency:
            breakdown.consistency = clamp(breakdown.consistency + delta)
        case .testimonySharing:
            breakdown.testimonySharing = clamp(breakdown.testimonySharing + delta)
        case .prayerSupport:
            breakdown.prayerSupport = clamp(breakdown.prayerSupport + delta)
        }

        // Recompute composite Ark Score as equal-weighted average
        let composite = (
            breakdown.truthfulness +
            breakdown.encouragement +
            breakdown.conflictGrace +
            breakdown.consistency +
            breakdown.testimonySharing +
            breakdown.prayerSupport
        ) / 6.0

        try await memberRef.updateData([
            "arkScore": composite,
            "arkScoreBreakdown.truthfulness":    breakdown.truthfulness,
            "arkScoreBreakdown.encouragement":   breakdown.encouragement,
            "arkScoreBreakdown.conflictGrace":   breakdown.conflictGrace,
            "arkScoreBreakdown.consistency":     breakdown.consistency,
            "arkScoreBreakdown.testimonySharing": breakdown.testimonySharing,
            "arkScoreBreakdown.prayerSupport":   breakdown.prayerSupport
        ])
    }

    private func clamp(_ value: Double, min: Double = 0, max: Double = 100) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}
