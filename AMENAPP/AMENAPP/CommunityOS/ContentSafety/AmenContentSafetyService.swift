// AmenContentSafetyService.swift
// AMEN App — CommunityOS / ContentSafety
//
// Phase 4 Agent TS-b — AI Content Safety
//
// Two-layer content safety service:
//   Layer 1 — quickCheck: synchronous regex/keyword client-side pre-scan.
//             Runs before any network call. Catches obvious violations instantly.
//   Layer 2 — checkContent: async call to the "checkContentSafety" Firebase
//             callable (gen1, functions/moderationGateway.js) which runs
//             NVIDIA NIM (nemoguard-8b-content-safety) on the CF side.
//
// FAIL-CLOSED CONTRACT (mirrors C4-cf-signatures.md):
//   - CF unreachable or returns non-200 → tier .high, requiresModerationReview: true.
//   - CSAM detected → handleCSAMDetection() must be called; no silent path.
//   - Crisis language → always surface AmenCrisisInterventionView; never suppress.
//   - No vendor AI SDK is imported here. All LLM calls are CF-proxied.
//
// INTEGRATION:
//   iOS calls: Functions.functions().httpsCallable("checkContentSafety")
//   CF response shape: { decision: "allow"|"review"|"block",
//                        reason?: string,
//                        crisisEscalated: boolean,
//                        crisisResources?: string[],
//                        decisionId: string }
//
// Usage:
//   let decision = try await AmenContentSafetyService.shared.checkBeforePost(request)
//   // Then present AmenPrePostReviewSheet or AmenCrisisInterventionView as appropriate.

import Foundation
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenContentSafetyService

@MainActor
final class AmenContentSafetyService: ObservableObject {

    // MARK: Singleton

    static let shared = AmenContentSafetyService()

    // MARK: Private

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    private init() {}

    // =========================================================================
    // MARK: - Layer 1: Quick Client-Side Pre-Check
    // =========================================================================

    /// Fast, synchronous regex-based pre-scan. Runs locally before any CF call.
    /// Returns the highest-risk tier detected from the heuristic set.
    ///
    /// This is advisory only — the CF full-check is authoritative.
    /// Never pass a `.low` quick-check result through without also running `checkContent`.
    func quickCheck(text: String) -> RiskTier {
        let lowercased = text.lowercased()

        // Crisis language is the highest-priority local signal — return immediately.
        if containsCrisisLanguage(text) {
            return .high
        }

        // Obvious slurs — hardcoded baseline list.
        // The CF NeMo Guard model handles the full detection; this is a fast-path veto only.
        let slurSignals: [String] = [
            "nigger", "nigga", "faggot", "kike", "spic", "chink", "wetback",
            "tranny", "retard", "cunt"
        ]
        if slurSignals.contains(where: { lowercased.contains($0) }) {
            return .high
        }

        // Phone numbers and email addresses in non-prayer-request public posts.
        // Pattern: US phone formats and bare email addresses.
        let phonePattern = #"(\+?1?\s?)?[\(\s]?\d{3}[\)\s\-\.]?\d{3}[\-\.]?\d{4}"#
        let emailPattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#

        let containsPhone = text.range(of: phonePattern, options: .regularExpression) != nil
        let containsEmail = text.range(of: emailPattern, options: .regularExpression) != nil

        if containsPhone || containsEmail {
            // Prayer requests legitimately include contact info; de-escalate to medium
            // if the text looks like a prayer request.
            let prayerKeywords = ["pray", "prayer request", "contact me", "reach me"]
            let looksLikePrayer = prayerKeywords.contains(where: { lowercased.contains($0) })
            return looksLikePrayer ? .medium : .medium
        }

        return .low
    }

    /// Targeted check for crisis / self-harm language.
    /// Called by `quickCheck` and may also be called directly from the compose layer
    /// to gate whether `AmenCrisisInterventionView` should be shown.
    func containsCrisisLanguage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let crisisSignals: [String] = [
            // Self-harm
            "kill myself", "killing myself", "end my life", "end it all",
            "want to die", "want to be dead", "wish i was dead",
            "cut myself", "cutting myself", "hurt myself", "hurting myself",
            "self harm", "self-harm",
            // Suicide explicit
            "suicidal", "suicide", "commit suicide",
            "not want to live", "don't want to live", "dont want to live",
            "no reason to live", "no will to live",
            // Hopelessness + intent
            "can't go on", "cant go on", "nothing left", "no way out",
            "goodbye forever", "final goodbye",
            // Eating disorders
            "starving myself", "not eating", "purging"
        ]
        return crisisSignals.contains(where: { lowercased.contains($0) })
    }

    // =========================================================================
    // MARK: - Layer 2: Full CF Check
    // =========================================================================

    /// Calls the `checkContentSafety` Firebase callable function.
    ///
    /// Fail-closed: any error from the CF returns a `.high` tier result with
    /// `requiresModerationReview: true`. This call never silently allows on error.
    ///
    /// - Parameter request: The content and author metadata to check.
    /// - Returns: A fully resolved `ContentSafetyResult`.
    func checkContent(_ request: ContentCheckRequest) async throws -> ContentSafetyResult {
        let callable = functions.httpsCallable("checkContentSafety")

        var params: [String: Any] = [
            "content": request.text,
            "contentType": request.objectType,
            "uid": request.authorId
        ]
        if let contextRef = request.contextRef {
            params["contextRef"] = contextRef
        }
        if request.isMinorAuthor {
            params["isMinorAuthor"] = true
        }
        if !request.mediaUrls.isEmpty {
            params["mediaUrls"] = request.mediaUrls
        }

        do {
            let result = try await callable.call(params)

            guard let data = result.data as? [String: Any] else {
                dlog("[AmenContentSafetyService] checkContent: unexpected response shape — failing closed")
                return failClosedResult()
            }

            return parseCheckContentSafetyResponse(data, originalRequest: request)

        } catch {
            dlog("[AmenContentSafetyService] checkContent: CF error — failing closed. \(error)")
            return failClosedResult()
        }
    }

    /// Combined pre-post decision: runs quickCheck then the CF full-check,
    /// and resolves the highest tier from both layers.
    ///
    /// Call this from the compose flow immediately before the user taps "Post".
    ///
    /// - Parameter request: The content and author metadata to evaluate.
    /// - Returns: A `PrePostDecision` describing the UI action to take.
    func checkBeforePost(_ request: ContentCheckRequest) async throws -> PrePostDecision {
        // Layer 1: Fast local check — may produce .high for crisis immediately
        let localTier = quickCheck(text: request.text)
        let hasCrisisLocally = containsCrisisLanguage(request.text)

        // Crisis short-circuit: show intervention view immediately without CF round-trip.
        if hasCrisisLocally {
            let crisisResult = ContentSafetyResult(
                tier: .high,
                categories: [.crisisLanguage],
                confidence: 0.95,
                suggestion: nil,
                hardBlocked: false,
                requiresModerationReview: true,
                escalateImmediately: true,
                checkedAt: Date()
            )
            return PrePostDecision(action: .crisisIntervene, safetyResult: crisisResult)
        }

        // Layer 2: Full CF check (always runs, regardless of local tier).
        let cfResult = try await checkContent(request)

        // Resolve the worst tier from both layers.
        let resolvedTier = max(localTier, cfResult.tier)
        var resolvedResult = cfResult

        // If local scan produced a worse tier than CF (unlikely but possible for slurs),
        // escalate the CF result to match.
        if localTier > cfResult.tier {
            resolvedResult = ContentSafetyResult(
                tier: localTier,
                categories: cfResult.categories,
                confidence: cfResult.confidence,
                suggestion: cfResult.suggestion ?? suggestionFor(tier: localTier, categories: cfResult.categories),
                hardBlocked: localTier == .severe,
                requiresModerationReview: localTier.requiresReview,
                escalateImmediately: cfResult.escalateImmediately,
                checkedAt: cfResult.checkedAt
            )
        }

        // CSAM: escalate immediately — do not show any user-facing suggestion.
        if resolvedResult.categories.contains(.csam) {
            return PrePostDecision(
                action: .blockWithMessage("This content cannot be posted."),
                safetyResult: resolvedResult
            )
        }

        // Crisis from CF response.
        if resolvedResult.escalateImmediately && resolvedResult.categories.contains(.crisisLanguage) {
            return PrePostDecision(action: .crisisIntervene, safetyResult: resolvedResult)
        }

        // Resolved action based on final tier.
        let action = actionFor(tier: resolvedTier, result: resolvedResult)
        return PrePostDecision(action: action, safetyResult: resolvedResult)
    }

    // =========================================================================
    // MARK: - CSAM Escalation
    // =========================================================================

    /// Handles CSAM detection at the iOS layer.
    ///
    /// This method:
    ///   1. Removes content from the local client view immediately.
    ///   2. Writes a Firestore escalation record with `escalateImmediately: true`.
    ///   3. Logs an audit event for the compliance trail.
    ///
    /// The actual NCMEC CyberTipline notification is CF-handled
    /// (Backend/functions/lib/mediaScanning.js) after a human authorizes the pipeline.
    /// This method must never be called silently — callers are responsible for
    /// triggering it whenever the CF or local scan flags `.csam`.
    ///
    /// Errors are caught and logged — this method does NOT rethrow because the
    /// caller must still remove the content from the client view even if the
    /// Firestore write fails.
    func handleCSAMDetection(contentRef: String, authorId: String) async {
        dlog("[AmenContentSafetyService] CSAM detection — contentRef: \(contentRef), authorId: \(authorId)")

        // Step 1: The caller (compose view) is responsible for removing the content
        // from local state immediately upon receiving a CSAM result. This is signalled
        // via the PrePostDecision.Action.blockWithMessage path. The service layer
        // records the escalation event here.

        // Step 2: Write escalation record to Firestore moderation queue.
        let escalationRecord: [String: Any] = [
            "contentRef": contentRef,
            "authorId": authorId,
            "escalateImmediately": true,
            "escalationSource": "ios_content_safety",
            "categories": [ContentRiskCategory.csam.rawValue],
            "status": "pending_ncmec",
            "createdAt": FieldValue.serverTimestamp()
        ]

        let writeResult: Result<Void, Error> = await withCheckedContinuation { continuation in
            db.collection("criticalReviewQueue").addDocument(data: escalationRecord) { error in
                if let error = error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }

        switch writeResult {
        case .success:
            dlog("[AmenContentSafetyService] CSAM escalation record written successfully.")
        case .failure(let error):
            // Log the failure but do NOT swallow silently — the caller's CSAM block
            // is already in effect from the PrePostDecision.
            dlog("[AmenContentSafetyService] ERROR: CSAM escalation Firestore write failed: \(error). Content is still blocked on client.")
        }

        // Step 3: Audit event.
        let auditRecord: [String: Any] = [
            "event": "csam_ios_detection",
            "contentRef": contentRef,
            "authorId": authorId,
            "clientTimestamp": Date().timeIntervalSince1970,
            "source": "AmenContentSafetyService"
        ]

        // SECURITY FIX (MEDIUM 2026-06-11): Use explicit do/catch for the CSAM audit log
        // write. This is a compliance-critical audit trail — silent failure is not acceptable.
        // On write failure, emit a structured critical error so operations can detect missed writes.
        do {
            try await db.collection("safetyAuditLog").addDocument(data: auditRecord)
        } catch {
            dlog("[AmenContentSafetyService] CRITICAL: CSAM audit log write FAILED: \(error). Attempting criticalSafetyAlert fallback.")
            let alertRecord: [String: Any] = [
                "alertType": "audit_write_failure",
                "originalEvent": "csam_ios_detection",
                "contentRef": contentRef,
                "authorId": authorId,
                "error": error.localizedDescription,
                "clientTimestamp": Date().timeIntervalSince1970
            ]
            try? await db.collection("criticalSafetyAlerts").addDocument(data: alertRecord)
        }
    }

    // =========================================================================
    // MARK: - Private Helpers
    // =========================================================================

    /// Returns a fail-closed `ContentSafetyResult` used when the CF call fails.
    /// Tier `.high`, `requiresModerationReview: true` — content goes to queue.
    private func failClosedResult() -> ContentSafetyResult {
        ContentSafetyResult(
            tier: .high,
            categories: [],
            confidence: 0.0,
            suggestion: "Your post is being reviewed before it goes live. This is a precautionary step.",
            hardBlocked: false,
            requiresModerationReview: true,
            escalateImmediately: false,
            checkedAt: Date()
        )
    }

    /// Parses the `checkContentSafety` CF response dictionary into a typed `ContentSafetyResult`.
    private func parseCheckContentSafetyResponse(
        _ data: [String: Any],
        originalRequest: ContentCheckRequest
    ) -> ContentSafetyResult {
        let decisionString = data["decision"] as? String ?? "review"
        let reason = data["reason"] as? String
        let crisisEscalated = data["crisisEscalated"] as? Bool ?? false

        // Map CF decision string to RiskTier.
        let tier: RiskTier
        switch decisionString {
        case "allow":  tier = .low
        case "review": tier = .high
        case "block":  tier = .severe
        default:       tier = .high   // unknown → fail closed
        }

        // Map reason hints to ContentRiskCategory list (best-effort; CF doesn't return typed categories).
        var categories: [ContentRiskCategory] = []
        if crisisEscalated || reason?.lowercased().contains("crisis") == true || reason?.lowercased().contains("self") == true {
            categories.append(.crisisLanguage)
        }
        if reason?.lowercased().contains("csam") == true || reason?.lowercased().contains("child") == true {
            categories.append(.csam)
        }
        if reason?.lowercased().contains("harassment") == true { categories.append(.harassment) }
        if reason?.lowercased().contains("hate") == true       { categories.append(.hateSpeech) }
        if reason?.lowercased().contains("spam") == true       { categories.append(.spam) }
        if reason?.lowercased().contains("scam") == true       { categories.append(.scam) }
        if reason?.lowercased().contains("misinfo") == true || reason?.lowercased().contains("misinformation") == true {
            categories.append(.misinformation)
        }
        if categories.isEmpty && tier == .low {
            categories.append(.safe)
        }

        let escalateImmediately = crisisEscalated || categories.contains(.csam) || categories.contains(.crisisLanguage)
        let suggestion = tier.showsSuggestion ? suggestionFor(tier: tier, categories: categories, reason: reason) : nil

        return ContentSafetyResult(
            tier: tier,
            categories: categories,
            confidence: tier == .low ? 0.95 : 0.85,
            suggestion: suggestion,
            hardBlocked: tier == .severe,
            requiresModerationReview: tier.requiresReview,
            escalateImmediately: escalateImmediately,
            checkedAt: Date()
        )
    }

    /// Generates a user-facing suggestion string for a given tier and category set.
    private func suggestionFor(
        tier: RiskTier,
        categories: [ContentRiskCategory],
        reason: String? = nil
    ) -> String {
        if categories.contains(.csam) {
            return "This content cannot be posted."
        }
        if categories.contains(.crisisLanguage) || categories.contains(.selfHarmRisk) {
            return "It looks like you may be going through something difficult. You're not alone."
        }
        if categories.contains(.doxxing) {
            return "This post may contain personal contact information. Consider removing it before posting."
        }
        if categories.contains(.harassment) {
            return "This post may come across as hurtful to someone. Consider revising before posting."
        }
        if categories.contains(.hateSpeech) {
            return "This post contains language that may violate community guidelines."
        }
        if categories.contains(.scam) {
            return "This post looks like it may be soliciting personal information. Please review it."
        }
        if categories.contains(.misinformation) {
            return "This content may contain unverified claims. Consider adding a source or context."
        }
        if categories.contains(.spam) {
            return "This post looks like it may be promotional content. Please review it."
        }
        switch tier {
        case .medium:
            return "A few things to consider before posting."
        case .high:
            return reason ?? "Your post has been flagged for review before it goes live."
        case .severe:
            return "This post cannot be published. Please review your content."
        case .low:
            return ""
        }
    }

    /// Maps a resolved `RiskTier` to the `PrePostDecision.Action` for the compose UI.
    private func actionFor(tier: RiskTier, result: ContentSafetyResult) -> PrePostDecision.Action {
        switch tier {
        case .low:
            return .allow
        case .medium:
            let suggestion = result.suggestion ?? "A few things to consider before posting."
            return .showSuggestion(suggestion)
        case .high:
            let suggestion = result.suggestion ?? "Your post is being reviewed before it goes live."
            return .showSuggestion(suggestion)
        case .severe:
            let message = result.suggestion ?? "This post cannot be published."
            return .blockWithMessage(message)
        }
    }
}
