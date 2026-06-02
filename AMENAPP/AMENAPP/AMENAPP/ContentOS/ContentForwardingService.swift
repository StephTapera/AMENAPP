// ContentForwardingService.swift
// AMENAPP — ContentOS
//
// Firestore-backed service for approval requests, forwarding decisions,
// and the ContentOS audit log.
// Collection layout:
//   contentAuditLog/{entryId}
//   contentApprovalRequests/{requestId}

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

@MainActor
final class ContentForwardingService {
    static let shared = ContentForwardingService()
    private init() {}

    private let db        = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Audit Log

    func recordAudit(
        card: ContentCard,
        action: ContentAction,
        destination: ContentSurface?,
        isExternal: Bool,
        outcome: ContentPermissionOutcome,
        wasAnonymous: Bool
    ) {
        guard AMENFeatureFlags.shared.contentAuditLogEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let entry: [String: Any] = [
            "contentId":       card.id,
            "contentType":     card.sourceType.rawValue,
            "actorId":         uid,
            "action":          action.rawValue,
            "destination":     destination?.rawValue ?? "",
            "isExternal":      isExternal,
            "timestamp":       FieldValue.serverTimestamp(),
            "wasAnonymous":    wasAnonymous,
            "approvalOutcome": outcome.displayTitle,
            "sourceSurface":   card.sourceSurface.rawValue,
            "originalAudience": card.originalAudience.rawValue
        ]

        Task {
            try? await db.collection("contentAuditLog").addDocument(data: entry)
        }
    }

    // MARK: - Approval Requests

    func sendApprovalRequest(
        card: ContentCard,
        requestedAction: ContentAction,
        targetSurface: ContentSurface,
        note: String?
    ) async throws {
        guard AMENFeatureFlags.shared.contentApprovalWorkflowEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ContentForwardingError.notAuthenticated
        }

        let data: [String: Any] = [
            "contentId":       card.id,
            "contentType":     card.sourceType.rawValue,
            "creatorId":       card.creatorId,
            "requestorId":     uid,
            "requestedAction": requestedAction.rawValue,
            "targetSurface":   targetSurface.rawValue,
            "note":            note ?? "",
            "status":          "pending",
            "createdAt":       FieldValue.serverTimestamp(),
            "sourceTitle":     card.title,
            "sourceBody":      String(card.body.prefix(300))
        ]

        try await db.collection("contentApprovalRequests").addDocument(data: data)

        recordAudit(
            card: card,
            action: .requestPermission,
            destination: targetSurface,
            isExternal: false,
            outcome: .requiresCreatorApproval,
            wasAnonymous: card.isAnonymous
        )
    }

    // MARK: - Save to Church Notes

    func saveToChurchNotes(card: ContentCard) async throws {
        guard AMENFeatureFlags.shared.contentOSEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ContentForwardingError.notAuthenticated
        }

        let note: [String: Any] = [
            "userId":          uid,
            "sourceContentId": card.id,
            "sourceType":      card.sourceType.rawValue,
            "title":           card.title.isEmpty ? card.sourceType.displayName : card.title,
            "body":            card.body,
            "sourceSurface":   card.sourceSurface.rawValue,
            "attribution":     card.creatorDisplayName ?? "",
            "savedAt":         FieldValue.serverTimestamp(),
            "hasPrayerContent": card.hasPrayerContent
        ]

        try await db.collection("churchNotesSaved").addDocument(data: note)

        recordAudit(
            card: card,
            action: .saveToChurchNotes,
            destination: .churchNotes,
            isExternal: false,
            outcome: .allowedInstantly,
            wasAnonymous: false
        )
    }

    // MARK: - Forward Decision Record

    func recordForwardDecision(
        card: ContentCard,
        action: ContentAction,
        destination: ContentSurface,
        outcome: ContentPermissionOutcome,
        isExternal: Bool
    ) {
        recordAudit(
            card: card,
            action: action,
            destination: destination,
            isExternal: isExternal,
            outcome: outcome,
            wasAnonymous: card.isAnonymous
        )
    }

    // MARK: - Errors

    enum ContentForwardingError: LocalizedError {
        case notAuthenticated
        case featureDisabled

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Sign in to share content."
            case .featureDisabled:  return "Content sharing is not available right now."
            }
        }
    }
}
