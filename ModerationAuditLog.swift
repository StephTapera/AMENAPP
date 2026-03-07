
//
//  ModerationAuditLog.swift
//  AMENAPP
//
//  Immutable audit trail for all moderation decisions across every surface.
//
//  Collection: moderationAuditLogs/{auditId}
//  - Never deleted, never updated (append-only)
//  - Firestore rules must deny delete + update for all clients
//  - Written by app; reconciled by Cloud Functions on severe actions
//
//  Schema matches ModerationResult used by ModerationGateway.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Audit Log Entry

/// Immutable record of one moderation decision.
/// Written to Firestore before any enforcement action takes place.
struct ModerationAuditEntry: Codable {
    /// Auto-generated Firestore document ID — also used as idempotency key
    let auditId: String
    /// Which surface triggered the check
    let surface: Surface
    /// The user whose content was checked
    let userId: String
    /// Optional: target user (recipient in DMs, author for comment moderation)
    let targetUserId: String?
    /// Firestore doc path of the content (posts/{id}, conversations/{id}/messages/{id}, etc.)
    let contentPath: String?
    /// The content that was evaluated (truncated to 500 chars)
    let contentPreview: String
    /// Final decision
    let action: Action
    /// Detected categories
    let categories: [String]
    /// Score 0.0–1.0
    let severity: Double
    /// Score 0.0–1.0
    let confidence: Double
    /// Which AI provider made the call (e.g., "vertex", "openai", "client_heuristic")
    let provider: String
    /// Model/version string (e.g., "text-bison-002", "gpt-4o", "berean-heuristic-v1")
    let modelVersion: String
    /// ISO-8601 timestamp
    let createdAt: Timestamp
    /// Whether evidence was preserved (for severe cases)
    let evidencePreserved: Bool
    /// Optional: Idempotency key from the caller (clientMessageId, postTempId, etc.)
    let idempotencyKey: String?

    enum Surface: String, Codable {
        case post          = "post"
        case comment       = "comment"
        case dmText        = "dm_text"
        case dmMedia       = "dm_media"
        case profileField  = "profile_field"
        case bereanQuery   = "berean_query"
        case media         = "media"
        case notification  = "notification"
    }

    enum Action: String, Codable {
        case allow          = "allow"
        case warnUser       = "warn_user"
        case warnRecipient  = "warn_recipient"
        case holdForReview  = "hold_for_review"
        case blockContent   = "block_content"
        case strikeAccount  = "strike_account"
        case freezeAccount  = "freeze_account"
    }
}

// MARK: - Audit Log Service

/// Thread-safe singleton that writes immutable audit records to Firestore.
/// All writes are fire-and-forget — they must not block the content flow.
@MainActor
final class ModerationAuditLogService {
    static let shared = ModerationAuditLogService()

    private let collection = Firestore.firestore().collection("moderationAuditLogs")
    private init() {}

    // MARK: - Write

    /// Record a moderation decision. Fire-and-forget; failures are logged but not re-thrown.
    func record(
        surface: ModerationAuditEntry.Surface,
        userId: String,
        targetUserId: String? = nil,
        contentPath: String? = nil,
        contentPreview: String,
        action: ModerationAuditEntry.Action,
        categories: [String] = [],
        severity: Double = 0,
        confidence: Double = 0,
        provider: String = "client_heuristic",
        modelVersion: String = "berean-heuristic-v1",
        evidencePreserved: Bool = false,
        idempotencyKey: String? = nil
    ) {
        let auditId = idempotencyKey ?? UUID().uuidString
        let entry = ModerationAuditEntry(
            auditId: auditId,
            surface: surface,
            userId: userId,
            targetUserId: targetUserId,
            contentPath: contentPath,
            contentPreview: String(contentPreview.prefix(500)),
            action: action,
            categories: categories,
            severity: min(1, max(0, severity)),
            confidence: min(1, max(0, confidence)),
            provider: provider,
            modelVersion: modelVersion,
            createdAt: Timestamp(date: Date()),
            evidencePreserved: evidencePreserved,
            idempotencyKey: idempotencyKey
        )

        // Encode on MainActor (where Encodable conformance is isolated), then write off-actor.
        guard let entryData = try? Firestore.Encoder().encode(entry) else { return }
        Task.detached(priority: .utility) { [collection, entryData, auditId, surface, action] in
            do {
                // Idempotent: use auditId as document ID so duplicate decisions don't create
                // duplicate records (safe for retry).
                try await collection.document(auditId).setData(entryData, merge: false)
                print("📋 [Audit] \(surface.rawValue) → \(action.rawValue) recorded (\(auditId))")
            } catch {
                // Audit failure must not block content — log and continue.
                print("⚠️ [Audit] Failed to write audit log: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Convenience wrappers

    func recordDMTextDecision(
        senderId: String,
        recipientId: String,
        conversationId: String,
        messageId: String,
        text: String,
        decision: GatewayDecision
    ) {
        let (action, categories, severity, confidence) = gatewayDecisionComponents(decision)
        record(
            surface: .dmText,
            userId: senderId,
            targetUserId: recipientId,
            contentPath: "conversations/\(conversationId)/messages/\(messageId)",
            contentPreview: text,
            action: action,
            categories: categories,
            severity: severity,
            confidence: confidence,
            provider: "client_heuristic",
            modelVersion: "MessageSafetyGateway-v1",
            evidencePreserved: severity >= 0.8,
            idempotencyKey: messageId
        )
    }

    func recordPostDecision(
        userId: String,
        postId: String,
        content: String,
        decision: ModerationDecision
    ) {
        let action: ModerationAuditEntry.Action
        switch decision.action {
        case .allow:             action = .allow
        case .nudgeRewrite:      action = .warnUser
        case .requireRevision:   action = .warnUser
        case .holdForReview:     action = .holdForReview
        case .rateLimit:         action = .blockContent
        case .shadowRestrict:    action = .blockContent
        case .reject:            action = .blockContent
        }
        record(
            surface: .post,
            userId: userId,
            contentPath: "posts/\(postId)",
            contentPreview: content,
            action: action,
            categories: decision.reasons,
            severity: decision.scores.toxicity,
            confidence: decision.confidence,
            provider: "firebase_functions",
            modelVersion: "moderateContent-v1",
            idempotencyKey: postId
        )
    }

    // MARK: - Helpers

    private func gatewayDecisionComponents(_ decision: GatewayDecision)
        -> (ModerationAuditEntry.Action, [String], Double, Double)
    {
        switch decision {
        case .allow:
            return (.allow, [], 0, 1)
        case .warnRecipient(let signals, let score):
            return (.warnRecipient, signals.map(\.rawValue), score, 0.7)
        case .holdForReview(let signals, let score):
            return (.holdForReview, signals.map(\.rawValue), score, 0.8)
        case .blockAndStrike(let signals, let score, _):
            return (.strikeAccount, signals.map(\.rawValue), score, 0.9)
        case .freezeAccount(let signals, let score, _):
            return (.freezeAccount, signals.map(\.rawValue), score, 1.0)
        }
    }
}
