//
//  AntiHarassmentEngine.swift
//  AMENAPP
//
//  Anti-Harassment Engine with Repeat Offender Tracking
//  Enforcement escalation, user protection tools, appeal system
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Anti-Harassment Engine

/// Tracks repeat offenders, escalates enforcement, protects targets
class AntiHarassmentEngine {
    static let shared = AntiHarassmentEngine()

    private let db = Firestore.firestore()

    // MARK: - Enforcement History Tracking

    struct EnforcementRecord: Codable {
        let id: String
        let userId: String
        let violation: PolicyViolation
        let action: EnforcementAction
        let contentId: String?
        let contentType: ContentCategory
        let targetUserId: String?
        let timestamp: Date
        let confidence: Double
        let appealStatus: AppealStatus?

        enum AppealStatus: String, Codable {
            case pending = "pending"
            case approved = "approved"
            case denied = "denied"
        }
    }

    /// Record enforcement action for user
    func recordEnforcement(
        userId: String,
        violation: PolicyViolation,
        action: EnforcementAction,
        contentId: String?,
        contentType: ContentCategory,
        targetUserId: String?,
        confidence: Double
    ) async throws {

        let record = EnforcementRecord(
            id: UUID().uuidString,
            userId: userId,
            violation: violation,
            action: action,
            contentId: contentId,
            contentType: contentType,
            targetUserId: targetUserId,
            timestamp: Date(),
            confidence: confidence,
            appealStatus: nil
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
                "targetUserId": targetUserId as Any,
                "timestamp": Timestamp(date: record.timestamp),
                "confidence": confidence,
                "appealStatus": record.appealStatus?.rawValue as Any
            ])

        print("📝 [ENFORCEMENT] Recorded: User \(userId), Violation: \(violation), Action: \(action)")
    }

    /// Get user's enforcement history
    func getEnforcementHistory(userId: String, days: Int = 30) async throws -> [EnforcementRecord] {
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

            return EnforcementRecord(
                id: doc.documentID,
                userId: userId,
                violation: violation,
                action: action,
                contentId: data["contentId"] as? String,
                contentType: contentType,
                targetUserId: data["targetUserId"] as? String,
                timestamp: timestamp.dateValue(),
                confidence: confidence,
                appealStatus: appealStatus
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

        let history = try await getEnforcementHistory(userId: userId, days: 30)

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

    /// Enable enhanced protection for user
    func enableUserProtection(userId: String, reason: String) async throws {
        try await db
            .collection("users")
            .document(userId)
            .updateData([
                "enhancedProtectionEnabled": true,
                "enhancedProtectionReason": reason,
                "enhancedProtectionStarted": Timestamp(date: Date()),
                "commentApprovalRequired": true,  // Comments require approval
                "limitedProfileVisibility": true  // Hide from search temporarily
            ])

        // TODO: Notify user via NotificationService
        // try await NotificationService.shared.sendSystemNotification(
        //     to: userId,
        //     title: "Enhanced Protection Enabled",
        //     body: "We've enabled extra safety features on your account. Comments will require your approval.",
        //     data: ["type": "protection_enabled", "reason": reason]
        // )

        print("🛡️ [PROTECTION] Enabled for user: \(userId), Reason: \(reason)")
    }

    // MARK: - Temporary Restrictions

    enum RestrictionType: String, Codable {
        case commenting = "commenting"
        case posting = "posting"
        case messaging = "messaging"
    }

    struct UserRestriction: Codable {
        let userId: String
        let type: RestrictionType
        let reason: String
        let startDate: Date
        let endDate: Date
        let violationId: String?
    }

    /// Apply temporary restriction to user
    func applyRestriction(
        userId: String,
        type: RestrictionType,
        durationHours: Int,
        reason: String,
        violationId: String?
    ) async throws {

        let startDate = Date()
        let endDate = startDate.addingTimeInterval(Double(durationHours * 3600))

        let restriction = UserRestriction(
            userId: userId,
            type: type,
            reason: reason,
            startDate: startDate,
            endDate: endDate,
            violationId: violationId
        )

        try await db
            .collection("userRestrictions")
            .document("\(userId)_\(type.rawValue)")
            .setData([
                "userId": userId,
                "type": type.rawValue,
                "reason": reason,
                "startDate": Timestamp(date: startDate),
                "endDate": Timestamp(date: endDate),
                "violationId": violationId as Any
            ])

        // TODO: Notify user via NotificationService
        // try await NotificationService.shared.sendSystemNotification(
        //     to: userId,
        //     title: "Temporary Restriction",
        //     body: "Your \(type.rawValue) ability has been temporarily restricted for \(durationHours) hours due to: \(reason)",
        //     data: ["type": "restriction", "restrictionType": type.rawValue, "hours": "\(durationHours)"]
        // )

        print("⏸️ [RESTRICTION] Applied: User \(userId), Type: \(type), Duration: \(durationHours)h")
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

    /// Submit appeal for enforcement action
    func submitAppeal(
        userId: String,
        enforcementId: String,
        reason: String
    ) async throws -> String {

        let appealId = UUID().uuidString

        let appeal = Appeal(
            id: appealId,
            userId: userId,
            enforcementId: enforcementId,
            reason: reason,
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
                "reason": reason,
                "submittedAt": Timestamp(date: appeal.submittedAt),
                "status": appeal.status.rawValue
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

    /// Detect harassment patterns between two users
    func detectHarassmentPattern(
        userId: String,
        targetUserId: String
    ) async throws -> HarassmentPattern? {

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

            return EnforcementRecord(
                id: doc.documentID,
                userId: userId,
                violation: violation,
                action: action,
                contentId: data["contentId"] as? String,
                contentType: contentType,
                targetUserId: data["targetUserId"] as? String,
                timestamp: timestamp.dateValue(),
                confidence: confidence,
                appealStatus: nil
            )
        }

        let incidentCount = incidents.count
        let timeSpan = Date().timeIntervalSince(incidents.first!.timestamp)
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

    /// Take action on detected harassment pattern
    func handleHarassmentPattern(_ pattern: HarassmentPattern) async throws {
        print("🚨 [PATTERN] Harassment detected: \(pattern.userId) → \(pattern.targetUserId), Risk: \(pattern.riskLevel)")

        switch pattern.riskLevel {
        case .critical:
            // Immediate account restriction + escalate to safety team
            try await applyRestriction(
                userId: pattern.userId,
                type: .commenting,
                durationHours: 72,
                reason: "Critical harassment pattern detected",
                violationId: nil
            )
            try await enableUserProtection(
                userId: pattern.targetUserId,
                reason: "Target of critical harassment pattern"
            )

        case .high:
            // 48-hour commenting restriction
            try await applyRestriction(
                userId: pattern.userId,
                type: .commenting,
                durationHours: 48,
                reason: "Repeated harassment of same user",
                violationId: nil
            )
            try await enableUserProtection(
                userId: pattern.targetUserId,
                reason: "Target of repeated harassment"
            )

        case .medium:
            // 24-hour commenting restriction
            try await applyRestriction(
                userId: pattern.userId,
                type: .commenting,
                durationHours: 24,
                reason: "Multiple incidents targeting same user",
                violationId: nil
            )

        case .low:
            // Warning only
            // TODO: Send notification via NotificationService
            // try await NotificationService.shared.sendSystemNotification(
            //     to: pattern.userId,
            //     title: "Community Reminder",
            //     body: "Please be respectful in your interactions. Repeated targeting of other users may result in restrictions.",
            //     data: ["type": "warning", "reason": "interaction_pattern"]
            // )
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
