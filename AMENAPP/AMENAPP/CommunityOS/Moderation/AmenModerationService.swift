// AmenModerationService.swift
// AMENAPP — CommunityOS/Moderation
//
// Phase 4 Agent TS-d — Moderation & Governance
//
// Moderation queue service. Handles reporting, queue loading, action-taking,
// appeals, and community health signals.
//
// Architecture:
//   - iOS submits reports via reportContent(). CF handles routing, counting, and assignment.
//   - Moderators load the queue via loadModQueue() — requires moderator role (Firestore rules).
//   - takeAction() soft-deletes content + writes audit log via AmenAuditLogService.
//   - All hard deletes are DENIED at the Firestore rules layer (Invariant I-1).
//   - Reporter identity is stored server-side but NEVER shown to content authors.
//   - Community health signals contain no individual attribution.
//
// AUDIT LOG: All moderation actions are written to /auditLog via AmenAuditLogService.
//   The audit log is append-only (Invariant I-2). Log writes use try? — they must never
//   interrupt the moderation action if the write fails.
//
// ROLE ENFORCEMENT: loadModQueue() and takeAction() require Moderator+ role.
//   This is enforced at the Firestore rules layer. iOS pre-checks via AmenRBACService
//   as defense-in-depth but the server rule is authoritative.
//
// C5 §2o, Invariant I-1, I-2
// Phase 4 Agent TS-d

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenModerationService

@MainActor
final class AmenModerationService: ObservableObject {

    // MARK: - Published State

    /// The current page of moderation queue items loaded for the active context.
    @Published var queueItems: [ModerationQueueItem] = []

    /// Pending appeals for the active context.
    @Published var appeals: [AmenModerationAppeal] = []

    /// Whether a load operation is in progress.
    @Published var isLoading: Bool = false

    /// Error message if the last load or action failed.
    @Published var errorMessage: String?

    // MARK: - Private

    private let db = Firestore.firestore()
    private let auditLog = AmenAuditLogService.shared

    // MARK: - Init

    init() {}

    // =========================================================================
    // MARK: - Report Content
    // =========================================================================

    /// Submits a content report to /moderationQueue.
    ///
    /// PRIVACY: The reporter ID is stored in Firestore but Firestore rules ensure
    ///   that only Moderator+ can read it. Content authors never see who reported them.
    ///
    /// QUEUE ROUTING: A CF onDocumentCreated trigger on /moderationQueue picks up the
    ///   report, determines the risk tier (calling checkContentSafety if needed),
    ///   routes it to the appropriate moderator pool, and updates counters.
    ///
    /// iOS only writes the initial report. CF handles all downstream routing.
    ///
    /// - Parameters:
    ///   - contentRef:   Firestore path of the reported content (e.g. "posts/abc123")
    ///   - contentType:  Surface type: "post" | "comment" | "prayer" | "message"
    ///   - reason:       User-supplied report reason
    ///   - reporterId:   UID of the user submitting the report
    ///
    /// - Throws: Firestore write errors.
    func reportContent(
        contentRef: String,
        contentType: String,
        reason: String,
        reporterId: String
    ) async throws {
        let reportData: [String: Any] = [
            "contentRef": contentRef,
            "contentType": contentType,
            "reportReason": reason,
            "reportedBy": reporterId,   // Stored server-side; never shown to content author
            "riskTier": "pending",      // CF will update this after AI scan
            "escalateImmediately": false,
            "status": ModerationItemStatus.pending.rawValue,
            "isAppealable": true,
            "createdAt": FieldValue.serverTimestamp()
        ]

        try await db.collection("moderationQueue").addDocument(data: reportData)
        dlog("[AmenModerationService] Report submitted. contentRef=\(contentRef), contentType=\(contentType)")
    }

    // =========================================================================
    // MARK: - Load Queue
    // =========================================================================

    /// Loads the moderation queue for the given context.
    ///
    /// ROLE ENFORCEMENT: This query is protected by Firestore rules — only Moderator+
    ///   roles within the context may read /moderationQueue documents. If the caller
    ///   lacks the required role, Firestore returns a permission-denied error.
    ///
    /// iOS pre-checks via AmenRBACService as defense-in-depth, but the Firestore
    ///   rule is authoritative (C5 §2o).
    ///
    /// - Parameters:
    ///   - contextType:   "church" | "space" | "org"
    ///   - contextId:     Firestore ID of the context
    ///   - moderatorId:   UID of the requesting moderator (for RBAC pre-check only)
    ///
    /// - Throws: Firestore read errors including permission-denied for insufficient role.
    func loadModQueue(
        contextType: String,
        contextId: String,
        moderatorId: String
    ) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // RBAC pre-check: verify the caller has at least Moderator role in this context.
        let role = try await AmenRBACService.shared.resolveRole(
            for: moderatorId,
            in: contextType,
            contextId: contextId
        )

        let result = AmenRBACService.shared.check(
            role: role,
            resource: .moderationQueue,
            action: .read
        )

        guard result.allowed else {
            throw NSError(
                domain: "AmenModeration",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: result.reason]
            )
        }

        // Load pending + escalated items for this context.
        let snap = try await db.collection("moderationQueue")
            .whereField("contextType", isEqualTo: contextType)
            .whereField("contextId", isEqualTo: contextId)
            .whereField("status", in: [
                ModerationItemStatus.pending.rawValue,
                ModerationItemStatus.escalated.rawValue,
                ModerationItemStatus.appealed.rawValue
            ])
            .order(by: "createdAt", descending: false)
            .limit(to: 50)
            .getDocuments()

        queueItems = snap.documents.compactMap { parseQueueItem(from: $0) }

        // Also load pending appeals.
        let appealSnap = try await db.collection("moderationAppeals")
            .whereField("contextType", isEqualTo: contextType)
            .whereField("contextId", isEqualTo: contextId)
            .whereField("status", isEqualTo: AppealStatus.pending.rawValue)
            .order(by: "createdAt", descending: false)
            .limit(to: 25)
            .getDocuments()

        appeals = appealSnap.documents.compactMap { parseAppeal(from: $0) }
    }

    // =========================================================================
    // MARK: - Take Action
    // =========================================================================

    /// Takes a moderation action on a queue item.
    ///
    /// Steps:
    ///   1. Updates the queue item's status and records the action.
    ///   2. If action is .remove, soft-deletes the content (sets isDeleted: true).
    ///      Hard deletes are NEVER performed — Invariant I-1.
    ///   3. If action is .ban, suspends the author's account (sets suspended: true).
    ///   4. Writes an audit log entry via AmenAuditLogService (Invariant I-2).
    ///
    /// AUDIT LOG: Written using AmenAuditLogService.log() which is best-effort (try?).
    ///   A write failure must not prevent the moderation action from completing.
    ///
    /// - Parameters:
    ///   - itemId:       Firestore document ID of the ModerationQueueItem
    ///   - action:       The ModerationActionType to apply
    ///   - note:         Moderator's explanation (required; must be non-empty)
    ///   - moderatorId:  UID of the moderator taking action
    ///
    /// - Throws: Firestore errors or validation errors.
    func takeAction(
        itemId: String,
        action: ModerationActionType,
        note: String,
        moderatorId: String
    ) async throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        guard !trimmedNote.isEmpty else {
            throw NSError(
                domain: "AmenModeration",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "A moderator note is required."]
            )
        }

        // Retrieve the current queue item to get the contentRef.
        let itemDoc = try await db.collection("moderationQueue").document(itemId).getDocument()
        guard let data = itemDoc.data() else {
            throw NSError(
                domain: "AmenModeration",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Queue item not found."]
            )
        }

        let contentRef = data["contentRef"] as? String ?? ""
        let authorId = data["authorId"] as? String

        // Determine new status based on action.
        let newStatus: ModerationItemStatus = {
            switch action {
            case .escalate:      return .escalated
            case .appealGranted, .appealDenied: return .resolved
            default:             return .reviewed
            }
        }()

        // Step 1: Update the moderation queue item.
        var queueUpdate: [String: Any] = [
            "status": newStatus.rawValue,
            "actionTaken": action.rawValue,
            "actionNote": trimmedNote,
            "assignedModerator": moderatorId,
            "resolvedAt": FieldValue.serverTimestamp()
        ]
        if action == .escalate {
            queueUpdate["escalatedAt"] = FieldValue.serverTimestamp()
            queueUpdate["escalatedBy"] = moderatorId
        }
        try await db.collection("moderationQueue").document(itemId).updateData(queueUpdate)

        // Step 2: Soft-delete content if action is .remove (Invariant I-1 — NO hard deletes).
        // SECURITY FIX (HIGH 2026-06-11): Replace try? with throwing try. The outer function
        // already throws; callers wrapped in try? at the UI layer. Making the write throw
        // gives the caller a real failure signal so the moderator knows the remove failed.
        if action == .remove, !contentRef.isEmpty {
            let pathComponents = contentRef.split(separator: "/").map(String.init)
            if pathComponents.count == 2 {
                let collection = pathComponents[0]
                let documentId = pathComponents[1]
                try await db.collection(collection).document(documentId).updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "deletionReason": "moderation_action",
                    "deletedBy": moderatorId
                ])
            }
        }

        // Step 3: Suspend account if action is .ban.
        // SECURITY FIX (HIGH 2026-06-11): Replace try? with throwing try. A silent failure
        // leaves a banned user fully active.
        if action == .ban, let uid = authorId {
            try await db.collection("users").document(uid).updateData([
                "suspended": true,
                "suspendedAt": FieldValue.serverTimestamp(),
                "suspendedBy": moderatorId,
                "suspensionReason": trimmedNote
            ])
        }

        // Step 4: Restore content if action is .restore or .appealGranted.
        if (action == .restore || action == .appealGranted), !contentRef.isEmpty {
            let pathComponents = contentRef.split(separator: "/").map(String.init)
            if pathComponents.count == 2 {
                let collection = pathComponents[0]
                let documentId = pathComponents[1]
                // SECURITY FIX (HIGH 2026-06-11): Use `try` instead of `try?` so that a
                // failed restore write propagates an error to the caller. The outer
                // `applyModeration` function already throws — the moderator will see a real
                // failure signal and know the restore did not take effect.
                try await db.collection(collection).document(documentId).updateData([
                    "isDeleted": false,
                    "restoredAt": FieldValue.serverTimestamp(),
                    "restoredBy": moderatorId
                ])
            }
        }

        // Step 5: Write audit log entry (best-effort — Invariant I-2).
        // AmenAuditLogService.log() uses try? internally and never throws.
        await auditLog.log(
            event: .contentModerate,
            actorId: moderatorId,
            actorRole: AmenRole.moderator.rawValue,
            resourceType: "moderationQueue",
            resourceId: itemId,
            targetId: authorId,
            metadata: [
                "action": action.rawValue,
                "note": trimmedNote,
                "contentRef": contentRef
            ],
            outcome: .success
        )

        // Refresh local state.
        queueItems.removeAll { $0.id == itemId }

        dlog("[AmenModerationService] Action '\(action.rawValue)' taken on item \(itemId) by moderator \(moderatorId)")
    }

    // =========================================================================
    // MARK: - Appeals
    // =========================================================================

    /// Submits an appeal against a moderation action.
    ///
    /// The appellant must be the author of the content that was actioned.
    /// Appeals are only permitted when ModerationQueueItem.isAppealable is true.
    ///
    /// - Throws: Firestore write errors or validation errors.
    func submitAppeal(
        queueItemId: String,
        reason: String,
        appellantId: String
    ) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespaces)
        guard !trimmedReason.isEmpty else {
            throw NSError(
                domain: "AmenModeration",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Please provide a reason for your appeal."]
            )
        }

        // Verify the item is appealable.
        let itemDoc = try await db.collection("moderationQueue").document(queueItemId).getDocument()
        guard let data = itemDoc.data() else {
            throw NSError(
                domain: "AmenModeration",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Moderation item not found."]
            )
        }

        let isAppealable = data["isAppealable"] as? Bool ?? false
        guard isAppealable else {
            throw NSError(
                domain: "AmenModeration",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "This decision is not appealable."]
            )
        }

        // Write the appeal.
        let appealData: [String: Any] = [
            "queueItemId": queueItemId,
            "appellantId": appellantId,
            "reason": trimmedReason,
            "status": AppealStatus.pending.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await db.collection("moderationAppeals").addDocument(data: appealData)

        // Update the queue item status to .appealed.
        try await db.collection("moderationQueue").document(queueItemId).updateData([
            "status": ModerationItemStatus.appealed.rawValue,
            "appealedAt": FieldValue.serverTimestamp()
        ])

        // Audit log: appeal submission.
        await auditLog.log(
            event: .appealSubmit,
            actorId: appellantId,
            actorRole: AmenRole.member.rawValue,
            resourceType: "moderationQueue",
            resourceId: queueItemId,
            metadata: ["reason": trimmedReason],
            outcome: .success
        )

        dlog("[AmenModerationService] Appeal submitted for item \(queueItemId) by \(appellantId)")
    }

    /// Reviews a pending appeal and grants or denies it.
    ///
    /// - Parameters:
    ///   - appealId:   Firestore document ID of the AmenModerationAppeal
    ///   - status:     The decision: .granted or .denied
    ///   - note:       Reviewer's explanation (required)
    ///   - reviewerId: UID of the reviewer (must be Moderator+ or Owner)
    ///
    /// - Throws: Firestore errors or validation errors.
    func reviewAppeal(
        appealId: String,
        status: AppealStatus,
        note: String,
        reviewerId: String
    ) async throws {
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        guard !trimmedNote.isEmpty else {
            throw NSError(
                domain: "AmenModeration",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "A review note is required."]
            )
        }
        guard status != .pending else {
            throw NSError(
                domain: "AmenModeration",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Appeal decision must be granted or denied."]
            )
        }

        // Retrieve the appeal to get the queue item ID.
        let appealDoc = try await db.collection("moderationAppeals").document(appealId).getDocument()
        guard let appealData = appealDoc.data() else {
            throw NSError(
                domain: "AmenModeration",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Appeal not found."]
            )
        }

        let queueItemId = appealData["queueItemId"] as? String ?? ""
        let appellantId = appealData["appellantId"] as? String ?? ""

        // Update the appeal record.
        try await db.collection("moderationAppeals").document(appealId).updateData([
            "status": status.rawValue,
            "reviewNote": trimmedNote,
            "reviewedBy": reviewerId,
            "reviewedAt": FieldValue.serverTimestamp()
        ])

        // Map appeal outcome to a ModerationActionType for the queue item update.
        let actionType: ModerationActionType = status == .granted ? .appealGranted : .appealDenied

        // Re-use takeAction for queue item update + content restoration + audit log.
        if !queueItemId.isEmpty {
            try await takeAction(
                itemId: queueItemId,
                action: actionType,
                note: trimmedNote,
                moderatorId: reviewerId
            )
        }

        // Audit log: appeal resolution.
        await auditLog.log(
            event: .appealResolve,
            actorId: reviewerId,
            actorRole: AmenRole.moderator.rawValue,
            resourceType: "moderationAppeals",
            resourceId: appealId,
            targetId: appellantId,
            metadata: [
                "decision": status.rawValue,
                "note": trimmedNote
            ],
            outcome: status == .granted ? .success : .denied
        )

        // Remove from local appeals list.
        appeals.removeAll { $0.id == appealId }

        dlog("[AmenModerationService] Appeal \(appealId) \(status.rawValue) by \(reviewerId)")
    }

    // =========================================================================
    // MARK: - Community Health
    // =========================================================================

    /// Returns a privacy-preserving community health signal for the given context.
    ///
    /// PRIVACY: No individual user attribution — counts only.
    /// Readable by Owner, Pastor, ExecutiveAdmin for the context (Firestore rules).
    ///
    /// - Parameters:
    ///   - contextType: "church" | "space" | "org"
    ///   - contextId:   Firestore ID of the context
    ///
    /// - Returns: A CommunityHealthSignal for the last 30 days.
    /// - Throws: Firestore read errors.
    func getCommunityHealth(
        contextType: String,
        contextId: String
    ) async throws -> CommunityHealthSignal {
        let doc = try await db
            .collection("communityHealth")
            .document(contextType)
            .collection(contextId)
            .document("30d")
            .getDocument()

        if let data = doc.data() {
            return CommunityHealthSignal(
                contextType:            data["contextType"]            as? String ?? contextType,
                contextId:              data["contextId"]              as? String ?? contextId,
                period:                 data["period"]                 as? String ?? "30d",
                reportCount:            data["reportCount"]            as? Int    ?? 0,
                resolvedCount:          data["resolvedCount"]          as? Int    ?? 0,
                appealGrantedCount:     data["appealGrantedCount"]     as? Int    ?? 0,
                averageResolutionHours: data["averageResolutionHours"] as? Double ?? 0,
                generatedAt:            (data["generatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }

        // Return a zero-state signal if no data exists yet for this context.
        return CommunityHealthSignal(
            contextType: contextType,
            contextId: contextId,
            period: "30d",
            reportCount: 0,
            resolvedCount: 0,
            appealGrantedCount: 0,
            averageResolutionHours: 0,
            generatedAt: Date()
        )
    }

    // =========================================================================
    // MARK: - Private Parsing Helpers
    // =========================================================================

    private func parseQueueItem(from doc: QueryDocumentSnapshot) -> ModerationQueueItem? {
        let data = doc.data()
        guard
            let contentRef  = data["contentRef"]  as? String,
            let contentType = data["contentType"] as? String,
            let reportReason = data["reportReason"] as? String,
            let statusRaw   = data["status"]      as? String,
            let status      = ModerationItemStatus(rawValue: statusRaw),
            let createdAt   = (data["createdAt"]  as? Timestamp)?.dateValue()
        else { return nil }

        return ModerationQueueItem(
            id:                  doc.documentID,
            contentRef:          contentRef,
            contentType:         contentType,
            reportedBy:          data["reportedBy"]        as? String,
            reportReason:        reportReason,
            riskTier:            data["riskTier"]          as? String ?? "pending",
            escalateImmediately: data["escalateImmediately"] as? Bool ?? false,
            status:              status,
            assignedModerator:   data["assignedModerator"] as? String,
            moderatorNote:       data["moderatorNote"]     as? String,
            actionTaken:         ModerationActionType(rawValue: data["actionTaken"] as? String ?? ""),
            actionNote:          data["actionNote"]        as? String,
            createdAt:           createdAt,
            resolvedAt:          (data["resolvedAt"]       as? Timestamp)?.dateValue(),
            isAppealable:        data["isAppealable"]      as? Bool ?? true
        )
    }

    private func parseAppeal(from doc: QueryDocumentSnapshot) -> AmenModerationAppeal? {
        let data = doc.data()
        guard
            let queueItemId  = data["queueItemId"]  as? String,
            let appellantId  = data["appellantId"]  as? String,
            let reason       = data["reason"]       as? String,
            let statusRaw    = data["status"]       as? String,
            let status       = AppealStatus(rawValue: statusRaw),
            let createdAt    = (data["createdAt"]   as? Timestamp)?.dateValue()
        else { return nil }

        return AmenModerationAppeal(
            id:          doc.documentID,
            queueItemId: queueItemId,
            appellantId: appellantId,
            reason:      reason,
            status:      status,
            reviewedBy:  data["reviewedBy"]  as? String,
            reviewNote:  data["reviewNote"]  as? String,
            createdAt:   createdAt,
            reviewedAt:  (data["reviewedAt"] as? Timestamp)?.dateValue()
        )
    }
}
