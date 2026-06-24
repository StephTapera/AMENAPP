// CommentModerationService.swift
// AMENAPP — Smart Comments Wave 2
//
// Layered moderation pipeline for Smart Comments.
//
// SPINE INVARIANT: A comment is NEVER publicly visible until
//   moderationStatus == .allowed AND visibilityStatus == .public.
//   Fail-closed: if this service is unavailable, the comment stays pendingReview / hidden.
//
// Pipeline:
//   Stage 1 — On-device pre-check (sync, instant, local heuristics)
//   Stage 2 — Server-side AI moderation (async, calls callModelCommentCoach)
//   Stage 3 — Full pipeline (runs 1→2; short-circuits on Stage 1 hit)
//
// Crisis special handling (selfHarm / childSafety):
//   NOT blocked — the comment posts; the AUTHOR sees CommentCrisisHandlerView privately.
//   Never surface method content. Never tell the author "your comment was flagged as dangerous."
//
// Audit log: UserDefaults (Firestore persistence is a backend deploy TODO).
// Sensitive categories (selfHarm, childSafety) set encryptedAtRest: true.

import Foundation
import FirebaseAuth

@MainActor
final class CommentModerationService: ObservableObject {

    static let shared = CommentModerationService()
    private init() {}

    // Notification name emitted when a crisis comment is detected.
    // Payload: ["commentId": String, "category": ModerationCategory.rawValue]
    static let crisisDetectedNotification = Notification.Name("CommentModerationCrisisDetected")

    // MARK: - Stage 1: On-Device Pre-Check

    /// Synchronous, instant local heuristics. Returns the first matching category, or nil if clean.
    /// This is a fast-fail guard — it is NOT a replacement for the server pipeline.
    func onDeviceCheck(_ body: String) -> ModerationCategory? {
        let lower = body.lowercased()

        // Doxxing: explicit phone/email patterns
        let phonePattern = try? NSRegularExpression(
            pattern: #"(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}"#
        )
        let emailPattern = try? NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        )
        let range = NSRange(body.startIndex..., in: body)
        if phonePattern?.firstMatch(in: body, range: range) != nil {
            return .doxxing
        }
        if emailPattern?.firstMatch(in: body, range: range) != nil {
            return .doxxing
        }

        // Crisis / self-harm keywords — do NOT block; caller uses isCrisis() to route support
        let crisisKeywords = [
            "suicide", "kill myself", "end my life", "harm myself",
            "want to die", "don't want to be here", "take my own life"
        ]
        for keyword in crisisKeywords where lower.contains(keyword) {
            return .selfHarm
        }

        // Spam patterns
        let urlCount = countURLs(in: body)
        if urlCount >= 5 {
            return .spam
        }
        let spamPhrases = ["buy now", "click here", "limited offer", "free money", "act now"]
        for phrase in spamPhrases where lower.contains(phrase) {
            return .spam
        }

        return nil
    }

    // MARK: - Stage 2: Server-Side AI Moderation

    /// Calls the existing SmartCommentService coaching callable and maps the result to a
    /// CommentModerationResult. Fail-closed: unavailability returns .pendingReview (not .allowed).
    func serverModerate(commentId: String, body: String) async -> CommentModerationResult {
        let now = Date().timeIntervalSince1970

        do {
            let coachResult = try await SmartCommentService.shared.reviewComment(
                commentText: body,
                postContext: nil
            )

            let status: CommentModerationStatus
            switch coachResult.action {
            case .block:  status = .blocked
            case .nudge:  status = .limited
            case .publish: status = .allowed
            }

            return CommentModerationResult(
                id: UUID().uuidString,
                targetId: commentId,
                targetType: "comment",
                status: status,
                category: nil,
                confidence: 0.85,
                source: .serverAI,
                reviewedAt: now,
                reviewedBy: nil
            )
        } catch {
            // Fail-closed: any error → pendingReview (never silently allow)
            return CommentModerationResult(
                id: UUID().uuidString,
                targetId: commentId,
                targetType: "comment",
                status: .pendingReview,
                category: nil,
                confidence: 0.0,
                source: .serverAI,
                reviewedAt: now,
                reviewedBy: nil
            )
        }
    }

    // MARK: - Stage 3: Full Pipeline

    /// Runs Stage 1 then Stage 2. Short-circuits to .blocked if Stage 1 fires (except crisis —
    /// see crisis special handling below). When the flag is OFF, returns .allowed immediately
    /// (preserves existing behavior; the server pipeline still runs independently).
    func moderate(commentId: String, body: String) async -> CommentModerationResult {
        let now = Date().timeIntervalSince1970

        // ── C-Wave-5: GUARDIAN pre-publish gate (PP-I1). Runs regardless of the comment
        //    pipeline flag; hook 0 (child-safety) always enforces, hooks 1–3 obey the
        //    guardian flag. A non-committable verdict blocks the comment write.
        let guardianVerdict = await GuardianPrePublishGate.shared.gate(
            surface: .comment,
            contentRef: commentId,
            text: body
        )
        if !guardianVerdict.mayCommit {
            return CommentModerationResult(
                id: UUID().uuidString,
                targetId: commentId,
                targetType: "comment",
                status: .blocked,
                category: .childSafety,
                confidence: 1.0,
                source: .onDevice,
                reviewedAt: now,
                reviewedBy: nil
            )
        }

        // Feature flag guard — when OFF, preserve existing behavior
        guard AMENFeatureFlags.shared.commentModerationPipelineEnabled else {
            return CommentModerationResult(
                id: UUID().uuidString,
                targetId: commentId,
                targetType: "comment",
                status: .allowed,
                category: nil,
                confidence: 1.0,
                source: .onDevice,
                reviewedAt: now,
                reviewedBy: nil
            )
        }

        // Stage 1: on-device pre-check
        if let onDeviceCategory = onDeviceCheck(body) {
            let result = CommentModerationResult(
                id: UUID().uuidString,
                targetId: commentId,
                targetType: "comment",
                status: onDeviceCategory == .selfHarm ? .allowed : .blocked,
                category: onDeviceCategory,
                confidence: 0.95,
                source: .onDevice,
                reviewedAt: now,
                reviewedBy: nil
            )

            // Log and emit crisis notification if needed
            if isCrisis(result) {
                emitCrisisNotification(commentId: commentId, category: onDeviceCategory)
            }

            logAudit(CommentModerationAuditLog(
                id: UUID().uuidString,
                targetId: commentId,
                action: onDeviceCategory == .selfHarm ? .published : .flagged,
                reason: onDeviceCategory.rawValue,
                actorType: .system,
                actorId: nil,
                timestamp: now,
                encryptedAtRest: onDeviceCategory == .selfHarm || onDeviceCategory == .childSafety
            ))

            return result
        }

        // Stage 2: server-side AI moderation
        let serverResult = await serverModerate(commentId: commentId, body: body)

        logAudit(CommentModerationAuditLog(
            id: UUID().uuidString,
            targetId: commentId,
            action: serverResult.status == .allowed ? .approved : .flagged,
            reason: serverResult.category?.rawValue,
            actorType: .system,
            actorId: nil,
            timestamp: now,
            encryptedAtRest: false
        ))

        return serverResult
    }

    // MARK: - Audit Log

    /// Persists an audit log entry to UserDefaults locally.
    /// Sensitive categories (selfHarm, childSafety) set encryptedAtRest: true.
    /// Firestore persistence is a backend deploy TODO — the local log ensures nothing is lost.
    func logAudit(_ log: CommentModerationAuditLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        let key = "commentModerationAuditLog_\(log.id)"
        UserDefaults.standard.set(data, forKey: key)
        // Append ID to the index so the log can be enumerated
        var index = auditLogIndex()
        index.append(log.id)
        UserDefaults.standard.set(index, forKey: "commentModerationAuditLogIndex")
    }

    // MARK: - Crisis Detection

    /// Returns true when the moderation result indicates a crisis category that warrants
    /// showing supportive resources to the author.
    func isCrisis(_ result: CommentModerationResult) -> Bool {
        guard let category = result.category else { return false }
        return category == .selfHarm || category == .childSafety
    }

    // MARK: - Private Helpers

    private func countURLs(in text: String) -> Int {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.numberOfMatches(in: text, range: range) ?? 0
    }

    private func auditLogIndex() -> [String] {
        UserDefaults.standard.stringArray(forKey: "commentModerationAuditLogIndex") ?? []
    }

    private func emitCrisisNotification(commentId: String, category: ModerationCategory) {
        NotificationCenter.default.post(
            name: CommentModerationService.crisisDetectedNotification,
            object: nil,
            userInfo: [
                "commentId": commentId,
                "category": category.rawValue
            ]
        )
    }
}
