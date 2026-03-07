//
//  AntiHarassmentEngine.swift
//  AMENAPP
//
//  Anti-Harassment Engine with Repeat Offender Tracking
//  Enforcement escalation, user protection tools, appeal system
//

import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Anti-Harassment Engine

/// Tracks repeat offenders, escalates enforcement, protects targets
class AntiHarassmentEngine {
    static let shared = AntiHarassmentEngine()

    private let db = Firestore.firestore()

    // MARK: - Enforcement History Tracking

    // MARK: - Enforcement Record

    /// Source of an enforcement decision — used for analytics, appeals, and audit.
    enum EnforcementSource: String, Codable {
        case ai            = "ai"
        case keywords      = "keywords"
        case userReport    = "user_report"
        case moderator     = "moderator"
        case hybrid        = "hybrid"   // keyword pre-filter + AI confirmation
        case pattern       = "pattern"  // triggered by repeat-behavior pattern detection
    }

    /// Surface where the content appeared — used to apply surface-specific policies.
    enum ContentSurface: String, Codable {
        case post          = "post"
        case comment       = "comment"
        case dm            = "dm"
        case username      = "username"
        case bio           = "bio"
        case groupTitle    = "group_title"
        case prayerRequest = "prayer_request"
        case testimony     = "testimony"
        case churchNote    = "church_note"
    }

    struct EnforcementRecord: Codable {
        let id: String
        let userId: String
        let violation: PolicyViolation
        let action: EnforcementAction
        let contentId: String?
        let contentType: ContentCategory
        let surface: ContentSurface
        let targetUserId: String?
        let timestamp: Date
        let confidence: Double
        let appealStatus: AppealStatus?
        // Audit trail fields
        let source: EnforcementSource
        let modelVersion: String?
        let ruleIdsMatched: [String]
        let policyVersion: String
        /// Idempotency key: prevents duplicate records for the same moderation event.
        /// Format: contentId + violationRaw + actionRaw
        let idempotencyKey: String?

        enum AppealStatus: String, Codable {
            case pending = "pending"
            case approved = "approved"
            case denied = "denied"
        }
    }

    // MARK: - Current Policy Version
    // Bump this when enforcement thresholds, lexicon, or categories change.
    static let currentPolicyVersion = "2026-03-06"

    /// Record enforcement action for user.
    /// Requires an authenticated session — unauthenticated calls are rejected.
    /// Uses an idempotency key to prevent duplicate records for the same event.
    func recordEnforcement(
        userId: String,
        violation: PolicyViolation,
        action: EnforcementAction,
        contentId: String?,
        contentType: ContentCategory,
        surface: ContentSurface = .post,
        targetUserId: String?,
        confidence: Double,
        source: EnforcementSource = .hybrid,
        modelVersion: String? = nil,
        ruleIdsMatched: [String] = []
    ) async throws {

        // Auth guard: reject unauthenticated writes
        guard Auth.auth().currentUser != nil else {
            print("⛔️ [ENFORCEMENT] recordEnforcement rejected — no authenticated session")
            throw NSError(domain: "AntiHarassmentEngine", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Authentication required to record enforcement"])
        }

        // Build idempotency key to prevent duplicate records for the same moderation event
        let idempotencyKey: String
        if let cid = contentId {
            idempotencyKey = "\(cid)_\(violation.rawValue)_\(action.rawValue)"
        } else {
            idempotencyKey = "\(userId)_\(violation.rawValue)_\(action.rawValue)_\(Int(Date().timeIntervalSince1970 / 300))"
        }

        // Check for recent duplicate within a 5-minute window
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let existing = try? await db
            .collection("enforcementHistory")
            .whereField("idempotencyKey", isEqualTo: idempotencyKey)
            .whereField("timestamp", isGreaterThan: Timestamp(date: fiveMinutesAgo))
            .limit(to: 1)
            .getDocuments()

        if let existing, !existing.documents.isEmpty {
            print("⚠️ [ENFORCEMENT] Duplicate suppressed for idempotency key: \(idempotencyKey)")
            return
        }

        let record = EnforcementRecord(
            id: UUID().uuidString,
            userId: userId,
            violation: violation,
            action: action,
            contentId: contentId,
            contentType: contentType,
            surface: surface,
            targetUserId: targetUserId,
            timestamp: Date(),
            confidence: confidence,
            appealStatus: nil,
            source: source,
            modelVersion: modelVersion,
            ruleIdsMatched: ruleIdsMatched,
            policyVersion: AntiHarassmentEngine.currentPolicyVersion,
            idempotencyKey: idempotencyKey
        )

        try await db
            .collection("enforcementHistory")
            .document(record.id)
            .setData([
                "userId": userId,
                "violation": violation.rawValue,
                "action": action.rawValue,
                "contentId": contentId as Any,
                "contentType": contentType.rawValue,
                "surface": surface.rawValue,
                "targetUserId": targetUserId as Any,
                "timestamp": Timestamp(date: record.timestamp),
                "confidence": confidence,
                "appealStatus": record.appealStatus?.rawValue as Any,
                "source": source.rawValue,
                "modelVersion": modelVersion as Any,
                "ruleIdsMatched": ruleIdsMatched,
                "policyVersion": AntiHarassmentEngine.currentPolicyVersion,
                "idempotencyKey": idempotencyKey
            ])

        print("📝 [ENFORCEMENT] Recorded: User \(userId), Violation: \(violation), Action: \(action), Source: \(source.rawValue), Surface: \(surface.rawValue)")
    }

    /// Get user's enforcement history.
    /// Client-side callers may only request their own history. Cross-user queries
    /// must go through a Cloud Function with admin credentials.
    func getEnforcementHistory(userId: String, days: Int = 30) async throws -> [EnforcementRecord] {
        guard let currentUser = Auth.auth().currentUser else {
            throw NSError(domain: "AntiHarassmentEngine", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Authentication required"])
        }
        // Only allow reading own history from the client
        guard currentUser.uid == userId else {
            throw NSError(domain: "AntiHarassmentEngine", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot read another user's enforcement history from the client"])
        }

        return try await fetchEnforcementHistory(userId: userId, days: days)
    }

    /// Internal query — bypasses the own-user guard for engine-level pattern detection.
    /// Must not be called with user-supplied `userId` from UI code.
    private func fetchEnforcementHistory(userId: String, days: Int = 30) async throws -> [EnforcementRecord] {
        let cutoffDate = Date().addingTimeInterval(-Double(days * 24 * 3600))

        let snapshot = try await db
            .collection("enforcementHistory")
            .whereField("userId", isEqualTo: userId)
            .whereField("timestamp", isGreaterThan: Timestamp(date: cutoffDate))
            .order(by: "timestamp", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let userId = data["userId"] as? String,
                  let violationRaw = data["violation"] as? String,
                  let violation = PolicyViolation(rawValue: violationRaw),
                  let actionRaw = data["action"] as? String,
                  let action = EnforcementAction(rawValue: actionRaw),
                  let contentTypeRaw = data["contentType"] as? String,
                  let contentType = ContentCategory(rawValue: contentTypeRaw),
                  let timestamp = data["timestamp"] as? Timestamp,
                  let confidence = data["confidence"] as? Double else {
                return nil
            }

            let appealStatusRaw = data["appealStatus"] as? String
            let appealStatus = appealStatusRaw != nil ? EnforcementRecord.AppealStatus(rawValue: appealStatusRaw!) : nil

            let surfaceRaw = data["surface"] as? String ?? ContentSurface.post.rawValue
            let surface = ContentSurface(rawValue: surfaceRaw) ?? .post
            let sourceRaw = data["source"] as? String ?? EnforcementSource.hybrid.rawValue
            let source = EnforcementSource(rawValue: sourceRaw) ?? .hybrid

            return EnforcementRecord(
                id: doc.documentID,
                userId: userId,
                violation: violation,
                action: action,
                contentId: data["contentId"] as? String,
                contentType: contentType,
                surface: surface,
                targetUserId: data["targetUserId"] as? String,
                timestamp: timestamp.dateValue(),
                confidence: confidence,
                appealStatus: appealStatus,
                source: source,
                modelVersion: data["modelVersion"] as? String,
                ruleIdsMatched: data["ruleIdsMatched"] as? [String] ?? [],
                policyVersion: data["policyVersion"] as? String ?? "unknown",
                idempotencyKey: data["idempotencyKey"] as? String
            )
        }
    }

    // MARK: - Escalation Logic

    /// Determine if enforcement should be escalated based on history
    func shouldEscalateEnforcement(
        userId: String,
        currentViolation: PolicyViolation,
        targetUserId: String?
    ) async throws -> (shouldEscalate: Bool, reason: String) {

        let history = try await fetchEnforcementHistory(userId: userId, days: 30)

        // Count violations by severity
        let criticalCount = history.filter { $0.violation.severity == .critical }.count
        let severeCount = history.filter { $0.violation.severity == .severe }.count
        let moderateCount = history.filter { $0.violation.severity == .moderate }.count

        // ESCALATION RULES

        // Rule 1: Any critical violation = immediate escalation
        if criticalCount > 0 {
            return (true, "User has prior critical violations")
        }

        // Rule 2: 2+ severe violations = escalate
        if severeCount >= 2 {
            return (true, "User has \(severeCount) severe violations in 30 days")
        }

        // Rule 3: 5+ moderate violations = escalate
        if moderateCount >= 5 {
            return (true, "User has \(moderateCount) moderate violations in 30 days")
        }

        // Rule 4: Targeting same person repeatedly
        if let target = targetUserId {
            let targetedCount = history.filter { $0.targetUserId == target }.count
            if targetedCount >= 3 {
                return (true, "User has targeted same person \(targetedCount) times")
            }

            // Rule 4b: Contact after target has blocked the sender
            let isBlocked = await checkIfBlocked(actorId: userId, targetId: target)
            if isBlocked {
                return (true, "User is attempting contact with someone who has blocked them")
            }
        }

        // Rule 5: Recent escalation pattern (violations getting worse)
        let recentHistory = history.prefix(5)
        let severityTrend = recentHistory.map { $0.violation.severity.rawValue }
        if severityTrend.count >= 3 {
            let isEscalating = zip(severityTrend, severityTrend.dropFirst()).allSatisfy { $0 <= $1 }
            if isEscalating {
                return (true, "User's violations are escalating in severity")
            }
        }

        return (false, "")
    }

    // MARK: - User Protection Tools

    /// Check if user needs protection (being targeted)
    func checkUserNeedsProtection(userId: String) async throws -> (needsProtection: Bool, reason: String) {
        // Count how many times user has been targeted in last 7 days
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)

        let targeting = try await db
            .collection("enforcementHistory")
            .whereField("targetUserId", isEqualTo: userId)
            .whereField("timestamp", isGreaterThan: Timestamp(date: sevenDaysAgo))
            .getDocuments()

        let targetingCount = targeting.documents.count

        // Count unique users targeting this person
        let uniqueTargeters = Set(targeting.documents.compactMap { $0.data()["userId"] as? String })

        // PROTECTION TRIGGERS

        // Trigger 1: 5+ incidents in 7 days
        if targetingCount >= 5 {
            return (true, "\(targetingCount) harassment incidents in past week")
        }

        // Trigger 2: 3+ unique users targeting
        if uniqueTargeters.count >= 3 {
            return (true, "\(uniqueTargeters.count) unique users have targeted this person")
        }

        // Trigger 3: User has reported feeling unsafe (check reports)
        let userReports = try await db
            .collection("userReports")
            .whereField("reporterId", isEqualTo: userId)
            .whereField("createdAt", isGreaterThan: Timestamp(date: sevenDaysAgo))
            .limit(to: 5)
            .getDocuments()

        if userReports.documents.count >= 3 {
            return (true, "User has filed \(userReports.documents.count) reports in past week")
        }

        return (false, "")
    }

    /// Enable enhanced protection for user.
    /// Idempotent: if protection is already active and would not expire sooner,
    /// the existing protection is kept (never shortened).
    /// - Parameters:
    ///   - expiresAfterDays: Protection auto-expires after this many days (default 7).
    func enableUserProtection(userId: String, reason: String, expiresAfterDays: Int = 7) async throws {
        let expiresAt = Date().addingTimeInterval(Double(expiresAfterDays * 86400))

        // Idempotency: read existing protection and never shorten its expiry
        let existing = try? await db.collection("users").document(userId).getDocument()
        if let existing, existing.exists,
           let existingProtection = existing.data()?["enhancedProtectionEnabled"] as? Bool, existingProtection,
           let existingExpiry = (existing.data()?["enhancedProtectionExpiresAt"] as? Timestamp)?.dateValue(),
           existingExpiry > expiresAt {
            print("ℹ️ [PROTECTION] Already active for \(userId) until \(existingExpiry) — not shortening.")
            return
        }

        try await db
            .collection("users")
            .document(userId)
            .setData([
                "enhancedProtectionEnabled": true,
                "enhancedProtectionReason": reason,
                "enhancedProtectionStarted": Timestamp(date: Date()),
                "enhancedProtectionExpiresAt": Timestamp(date: expiresAt),
                "commentApprovalRequired": true,
                "limitedProfileVisibility": true
            ], merge: true)

        // Notify target user — only if this is a new or extended activation
        _ = try? await db.collection("notifications").addDocument(data: [
            "type": "system_protection_enabled",
            "toUserId": userId,
            "title": "Enhanced Protection Enabled",
            "body": "We've noticed activity that may be affecting your experience. We've enabled extra safety features on your account. Comments will require your approval.",
            "read": false,
            "createdAt": FieldValue.serverTimestamp(),
            "data": ["reason": reason, "expiresAfterDays": "\(expiresAfterDays)"]
        ])

        print("🛡️ [PROTECTION] Enabled for user: \(userId), Reason: \(reason), Expires: \(expiresAt)")
    }

    // MARK: - Temporary Restrictions

    enum RestrictionType: String, Codable {
        case commenting  = "commenting"
        case posting     = "posting"
        case messaging   = "messaging"
        /// Cannot comment on, mention, follow, or DM the specific target user.
        case noContact   = "no_contact"
        /// Can reply to others but cannot initiate new threads or top-level comments.
        case replyOnly   = "reply_only"
        /// DM capability frozen — cannot open new conversations.
        case dmFreeze    = "dm_freeze"
        /// All new content goes through friction prompt (scripture-grounded civility rewrite).
        case frictionPrompt = "friction_prompt"
    }

    struct UserRestriction: Codable {
        let userId: String
        let type: RestrictionType
        let reason: String
        let startDate: Date
        let endDate: Date
        let violationId: String?
    }

    /// Apply temporary restriction to user.
    /// Idempotent: if a restriction of this type already exists and its end date is
    /// later than the new proposed end date, the existing restriction is kept (never shortened).
    func applyRestriction(
        userId: String,
        type: RestrictionType,
        durationHours: Int,
        reason: String,
        violationId: String?,
        targetUserId: String? = nil   // Required for .noContact restrictions
    ) async throws {

        let startDate = Date()
        let proposedEndDate = startDate.addingTimeInterval(Double(durationHours * 3600))

        let docId = type == .noContact
            ? "\(userId)_no_contact_\(targetUserId ?? "all")"
            : "\(userId)_\(type.rawValue)"

        // Check for existing restriction — never shorten an existing one
        let existing = try? await db
            .collection("userRestrictions")
            .document(docId)
            .getDocument()

        if let existing, existing.exists,
           let existingEnd = (existing.data()?["endDate"] as? Timestamp)?.dateValue(),
           existingEnd > proposedEndDate {
            print("ℹ️ [RESTRICTION] Existing restriction for \(userId)/\(type.rawValue) ends later (\(existingEnd)) — not shortening.")
            return
        }

        try await db
            .collection("userRestrictions")
            .document(docId)
            .setData([
                "userId": userId,
                "type": type.rawValue,
                "reason": reason,
                "startDate": Timestamp(date: startDate),
                "endDate": Timestamp(date: proposedEndDate),
                "violationId": violationId as Any,
                "targetUserId": targetUserId as Any
            ])

        // Notify restricted user about the temporary restriction
        _ = try? await db.collection("notifications").addDocument(data: [
            "type": "system_restriction",
            "toUserId": userId,
            "title": "Temporary Restriction",
            "body": "Your account has been temporarily restricted for \(durationHours) hours due to a community guideline violation. You can appeal this decision in Settings.",
            "read": false,
            "createdAt": FieldValue.serverTimestamp(),
            "data": ["restrictionType": type.rawValue, "hours": "\(durationHours)"]
        ])

        print("⏸️ [RESTRICTION] Applied: User \(userId), Type: \(type.rawValue), Duration: \(durationHours)h")
    }

    /// Check if user is currently restricted
    func checkRestriction(userId: String, type: RestrictionType) async throws -> (isRestricted: Bool, endsAt: Date?) {
        let doc = try await db
            .collection("userRestrictions")
            .document("\(userId)_\(type.rawValue)")
            .getDocument()

        guard doc.exists, let data = doc.data(),
              let endTimestamp = data["endDate"] as? Timestamp else {
            return (false, nil)
        }

        let endDate = endTimestamp.dateValue()
        let isStillRestricted = endDate > Date()

        if !isStillRestricted {
            // Restriction expired, clean up
            try await doc.reference.delete()
            return (false, nil)
        }

        return (true, endDate)
    }

    // MARK: - Appeal System

    struct Appeal: Codable {
        let id: String
        let userId: String
        let enforcementId: String
        let reason: String
        let submittedAt: Date
        let status: AppealStatus
        let reviewedAt: Date?
        let reviewedBy: String?
        let decision: String?

        enum AppealStatus: String, Codable {
            case pending = "pending"
            case underReview = "under_review"
            case approved = "approved"
            case denied = "denied"
        }
    }

    /// Submit appeal for enforcement action.
    /// Requires the caller to be the user the enforcement was recorded against.
    func submitAppeal(
        userId: String,
        enforcementId: String,
        reason: String
    ) async throws -> String {

        guard let currentUser = Auth.auth().currentUser, currentUser.uid == userId else {
            throw NSError(domain: "AntiHarassmentEngine", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Can only submit appeals for your own enforcement records"])
        }

        // Rate limit: max 1 appeal per enforcement record
        let existingAppeal = try? await db
            .collection("appeals")
            .whereField("userId", isEqualTo: userId)
            .whereField("enforcementId", isEqualTo: enforcementId)
            .limit(to: 1)
            .getDocuments()

        if let existingAppeal, !existingAppeal.documents.isEmpty {
            throw NSError(domain: "AntiHarassmentEngine", code: 409,
                          userInfo: [NSLocalizedDescriptionKey: "An appeal for this enforcement action already exists"])
        }

        // Validate reason length (prevent abuse)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedReason.count >= 10 && trimmedReason.count <= 1000 else {
            throw NSError(domain: "AntiHarassmentEngine", code: 422,
                          userInfo: [NSLocalizedDescriptionKey: "Appeal reason must be between 10 and 1000 characters"])
        }

        let appealId = UUID().uuidString

        let appeal = Appeal(
            id: appealId,
            userId: userId,
            enforcementId: enforcementId,
            reason: trimmedReason,
            submittedAt: Date(),
            status: .pending,
            reviewedAt: nil,
            reviewedBy: nil,
            decision: nil
        )

        try await db
            .collection("appeals")
            .document(appealId)
            .setData([
                "id": appealId,
                "userId": userId,
                "enforcementId": enforcementId,
                "reason": trimmedReason,
                "submittedAt": Timestamp(date: appeal.submittedAt),
                "status": appeal.status.rawValue,
                "policyVersion": AntiHarassmentEngine.currentPolicyVersion
            ])

        // Update enforcement record with appeal
        try await db
            .collection("enforcementHistory")
            .document(enforcementId)
            .updateData([
                "appealId": appealId,
                "appealStatus": "pending"
            ])

        print("📝 [APPEAL] Submitted: \(appealId), User: \(userId)")

        return appealId
    }

    // MARK: - Relationship State Helpers

    /// Returns true if `targetId` has blocked `actorId`, meaning the actor is
    /// attempting contact with someone who has explicitly excluded them.
    private func checkIfBlocked(actorId: String, targetId: String) async -> Bool {
        do {
            let snapshot = try await db
                .collection("blockedUsers")
                .whereField("userId", isEqualTo: targetId)
                .whereField("blockedUserId", isEqualTo: actorId)
                .limit(to: 1)
                .getDocuments()
            return !snapshot.documents.isEmpty
        } catch {
            return false  // Unknown — do not escalate on error
        }
    }

    // MARK: - Appeal System

    /// Get user's appeals
    func getUserAppeals(userId: String) async throws -> [Appeal] {
        let snapshot = try await db
            .collection("appeals")
            .whereField("userId", isEqualTo: userId)
            .order(by: "submittedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let id = data["id"] as? String,
                  let userId = data["userId"] as? String,
                  let enforcementId = data["enforcementId"] as? String,
                  let reason = data["reason"] as? String,
                  let submittedAt = data["submittedAt"] as? Timestamp,
                  let statusRaw = data["status"] as? String,
                  let status = Appeal.AppealStatus(rawValue: statusRaw) else {
                return nil
            }

            return Appeal(
                id: id,
                userId: userId,
                enforcementId: enforcementId,
                reason: reason,
                submittedAt: submittedAt.dateValue(),
                status: status,
                reviewedAt: (data["reviewedAt"] as? Timestamp)?.dateValue(),
                reviewedBy: data["reviewedBy"] as? String,
                decision: data["decision"] as? String
            )
        }
    }

    // MARK: - Harassment Pattern Detection

    struct HarassmentPattern {
        let userId: String
        let targetUserId: String
        let incidentCount: Int
        let timeSpan: TimeInterval
        let violationTypes: [PolicyViolation]
        let isEscalating: Bool
        let riskLevel: RiskLevel

        enum RiskLevel: String {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case critical = "critical"
        }
    }

    /// Detect harassment patterns between two users.
    /// Requires an authenticated session.
    func detectHarassmentPattern(
        userId: String,
        targetUserId: String
    ) async throws -> HarassmentPattern? {

        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "AntiHarassmentEngine", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Authentication required"])
        }

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)

        // Get all enforcement records where this user targeted the other
        let records = try await db
            .collection("enforcementHistory")
            .whereField("userId", isEqualTo: userId)
            .whereField("targetUserId", isEqualTo: targetUserId)
            .whereField("timestamp", isGreaterThan: Timestamp(date: thirtyDaysAgo))
            .order(by: "timestamp", descending: false)
            .getDocuments()

        guard !records.documents.isEmpty else {
            return nil  // No pattern detected
        }

        let incidents = records.documents.compactMap { doc -> EnforcementRecord? in
            let data = doc.data()
            guard let userId = data["userId"] as? String,
                  let violationRaw = data["violation"] as? String,
                  let violation = PolicyViolation(rawValue: violationRaw),
                  let actionRaw = data["action"] as? String,
                  let action = EnforcementAction(rawValue: actionRaw),
                  let contentTypeRaw = data["contentType"] as? String,
                  let contentType = ContentCategory(rawValue: contentTypeRaw),
                  let timestamp = data["timestamp"] as? Timestamp,
                  let confidence = data["confidence"] as? Double else {
                return nil
            }

            let surfaceRaw = data["surface"] as? String ?? ContentSurface.post.rawValue
            let surface = ContentSurface(rawValue: surfaceRaw) ?? .post
            let sourceRaw = data["source"] as? String ?? EnforcementSource.hybrid.rawValue
            let source = EnforcementSource(rawValue: sourceRaw) ?? .hybrid

            return EnforcementRecord(
                id: doc.documentID,
                userId: userId,
                violation: violation,
                action: action,
                contentId: data["contentId"] as? String,
                contentType: contentType,
                surface: surface,
                targetUserId: data["targetUserId"] as? String,
                timestamp: timestamp.dateValue(),
                confidence: confidence,
                appealStatus: nil,
                source: source,
                modelVersion: data["modelVersion"] as? String,
                ruleIdsMatched: data["ruleIdsMatched"] as? [String] ?? [],
                policyVersion: data["policyVersion"] as? String ?? "unknown",
                idempotencyKey: data["idempotencyKey"] as? String
            )
        }

        // Guard: all docs failed to parse (schema mismatch) — treat as no pattern
        guard !incidents.isEmpty, let firstIncident = incidents.first else {
            return nil
        }

        let incidentCount = incidents.count
        let timeSpan = Date().timeIntervalSince(firstIncident.timestamp)
        let violationTypes = incidents.map { $0.violation }

        // Check if pattern is escalating
        let severities = incidents.map { $0.violation.severity.rawValue }
        let isEscalating = zip(severities, severities.dropFirst()).contains { $0 < $1 }

        // Determine risk level
        let riskLevel: HarassmentPattern.RiskLevel
        if incidentCount >= 10 || violationTypes.contains(where: { $0.severity == .critical }) {
            riskLevel = .critical
        } else if incidentCount >= 5 || isEscalating {
            riskLevel = .high
        } else if incidentCount >= 3 {
            riskLevel = .medium
        } else {
            riskLevel = .low
        }

        return HarassmentPattern(
            userId: userId,
            targetUserId: targetUserId,
            incidentCount: incidentCount,
            timeSpan: timeSpan,
            violationTypes: violationTypes,
            isEscalating: isEscalating,
            riskLevel: riskLevel
        )
    }

    /// Take action on detected harassment pattern.
    /// Minor-safety violations (minorSafety, sexualMinors) always receive the
    /// critical path regardless of the pattern's computed riskLevel.
    func handleHarassmentPattern(_ pattern: HarassmentPattern) async throws {
        print("🚨 [PATTERN] Harassment detected: \(pattern.userId) → \(pattern.targetUserId), Risk: \(pattern.riskLevel)")

        // MINOR-SAFETY OVERRIDE: any pattern involving child safety or sexual exploitation
        // violations gets the most severe response path unconditionally.
        let hasMinorSafetyViolation = pattern.violationTypes.contains {
            $0 == .childSafety || $0 == .sexualExploitation
        }
        if hasMinorSafetyViolation {
            print("🚨 [PATTERN] MINOR-SAFETY override — applying critical path regardless of risk level")
            // Full messaging + posting freeze
            try await applyRestriction(
                userId: pattern.userId,
                type: .messaging,
                durationHours: 168,  // 7 days
                reason: "Minor safety violation pattern — pending human review",
                violationId: nil
            )
            try await applyRestriction(
                userId: pattern.userId,
                type: .posting,
                durationHours: 168,
                reason: "Minor safety violation pattern — pending human review",
                violationId: nil
            )
            // Target-specific no-contact restriction
            try await applyRestriction(
                userId: pattern.userId,
                type: .noContact,
                durationHours: 168,
                reason: "Minor safety — no contact with target",
                violationId: nil,
                targetUserId: pattern.targetUserId
            )
            // Enable protection for target
            try await enableUserProtection(
                userId: pattern.targetUserId,
                reason: "Target of minor-safety pattern",
                expiresAfterDays: 30
            )
            // Flag for immediate human review
            _ = try? await db.collection("moderationQueue").addDocument(data: [
                "type": "minor_safety_pattern",
                "offenderId": pattern.userId,
                "targetId": pattern.targetUserId,
                "priority": "immediate",
                "incidentCount": pattern.incidentCount,
                "createdAt": FieldValue.serverTimestamp(),
                "policyVersion": AntiHarassmentEngine.currentPolicyVersion
            ])
            return
        }

        switch pattern.riskLevel {
        case .critical:
            // Full commenting + DM freeze + no-contact with target
            try await applyRestriction(
                userId: pattern.userId,
                type: .commenting,
                durationHours: 72,
                reason: "Critical harassment pattern detected",
                violationId: nil
            )
            try await applyRestriction(
                userId: pattern.userId,
                type: .noContact,
                durationHours: 168,  // 7-day no-contact with specific target
                reason: "Critical harassment — no contact with target",
                violationId: nil,
                targetUserId: pattern.targetUserId
            )
            try await enableUserProtection(
                userId: pattern.targetUserId,
                reason: "Target of critical harassment pattern",
                expiresAfterDays: 14
            )

        case .high:
            // 48-hour commenting restriction + no-contact with target
            try await applyRestriction(
                userId: pattern.userId,
                type: .commenting,
                durationHours: 48,
                reason: "Repeated harassment of same user",
                violationId: nil
            )
            try await applyRestriction(
                userId: pattern.userId,
                type: .noContact,
                durationHours: 72,
                reason: "Repeated harassment — no contact with target",
                violationId: nil,
                targetUserId: pattern.targetUserId
            )
            try await enableUserProtection(
                userId: pattern.targetUserId,
                reason: "Target of repeated harassment",
                expiresAfterDays: 7
            )

        case .medium:
            // Friction prompt + 24-hour no-contact rather than broad commenting ban
            try await applyRestriction(
                userId: pattern.userId,
                type: .frictionPrompt,
                durationHours: 48,
                reason: "Multiple targeting incidents — friction applied",
                violationId: nil
            )
            try await applyRestriction(
                userId: pattern.userId,
                type: .noContact,
                durationHours: 24,
                reason: "Multiple incidents targeting same user",
                violationId: nil,
                targetUserId: pattern.targetUserId
            )

        case .low:
            // Warning only — scripture-grounded civility reminder
            _ = try? await db.collection("notifications").addDocument(data: [
                "type": "system_warning",
                "toUserId": pattern.userId,
                "title": "A Gentle Reminder",
                "body": "\"Be kind to one another, tenderhearted\" (Ephesians 4:32). Repeated targeting of other members may result in restrictions.",
                "read": false,
                "createdAt": FieldValue.serverTimestamp(),
                "data": ["reason": "interaction_pattern"]
            ])
            print("⚠️ [WARNING] Sent to user: \(pattern.userId)")
        }
    }
}

// MARK: - User Safety Dashboard

extension AntiHarassmentEngine {

    /// Get user's safety dashboard data
    func getSafetyDashboard(userId: String) async throws -> SafetyDashboard {
        let history = try await getEnforcementHistory(userId: userId, days: 30)
        let restrictions = try await getActiveRestrictions(userId: userId)
        let appeals = try await getUserAppeals(userId: userId)
        let protectionStatus = try await checkUserNeedsProtection(userId: userId)

        return SafetyDashboard(
            userId: userId,
            enforcementCount: history.count,
            activeRestrictions: restrictions,
            pendingAppeals: appeals.filter { $0.status == .pending }.count,
            protectionEnabled: protectionStatus.needsProtection,
            lastIncidentDate: history.first?.timestamp
        )
    }

    struct SafetyDashboard: Codable {
        let userId: String
        let enforcementCount: Int
        let activeRestrictions: [UserRestriction]
        let pendingAppeals: Int
        let protectionEnabled: Bool
        let lastIncidentDate: Date?
    }

    private func getActiveRestrictions(userId: String) async throws -> [UserRestriction] {
        let snapshot = try await db
            .collection("userRestrictions")
            .whereField("userId", isEqualTo: userId)
            .whereField("endDate", isGreaterThan: Timestamp(date: Date()))
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let userId = data["userId"] as? String,
                  let typeRaw = data["type"] as? String,
                  let type = RestrictionType(rawValue: typeRaw),
                  let reason = data["reason"] as? String,
                  let startDate = data["startDate"] as? Timestamp,
                  let endDate = data["endDate"] as? Timestamp else {
                return nil
            }

            return UserRestriction(
                userId: userId,
                type: type,
                reason: reason,
                startDate: startDate.dateValue(),
                endDate: endDate.dateValue(),
                violationId: data["violationId"] as? String
            )
        }
    }
}
