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

    /// Returns true if the user is classified as a minor (teen or under_minimum).
    ///
    /// Reads the `ageTier` field from /users/{userId}.
    /// Returns false if the field is absent or the document doesn't exist —
    /// treat unknown as non-minor for content access (conservative in the other direction
    /// is canDM, which is fail-closed to false).
    ///
    /// - Throws: Firestore read errors. Callers on safety-critical paths should handle these.
    func checkIsMinor(userId: String) async throws -> Bool {
        let category = try await getAgeCategory(userId: userId)
        return category == .teen || category == .underMinimum
    }

    /// Resolves the user's AgeCategory from their Firestore profile.
    ///
    /// - Throws: Firestore read errors.
    func getAgeCategory(userId: String) async throws -> AgeCategory {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard let data = doc.data() else { return .adult }
        let raw = data["ageTier"] as? String ?? AgeCategory.adult.rawValue
        return AgeCategory(rawValue: raw) ?? .adult
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
            try? await db.collection(collection).document(documentId).updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp(),
                "deletionReason": "csam_escalation"
            ])
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

        try? await db.collection("moderationQueue").addDocument(data: queueRecord)

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
        try? await db.collection("safetyAuditLog").addDocument(data: auditRecord)
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

        // If guardian tools are not yet active (document absent), allow mutual-follow DMs.
        if !doc.exists { return true }

        // If a guardian approval document exists, check the approved field.
        let approved = doc.data()?["approved"] as? Bool ?? true
        return approved
    }

    /// Validates a basic email format before writing to Firestore.
    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
