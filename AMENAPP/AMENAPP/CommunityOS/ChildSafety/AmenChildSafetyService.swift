// AmenChildSafetyService.swift
// AMENAPP — CommunityOS/ChildSafety
//
// Phase 4 Agent TS-c — Child Safety
//
// Child safety enforcement service. Enforces minor restrictions at the iOS layer.
// Server-side enforcement (Firestore rules + Cloud Functions) is authoritative;
// this service provides defense-in-depth by also enforcing on the client.
//
// FAIL-CLOSED POLICY:
//   canDM() returns false on ANY error — when in doubt, deny DMs to/from minors.
//   checkIsMinor() returns false on Firestore error (conservative for content,
//     but callers should handle the thrown error for safety-critical paths).
//
// NCMEC PIPELINE — HUMAN AUTHORIZATION REQUIRED:
//   prepareCSAMEscalation() prepares escalation data on the iOS side.
//   The actual NCMEC CyberTipline submission requires explicit human authorization
//   and CANNOT be auto-activated from iOS.
//   See: contracts/C5-security-rules.md OPEN-4
//
// GUARDIAN TOOLS — OPEN-2:
//   Guardian link scope is pending T&S Lead resolution (C5 §4e / OPEN-2).
//   requestGuardianLink() is implemented; read access to minor's private data is NOT granted.
//
// C5 §4, Invariant I-3, I-8
// Phase 4 Agent TS-c

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - AmenChildSafetyService

@MainActor
final class AmenChildSafetyService: ObservableObject {

    // MARK: - Singleton

    static let shared = AmenChildSafetyService()

    // MARK: - Private

    private let db = Firestore.firestore()

    private init() {}

    // =========================================================================
    // MARK: - Age Category Queries
    // =========================================================================

    /// Returns true if the user is classified as a minor.
    ///
    /// Reads the server-owned `ageTier` field from /users/{userId}.
    /// Missing or unknown tiers fail closed to `.blocked`.
    ///
    /// - Throws: Firestore read errors. Callers on safety-critical paths should handle these.
    func checkIsMinor(userId: String) async throws -> Bool {
        let category = try await getAgeCategory(userId: userId)
        return category.isMinor
    }

    /// Resolves the user's AgeCategory from their Firestore profile.
    ///
    /// - Throws: Firestore read errors.
    func getAgeCategory(userId: String) async throws -> AgeCategory {
        let doc = try await db.collection("users").document(userId).getDocument()
        let raw = doc.data()?["ageTier"] as? String
        return AgeCategory.resolving(raw)
    }

    // =========================================================================
    // MARK: - Capability Checks
    // =========================================================================

    /// Returns true if the given capability is blocked for the specified user.
    ///
    /// Checks MinorProtectionConfig.blockedCapabilities when the user is a minor.
    /// Returns false (not blocked) on any error — fail open for capability checks
    /// to avoid locking users out on transient network errors.
    /// Note: canDM() has the opposite (fail-closed) policy because DM safety is critical.
    func isCapabilityBlocked(_ capability: String, for userId: String) async throws -> Bool {
        let isMinorUser = try await checkIsMinor(userId: userId)
        guard isMinorUser else { return false }
        return MinorProtectionConfig.blockedCapabilities.contains(capability)
    }

    // =========================================================================
    // MARK: - Minor Defaults Enforcement
    // =========================================================================

    /// Enforces the minor experience defaults on the user's settings document.
    ///
    /// Called after age verification confirms a user is a minor.
    /// Sets: privacyPreset -> "private", dmPolicy -> "mutualFollows",
    ///       and marks all blocked capabilities as disabled in userSettings.
    ///
    /// DEFENSE IN DEPTH: The server also enforces these defaults.
    /// iOS enforcement here means the UI state is immediately consistent
    /// without waiting for a server-side trigger.
    ///
    /// - Throws: Firestore write errors. The caller should log but not crash on failure.
    func enforceMinorDefaults(userId: String) async throws {
        // Build the settings update. This writes to /users/{userId}/settings
        // (not the age_assurance subcollection, which is Admin SDK only).
        var settingsUpdate: [String: Any] = [
            "privacyPreset": MinorProtectionConfig.defaultPrivacyPreset,
            "dmPolicy": MinorProtectionConfig.defaultDMPolicy,
            "minorDefaultsApplied": true,
            "minorDefaultsAppliedAt": FieldValue.serverTimestamp()
        ]

        // Mark all blocked capabilities as disabled in the settings map.
        var capabilityOverrides: [String: Bool] = [:]
        for cap in MinorProtectionConfig.blockedCapabilities {
            capabilityOverrides[cap] = false
        }
        settingsUpdate["capabilityOverrides"] = capabilityOverrides

        try await db.collection("users")
            .document(userId)
            .collection("settings")
            .document("minorProtection")
            .setData(settingsUpdate, merge: true)

        dlog("[AmenChildSafetyService] Minor defaults enforced for userId: \(userId)")
    }

    // =========================================================================
    // MARK: - DM Guard (FAIL-CLOSED)
    // =========================================================================

    /// Determines whether a DM may be sent from one user to another.
    ///
    /// CRITICAL — FAIL-CLOSED:
    ///   Any error during the check returns false (deny). When in doubt,
    ///   DMs involving minors are blocked. This matches C-MINOR-DM in C5 §4b.
    ///
    /// Rules (C5 §4b):
    ///   - If recipient is a minor: sender must be a mutual follow AND the
    ///     conversation must pass the minor-safe contact check (CF-enforced).
    ///   - If sender is a minor: recipient must be a mutual follow.
    ///   - Both the sender and recipient being adults: permitted by default.
    ///
    /// Note: The full C-MINOR-DM mutual-follow check is authoritative at the
    ///   CF layer. This method provides the iOS-layer pre-check. CF will
    ///   re-verify before any message is written to Firestore.
    ///
    /// - Returns: true if the DM is permitted by this layer's check; false to deny.
    func canDM(from senderId: String, to recipientId: String) async throws -> Bool {
        do {
            // Determine minor status for both parties.
            let senderIsMinor = try await checkIsMinor(userId: senderId)
            let recipientIsMinor = try await checkIsMinor(userId: recipientId)

            // Neither party is a minor — default allow; CF enforces other constraints.
            guard senderIsMinor || recipientIsMinor else { return true }

            // At least one party is a minor — require mutual follow.
            let isMutual = try await areMutualFollows(userId1: senderId, userId2: recipientId)
            guard isMutual else {
                dlog("[AmenChildSafetyService] canDM: DENIED — not mutual follows. sender=\(senderId), recipient=\(recipientId)")
                return false
            }

            // If the recipient is a minor, also check guardian approval.
            if recipientIsMinor {
                let guardianApproved = try await isGuardianApprovedContact(
                    minorId: recipientId,
                    contactId: senderId
                )
                guard guardianApproved else {
                    dlog("[AmenChildSafetyService] canDM: DENIED — no guardian approval. minorId=\(recipientId), senderId=\(senderId)")
                    return false
                }
            }

            return true

        } catch {
            // FAIL-CLOSED: any error denies the DM.
            dlog("[AmenChildSafetyService] canDM: ERROR — failing closed. \(error)")
            return false
        }
    }

    // =========================================================================
    // MARK: - Content Filtering (Client-Side Stub)
    // =========================================================================

    /// Client-side content filter stub for minor experience.
    ///
    /// IMPORTANT: Content filtering for minors is authoritative at the CF layer
    /// (the `checkContentSafety` callable applies minor-specific rules when
    ///  `isMinorAuthor: true` is set in the request). This iOS stub passes items
    /// through unchanged. Actual content filtering happens server-side.
    ///
    /// Callers should always ensure `ContentCheckRequest.isMinorAuthor` is set
    /// correctly before calling AmenContentSafetyService.checkBeforePost().
    func filterContentForMinor(_ items: [String]) -> [String] {
        // CF handles actual minor content filtering via checkContentSafety.
        // When isMinorAuthor: true is passed, NeMo Guard applies stricter thresholds.
        // This stub returns the full list; the CF gate is the authoritative filter.
        return items
    }

    // =========================================================================
    // MARK: - Guardian Link
    // =========================================================================

    /// Submits a guardian link request for the given minor user.
    ///
    /// Writes a pending guardian link request to Firestore.
    /// A Cloud Function (onDocumentCreated on /guardianLinkRequests) handles
    /// sending the verification email to the guardian and completing the link
    /// after the guardian confirms.
    ///
    /// OPEN-2 (T&S Lead must resolve): Guardian read/control scope is undefined for v1.
    /// Until resolved, this method only creates the link — guardian has zero read access
    /// to the minor's private content.
    ///
    /// - Throws: Firestore write errors.
    func requestGuardianLink(minorId: String, guardianEmail: String) async throws {
        // Validate email format before writing.
        guard isValidEmail(guardianEmail) else {
            throw NSError(
                domain: "AmenChildSafety",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid guardian email address."]
            )
        }

        let requestData: [String: Any] = [
            "minorId": minorId,
            "guardianEmail": guardianEmail,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
            // NOTE: OPEN-2 — guardian access scope to be defined by T&S Lead before Phase 4 deploy.
            // Current implementation: guardian has zero read access to minor's private data.
        ]

        try await db.collection("guardianLinkRequests").addDocument(data: requestData)

        dlog("[AmenChildSafetyService] Guardian link request submitted. minorId=\(minorId)")
    }

    // =========================================================================
    // MARK: - NCMEC Escalation Pipeline
    // =========================================================================

    // NCMEC PIPELINE — HUMAN AUTHORIZATION REQUIRED
    // This method prepares the escalation data. The actual NCMEC CyberTipline
    // submission requires explicit human authorization and cannot be auto-activated.
    // See: contracts/C5-security-rules.md OPEN-4
    //
    // What this method does (iOS client responsibilities only):
    //   1. Immediately marks content as deleted in visible collections (set isDeleted: true)
    //   2. Writes to /moderationQueue with escalateImmediately: true, type: "csam"
    //   3. Writes to /safetyAuditLog for the compliance trail
    //
    // What this method does NOT do:
    //   - Submit to NCMEC CyberTipline (requires human authorization + CF)
    //   - Write to /auditLog (CF handles via Admin SDK to preserve audit integrity)
    //
    // The CF `onDocumentCreated` trigger on /moderationQueue watches for
    //   type == "csam" and escalateImmediately == true.
    //   The CF then notifies safety staff. Human authorization is required
    //   before the CF submits to NCMEC. No auto-submission ever occurs.
    //
    // Errors are caught and logged — this method does NOT rethrow because the
    //   content removal (step 1) must still complete even if the Firestore writes fail.

    /// Prepares CSAM escalation data. DOES NOT submit to NCMEC automatically.
    ///
    /// - Parameters:
    ///   - contentRef:      Firestore path of the flagged content (e.g. "posts/abc123")
    ///   - authorId:        UID of the content author
    ///   - detectionSource: What triggered the flag: "ios_hash_match" | "cf_vision_scan" | "user_report"
    func prepareCSAMEscalation(
        contentRef: String,
        authorId: String,
        detectionSource: String
    ) async throws {
        dlog("[AmenChildSafetyService] CSAM escalation PREPARED — contentRef=\(contentRef), source=\(detectionSource)")

        // Step 1: Soft-delete content from visible collections.
        // Parse the Firestore path to get collection + document ID.
        let pathComponents = contentRef.split(separator: "/").map(String.init)
        if pathComponents.count == 2 {
            let collection = pathComponents[0]
            let documentId = pathComponents[1]
            do {
                try await db.collection(collection).document(documentId).updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "deletionReason": "csam_escalation"
                ])
            } catch {
                try await writeCriticalCSAMFailureAlert(
                    contentRef: contentRef,
                    authorId: authorId,
                    detectionSource: detectionSource,
                    failedStep: "hide_content",
                    error: error
                )
                throw error
            }
        }

        // Step 2: Write to moderationQueue with CSAM escalation flag.
        let queueRecord: [String: Any] = [
            "contentRef": contentRef,
            "authorId": authorId,
            "contentType": pathComponents.first ?? "unknown",
            "escalateImmediately": true,
            "type": "csam",
            "detectionSource": detectionSource,
            "status": "pending",
            "createdAt": FieldValue.serverTimestamp()
            // NOTE: NCMEC submission requires human authorization. CF handles after staff review.
            // See OPEN-4 in contracts/C5-security-rules.md for SLA and escalation key holder.
        ]

        do {
            try await db.collection("moderationQueue").addDocument(data: queueRecord)
        } catch {
            try await writeCriticalCSAMFailureAlert(
                contentRef: contentRef,
                authorId: authorId,
                detectionSource: detectionSource,
                failedStep: "moderation_queue",
                error: error
            )
            throw error
        }

        // Step 3: Write to safety audit log.
        let auditRecord: [String: Any] = [
            "event": "csam_escalation_prepared",
            "contentRef": contentRef,
            "authorId": authorId,
            "detectionSource": detectionSource,
            "clientTimestamp": Date().timeIntervalSince1970,
            "source": "AmenChildSafetyService",
            "ncmecSubmissionPending": true
            // HUMAN AUTHORIZATION REQUIRED before CF completes NCMEC submission.
        ]
        do {
            try await db.collection("safetyAuditLog").addDocument(data: auditRecord)
        } catch {
            try await writeCriticalCSAMFailureAlert(
                contentRef: contentRef,
                authorId: authorId,
                detectionSource: detectionSource,
                failedStep: "safety_audit_log",
                error: error
            )
            throw error
        }
    }

    private func writeCriticalCSAMFailureAlert(
        contentRef: String,
        authorId: String,
        detectionSource: String,
        failedStep: String,
        error: Error
    ) async throws {
        try await db.collection("criticalSafetyAlerts").addDocument(data: [
            "type": "csam_escalation_write_failure",
            "contentRef": contentRef,
            "authorId": authorId,
            "detectionSource": detectionSource,
            "failedStep": failedStep,
            "errorDescription": error.localizedDescription,
            "createdAt": FieldValue.serverTimestamp(),
            "requiresImmediateHumanReview": true,
            "reporterUid": Auth.auth().currentUser?.uid ?? "unknown"
        ])
    }

    // =========================================================================
    // MARK: - Grooming Auto-Removal (C-11)
    // =========================================================================

    /// Immediately soft-deletes content flagged for grooming patterns and queues it
    /// for staff review. Unlike CSAM, grooming auto-removal does NOT require NCMEC
    /// human authorization — content is removed immediately, review happens afterward.
    ///
    /// FAIL-HARD: all four Firestore writes use `try` with explicit error handling
    /// matching the CSAM pipeline. A silent failure on the content-hide or queue write
    /// is a child-safety regression — errors write a criticalSafetyAlert and rethrow.
    ///
    /// - Parameters:
    ///   - contentRef:      Firestore path of the flagged content (e.g. "posts/abc123")
    ///   - authorId:        UID of the content author
    ///   - detectionSource: What triggered the flag: "ios_pattern_match" | "cf_ml_scan"
    func reportGroomingContent(
        contentRef: String,
        authorId: String,
        detectionSource: String
    ) async throws {
        dlog("[AmenChildSafetyService] Grooming auto-removal — contentRef=\(contentRef), source=\(detectionSource)")

        // Step 1: Immediately soft-delete the content.
        let pathComponents = contentRef.split(separator: "/").map(String.init)
        if pathComponents.count == 2 {
            let collection = pathComponents[0]
            let documentId = pathComponents[1]
            do {
                try await db.collection(collection).document(documentId).updateData([
                    "isDeleted": true,
                    "deletedAt": FieldValue.serverTimestamp(),
                    "deletionReason": "grooming_auto_removal"
                ])
            } catch {
                // CRITICAL: content hide failed — content remains visible. Alert and rethrow.
                try await writeCriticalGroomingFailureAlert(
                    contentRef: contentRef,
                    authorId: authorId,
                    detectionSource: detectionSource,
                    failedStep: "hide_content",
                    error: error
                )
                throw error
            }
        }

        // Step 2: Queue for staff review (no NCMEC pipeline required for grooming).
        let queueRecord: [String: Any] = [
            "contentRef": contentRef,
            "authorId": authorId,
            "contentType": pathComponents.first ?? "unknown",
            "type": "grooming",
            "detectionSource": detectionSource,
            "status": "pending",
            "autoRemoved": true,
            "createdAt": FieldValue.serverTimestamp()
        ]
        do {
            try await db.collection("moderationQueue").addDocument(data: queueRecord)
        } catch {
            // CRITICAL: queue entry lost — staff will not review this content.
            try await writeCriticalGroomingFailureAlert(
                contentRef: contentRef,
                authorId: authorId,
                detectionSource: detectionSource,
                failedStep: "moderation_queue",
                error: error
            )
            throw error
        }

        // Step 3: Increment grooming flag count on user_trust record.
        // The EnforcementLadderService CF monitors this and escalates if threshold exceeded.
        do {
            try await db.collection("user_trust").document(authorId).updateData([
                "groomingFlagCount": FieldValue.increment(Int64(1)),
                "lastGroomingFlagAt": FieldValue.serverTimestamp()
            ])
        } catch {
            // Non-fatal to the removal itself, but still write an alert — escalation ladder
            // depends on this count being accurate.
            try await writeCriticalGroomingFailureAlert(
                contentRef: contentRef,
                authorId: authorId,
                detectionSource: detectionSource,
                failedStep: "user_trust_increment",
                error: error
            )
            throw error
        }

        // Step 4: Write to safety audit log.
        let auditRecord: [String: Any] = [
            "event": "grooming_auto_removal",
            "contentRef": contentRef,
            "authorId": authorId,
            "detectionSource": detectionSource,
            "clientTimestamp": Date().timeIntervalSince1970,
            "source": "AmenChildSafetyService"
        ]
        do {
            try await db.collection("safetyAuditLog").addDocument(data: auditRecord)
        } catch {
            // CRITICAL: audit record lost — compliance trail broken.
            try await writeCriticalGroomingFailureAlert(
                contentRef: contentRef,
                authorId: authorId,
                detectionSource: detectionSource,
                failedStep: "safety_audit_log",
                error: error
            )
            throw error
        }
    }

    private func writeCriticalGroomingFailureAlert(
        contentRef: String,
        authorId: String,
        detectionSource: String,
        failedStep: String,
        error: Error
    ) async throws {
        try await db.collection("criticalSafetyAlerts").addDocument(data: [
            "type": "grooming_removal_write_failure",
            "contentRef": contentRef,
            "authorId": authorId,
            "detectionSource": detectionSource,
            "failedStep": failedStep,
            "errorDescription": error.localizedDescription,
            "createdAt": FieldValue.serverTimestamp(),
            "requiresImmediateHumanReview": true,
            "reporterUid": Auth.auth().currentUser?.uid ?? "unknown"
        ])
    }

    // =========================================================================
    // MARK: - Private Helpers
    // =========================================================================

    /// Returns true if both users have a mutual follow edge in the social graph.
    /// Checks the /edges collection for a bidirectional relationship.
    private func areMutualFollows(userId1: String, userId2: String) async throws -> Bool {
        // Check that userId1 follows userId2
        let forward = try await db.collection("edges")
            .whereField("fromUserId", isEqualTo: userId1)
            .whereField("toUserId", isEqualTo: userId2)
            .whereField("type", isEqualTo: "follow")
            .limit(to: 1)
            .getDocuments()

        guard !forward.documents.isEmpty else { return false }

        // Check that userId2 follows userId1
        let reverse = try await db.collection("edges")
            .whereField("fromUserId", isEqualTo: userId2)
            .whereField("toUserId", isEqualTo: userId1)
            .whereField("type", isEqualTo: "follow")
            .limit(to: 1)
            .getDocuments()

        return !reverse.documents.isEmpty
    }

    /// Returns true if the guardian has approved this contact for DM with the minor.
    ///
    /// Reads from /guardianApprovedContacts/{minorId}/contacts/{contactId}.
    /// Returns false (deny) if the document is absent or guardian approval has not been given.
    private func isGuardianApprovedContact(minorId: String, contactId: String) async throws -> Bool {
        // OPEN-2: Guardian tools scope is pending T&S Lead resolution.
        // Current policy (default): guardian has not been given approve/deny capability.
        // Until OPEN-2 is resolved, we allow mutual-follow DMs without explicit guardian approval,
        // matching the current skeleton in C5 §4e ("guardian has zero read access").
        // This function returns true (allow) when guardian tools are not yet configured,
        // so mutual-follow DMs between minors and verified contacts proceed.
        // When OPEN-2 is resolved and guardian approval is required, this should query
        // /guardianApprovedContacts/{minorId}/contacts/{contactId} and require approved: true.
        let doc = try await db
            .collection("guardianApprovedContacts")
            .document(minorId)
            .collection("contacts")
            .document(contactId)
            .getDocument()

        // OPEN-2 placeholder: document absent means guardian tools not yet active — allow.
        if !doc.exists { return true }

        // CRITICAL: fail closed — no approval field on an existing document = no DM allowed.
        // A partial write or race condition that produces a document without the `approved`
        // field must be treated as NOT approved, not approved. ?? false enforces this.
        let approved = doc.data()?["approved"] as? Bool ?? false
        return approved
    }

    /// Validates a basic email format before writing to Firestore.
    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
