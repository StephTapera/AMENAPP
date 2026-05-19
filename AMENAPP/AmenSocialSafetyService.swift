// AmenSocialSafetyService.swift
// AMENAPP
// Main Social Safety OS client service — bridges iOS models to backend callables.

import Foundation
import FirebaseAuth
import FirebaseFunctions
import FirebaseFirestore
import Combine

@MainActor
final class AmenSocialSafetyService: ObservableObject {
    static let shared = AmenSocialSafetyService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    // MARK: - Content Safety

    /// Evaluate a piece of content before publishing.
    func evaluateContentSafety(
        contentId: String,
        contentType: String,
        text: String?,
        mediaURLs: [String] = [],
        authorId: String
    ) async throws -> SafetyDecision {
        let payload: [String: Any] = [
            "contentId": contentId,
            "contentType": contentType,
            "text": text as Any,
            "mediaURLs": mediaURLs,
            "authorId": authorId
        ]
        let result = try await functions.httpsCallable("evaluateContentSafety").call(payload)
        let data = result.data as? [String: Any] ?? [:]
        return decodeSafetyDecision(from: data)
    }

    /// Publish content only after passing the safety gate.
    func publishWithSafetyDecision(
        contentId: String,
        contentType: String,
        decision: SafetyDecision
    ) async throws -> Bool {
        guard decision.action != .blockSend else { return false }
        let result = try await functions.httpsCallable("publishWithSafetyDecision").call([
            "contentId": contentId,
            "contentType": contentType,
            "action": decision.action.rawValue,
            "riskCategory": decision.riskCategory?.rawValue as Any
        ])
        let data = result.data as? [String: Any] ?? [:]
        return data["published"] as? Bool ?? false
    }

    // MARK: - Message Safety

    /// Evaluate a DM/message before delivery.
    func evaluateMessageSafety(
        conversationId: String,
        message: String,
        senderId: String,
        recipientId: String,
        recipientIsMinor: Bool
    ) async throws -> SafetyDecision {
        let payload: [String: Any] = [
            "conversationId": conversationId,
            "message": message,
            "senderId": senderId,
            "recipientId": recipientId,
            "recipientIsMinor": recipientIsMinor
        ]
        let result = try await functions.httpsCallable("evaluateMessageSafety").call(payload)
        let data = result.data as? [String: Any] ?? [:]
        return decodeSafetyDecision(from: data)
    }

    // MARK: - Media Integrity

    /// Evaluate media before it is attached to a post.
    /// Returns a SafetyDecision with an `integrityLabel` in the backend response.
    func evaluateMediaIntegrity(
        mediaURL: String,
        mediaType: String,
        contentId: String,
        isAIGenerated: Bool = false,
        fileSizeBytes: Int? = nil
    ) async throws -> SafetyDecision {
        var payload: [String: Any] = [
            "mediaURL": mediaURL,
            "mediaType": mediaType,
            "contentId": contentId,
            "isAIGenerated": isAIGenerated
        ]
        if let size = fileSizeBytes { payload["fileSizeBytes"] = size }
        let result = try await functions.httpsCallable("evaluateMediaIntegrity").call(payload)
        let data = result.data as? [String: Any] ?? [:]
        return decodeSafetyDecision(from: data)
    }

    // MARK: - Reports

    func createSafetyReport(
        entityId: String,
        entityType: String,
        category: SafetyRiskCategory,
        description: String?,
        evidenceURLs: [String] = []
    ) async throws -> SafetyReportRecord {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let payload: [String: Any] = [
            "entityId": entityId,
            "entityType": entityType,
            "category": category.rawValue,
            "description": description as Any,
            "evidenceURLs": evidenceURLs,
            "reporterId": uid
        ]
        let result = try await functions.httpsCallable("createSafetyReport").call(payload)
        let data = result.data as? [String: Any] ?? [:]
        return SafetyReportRecord(
            id: data["reportId"] as? String ?? UUID().uuidString,
            reporterUid: uid,
            contentId: entityType == "content" ? entityId : nil,
            conversationId: entityType == "conversation" ? entityId : nil,
            category: category,
            severity: SafetySeverity(rawValue: data["severity"] as? String ?? "") ?? .low,
            description: description,
            evidenceRefs: evidenceURLs,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Panic / Emergency Flows

    func activateSextortionPanicFlow(for userId: String) async throws {
        _ = try await functions.httpsCallable("activateSextortionPanicFlow").call([
            "userId": userId
        ])
    }

    // MARK: - Trusted Contacts

    func fetchTrustedContacts() async throws -> [TrustedContact] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let snapshot = try await db.collection("users").document(uid)
            .collection("trustedContacts").getDocuments()
        return snapshot.documents.compactMap { decodeTrustedContact(from: $0.data(), id: $0.documentID) }
    }

    func addTrustedContact(_ contact: TrustedContact) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        _ = try await functions.httpsCallable("updateTrustedContacts").call([
            "action": "add",
            "contactId": contact.contactUserId,
            "relationshipType": contact.relationshipType.rawValue,
            "notificationLevel": contact.notificationLevel.rawValue
        ])
        _ = uid // used implicitly via the callable auth context
    }

    func removeTrustedContact(contactId: String) async throws {
        _ = try await functions.httpsCallable("updateTrustedContacts").call([
            "action": "remove",
            "contactId": contactId
        ])
    }

    // MARK: - Feed Controls

    func fetchFeedControlState() async throws -> FeedControlState {
        guard let uid = Auth.auth().currentUser?.uid else { return FeedControlState() }
        let doc = try await db.collection("users").document(uid)
            .collection("feedControls").document("current").getDocument()
        let data = doc.data() ?? [:]
        return decodeFeedControlState(from: data)
    }

    func updateFeedControls(_ state: FeedControlState) async throws {
        _ = try await functions.httpsCallable("updateFeedControls").call([
            "mode": state.activeMode.rawValue,
            "categories": state.blockedCategories.map { $0.rawValue },
            "sessionDurationMinutes": state.sessionDurationLimitMinutes as Any,
            "quietHoursStart": state.quietHoursStart as Any,
            "quietHoursEnd": state.quietHoursEnd as Any
        ])
    }

    // MARK: - Session Boundaries

    func recordSessionBoundarySignal(signal: WellbeingSignal) async throws {
        _ = try await functions.httpsCallable("recordSessionBoundarySignal").call([
            "signalType": signal.signalType.rawValue,
            "value": signal.value,
            "confidence": signal.confidence,
            "source": signal.source,
            "createdAt": Timestamp(date: signal.createdAt)
        ])
    }

    func checkSessionBoundary() async throws -> SessionBoundary? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let doc = try await db.collection("users").document(uid)
            .collection("sessionBoundaries").document("active").getDocument()
        guard doc.exists, let data = doc.data() else { return nil }
        return decodeSessionBoundary(from: data)
    }

    // MARK: - Claim Context / Integrity

    func submitClaimContext(_ claim: ClaimContext) async throws {
        _ = try await functions.httpsCallable("submitClaimContext").call([
            "contentId": claim.contentId,
            "claimText": claim.claimText,
            "claimType": claim.claimType.rawValue,
            "sourceUrls": claim.sourceUrls,
            "scriptureRefs": claim.scriptureRefs,
            "contextSummary": claim.contextSummary as Any,
            "confidence": claim.confidence,
            "verificationStatus": claim.verificationStatus.rawValue
        ])
    }

    func fetchIntegrityLabel(for contentId: String) async throws -> ContentIntegrityLabel? {
        let doc = try await db.collection("contentIntegrity").document(contentId).getDocument()
        guard doc.exists, let data = doc.data() else { return nil }
        return decodeIntegrityLabel(from: data, contentId: contentId)
    }

    // MARK: - Algorithm Transparency

    func getRecommendationContext(for contentId: String) async throws -> String? {
        let result = try await functions.httpsCallable("getRecommendationContext").call([
            "contentId": contentId
        ])
        let data = result.data as? [String: Any] ?? [:]
        return data["explanation"] as? String
    }

    func resetRecommendationTraining() async throws {
        _ = try await functions.httpsCallable("resetRecommendationTraining").call([:])
    }

    // MARK: - Wellbeing Signals (local + backend)

    private var wellbeingBuffer: [WellbeingSignal] = []

    func appendWellbeingSignal(_ signal: WellbeingSignal) {
        wellbeingBuffer.append(signal)
        if wellbeingBuffer.count >= 5 {
            flushWellbeingBuffer()
        }
    }

    private func flushWellbeingBuffer() {
        let batch = wellbeingBuffer
        wellbeingBuffer = []
        Task {
            for signal in batch {
                try? await recordSessionBoundarySignal(signal: signal)
            }
        }
    }

    // MARK: - Human Review

    func requestHumanReview(contentId: String, reason: String) async throws {
        _ = try await functions.httpsCallable("requestHumanReview").call([
            "contentId": contentId,
            "reason": reason
        ])
    }

    func resolveSafetyReview(reportId: String, resolution: SafetyReviewStatus, notes: String?) async throws {
        _ = try await functions.httpsCallable("resolveSafetyReview").call([
            "reportId": reportId,
            "resolution": resolution.rawValue,
            "notes": notes as Any
        ])
    }

    // MARK: - Policy Snapshot

    func getSafetyPolicySnapshot() async throws -> [String: Any] {
        let result = try await functions.httpsCallable("getSafetyPolicySnapshot").call([:])
        return result.data as? [String: Any] ?? [:]
    }

    // MARK: - Decoders

    private func decodeSafetyDecision(from data: [String: Any]) -> SafetyDecision {
        let action = SafetyActionType(rawValue: data["action"] as? String ?? "allow") ?? .allow
        let category = (data["riskCategory"] as? String).flatMap(SafetyRiskCategory.init(rawValue:))
        let severity = (data["severity"] as? String).flatMap(SafetySeverity.init(rawValue:)) ?? .low
        return SafetyDecision(
            action: action,
            riskCategory: category,
            severity: severity,
            reason: data["reason"] as? String,
            userFacingMessage: data["userFacingMessage"] as? String,
            requiresHumanReview: data["requiresHumanReview"] as? Bool ?? false,
            appealEligible: data["appealEligible"] as? Bool ?? true,
            decidedAt: Date()
        )
    }

    private func decodeTrustedContact(from data: [String: Any], id: String) -> TrustedContact? {
        guard
            let contactUserId = data["contactUserId"] as? String,
            let displayName = data["displayName"] as? String,
            let relTypeRaw = data["relationshipType"] as? String,
            let relType = TrustedContactRelationshipType(rawValue: relTypeRaw)
        else { return nil }
        let notifLevelRaw = data["notificationLevel"] as? String ?? ""
        let notifLevel = TrustedContactNotificationLevel(rawValue: notifLevelRaw) ?? .alerts
        return TrustedContact(
            id: id,
            contactUserId: contactUserId,
            displayName: displayName,
            avatarURL: data["avatarURL"] as? String,
            relationshipType: relType,
            notificationLevel: notifLevel,
            addedAt: (data["addedAt"] as? Timestamp)?.dateValue() ?? Date()
        )
    }

    private func decodeFeedControlState(from data: [String: Any]) -> FeedControlState {
        let modeRaw = data["mode"] as? String ?? FeedMode.balanced.rawValue
        let mode = FeedMode(rawValue: modeRaw) ?? .balanced
        let blockedRaw = data["categories"] as? [String] ?? []
        let blocked = blockedRaw.compactMap(SafetyRiskCategory.init(rawValue:))
        return FeedControlState(
            activeMode: mode,
            blockedCategories: Set(blocked),
            sessionDurationLimitMinutes: data["sessionDurationMinutes"] as? Int,
            quietHoursStart: data["quietHoursStart"] as? String,
            quietHoursEnd: data["quietHoursEnd"] as? String
        )
    }

    private func decodeSessionBoundary(from data: [String: Any]) -> SessionBoundary? {
        let idStr = data["id"] as? String ?? UUID().uuidString
        let actionRaw = data["action"] as? String
        let action = actionRaw.flatMap(SessionBoundaryAction.init(rawValue:))
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
            ?? (data["triggeredAt"] as? Timestamp)?.dateValue()
            ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

        return SessionBoundary(
            id: idStr,
            uid: data["uid"] as? String ?? Auth.auth().currentUser?.uid ?? "",
            sessionId: data["sessionId"] as? String ?? "active",
            postsViewed: data["postsViewed"] as? Int ?? 0,
            scrollVelocityScore: data["scrollVelocityScore"] as? Double ?? 0,
            timeSpentSeconds: data["timeSpentSeconds"] as? Int
                ?? ((data["sessionDurationMinutes"] as? Int).map { $0 * 60 } ?? 0),
            lateNightUse: data["lateNightUse"] as? Bool ?? false,
            negativeEngagementScore: data["negativeEngagementScore"] as? Double ?? 0,
            pauseShown: data["pauseShown"] as? Bool ?? false,
            actionTaken: action,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func decodeIntegrityLabel(from data: [String: Any], contentId: String) -> ContentIntegrityLabel? {
        guard
            let typeRaw = data["labelType"] as? String,
            let labelType = IntegrityLabelType(rawValue: typeRaw)
        else { return nil }

        return ContentIntegrityLabel(
            id: data["id"] as? String ?? UUID().uuidString,
            contentId: contentId,
            contentType: data["contentType"] as? String ?? "unknown",
            labelType: labelType,
            confidence: data["confidence"] as? Double ?? 0.5,
            source: data["source"] as? String ?? "system",
            explanation: data["explanation"] as? String ?? data["claimSummary"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue()
                ?? (data["verifiedAt"] as? Timestamp)?.dateValue()
                ?? Date(),
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue()
        )
    }
}
