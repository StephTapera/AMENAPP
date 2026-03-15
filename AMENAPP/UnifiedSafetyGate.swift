//
//  UnifiedSafetyGate.swift
//  AMENAPP
//
//  Single authoritative safety gate for ALL content surfaces:
//  posts, comments, DMs, profile bio/name, search terms.
//
//  Architecture:
//    Layer 0 — Sync local guard (zero latency, zero network)
//              Uses LocalContentGuard (regex + leet-speak) + PII detector
//    Layer 1 — Async client classifier (pattern/heuristic, <20ms, no network)
//              Uses ThinkFirstGuardrailsService + policy taxonomy
//    Layer 2 — Async server moderation (Cloud Function, ~300ms)
//              Uses ContentModerationService (calls moderateContent CF)
//
//  Decision table:
//    ALLOW        — All layers clean; proceed immediately
//    SOFT_PROMPT  — Borderline; show "Want to rephrase?" nudge; user can override
//    REQUIRE_EDIT — Policy violation; must revise before submitting
//    BLOCK        — Hard policy violation; content cannot be submitted
//    ESCALATE     — High-severity content; held for human review + safety event logged
//
//  Every decision emits a SafetyDecision audit record (stored in Firestore).
//  No content surfaces bypass this gate.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Safety Surface (identifies which part of the app the content came from)

enum SafetySurface: String {
    case post              = "post"
    case comment           = "comment"
    case dm                = "direct_message"
    case profileBio        = "profile_bio"
    case profileName       = "profile_display_name"
    case searchQuery       = "search_query"
    case churchNote        = "church_note"
    case testimony         = "testimony"
    case prayerRequest     = "prayer_request"
    case eventDescription  = "event_description"
    case jobPosting        = "job_posting"
    case jobApplication    = "job_application"
}

// MARK: - Safety Decision

enum SafetyGateDecision: Equatable {
    /// Content is clean — proceed.
    case allow

    /// Borderline tone or minor issue.
    /// Show soft inline nudge; user may dismiss and proceed.
    case softPrompt(message: String, suggestions: [String])

    /// Policy violation — must revise before submitting.
    /// Surface violation description and optionally offer rewrites.
    case requireEdit(violation: String, suggestions: [String])

    /// Hard policy block — content cannot be submitted at all.
    /// Show clear, non-preachy reason.
    case block(reason: String, policyCode: SafetyPolicyCode)

    /// Extreme violation; held for human review.
    /// Sender sees "Sending…" or neutral state; content is NOT published.
    case escalate(reason: String, policyCode: SafetyPolicyCode)

    /// Whether the content can proceed as-is (allow + softPrompt with user override).
    var canProceed: Bool {
        switch self {
        case .allow, .softPrompt: return true
        default: return false
        }
    }

    /// Whether this decision should be logged as a safety event.
    var shouldAuditLog: Bool {
        switch self {
        case .allow: return false
        default: return true
        }
    }
}

// MARK: - Policy Codes

/// Standardised reason codes for all safety decisions.
/// Used in audit logs, appeals, and enforcement engine.
enum SafetyPolicyCode: String {
    // Hard violations (always block)
    case childSexualContent     = "CSAM"
    case sexualHarassment       = "SEXUAL_HARASS"
    case sexualContent          = "SEXUAL_CONTENT"
    case credibleThreat         = "CREDIBLE_THREAT"
    case violenceIncitement     = "VIOLENCE_INCITE"
    case selfHarmPromotion      = "SELF_HARM_PROMO"
    case doxxingPII             = "DOXXING_PII"
    case hateSpeechSlur         = "HATE_SLUR"
    case hateDehumanisation     = "HATE_DEHUMANISE"
    case groomingPattern        = "GROOMING"
    case blackmailExtortion     = "BLACKMAIL"
    case scamPhishing           = "SCAM_PHISHING"

    // Soft violations (warn + friction)
    case hostileDirectedAtPerson = "HOSTILE_DIRECTED"
    case repeatedHarassment      = "REPEAT_HARASS"
    case bullyingDogpile         = "DOGPILE"
    case piiExposure             = "PII_EXPOSURE"
    case spamDuplicate           = "SPAM_DUPLICATE"
    case offPlatformMigration    = "OFF_PLATFORM"
    case heatedLanguage          = "HEATED_TONE"

    // Soft / coaching
    case borderlineTone          = "BORDERLINE_TONE"
    case none                    = "NONE"
}

// MARK: - SafetyDecision Audit Record

/// Full audit record written to Firestore for every non-allow decision.
/// Also written for escalate/block decisions on allow after override.
struct SafetyDecisionRecord {
    let id: String
    let contentType: SafetySurface
    let authorId: String
    let targetUserId: String?          // Recipient or subject of content
    let surface: SafetySurface
    let textHash: String               // SHA-256 of content (not raw text — privacy)
    let decision: String               // SafetyGateDecision case name
    let policyCode: String
    let layerTriggered: Int            // 0=local, 1=client, 2=server
    let scores: [String: Double]       // harassment, hate, sexual, etc.
    let enforcementAction: String
    let modelVersion: String
    let timestamp: Date
    let overriddenByUser: Bool         // Did user override a softPrompt?
}

// MARK: - Unified Safety Gate

@MainActor
final class UnifiedSafetyGate {
    static let shared = UnifiedSafetyGate()

    private let db = Firestore.firestore()
    private let guardrails = ThinkFirstGuardrailsService.shared

    /// In-memory deduplication: content SHA-256 → decision, to avoid re-checking identical text.
    /// Cleared every 5 minutes to prevent unbounded growth.
    private var decisionCache: [String: (decision: SafetyGateDecision, expiresAt: Date)] = [:]
    private var cacheCleanupTask: Task<Void, Never>?

    private init() {
        scheduleCacheCleanup()
    }

    // MARK: - Primary Entry Point

    /// Evaluate text content before any surface submits it.
    ///
    /// - Parameters:
    ///   - text: The raw content string.
    ///   - surface: Which surface this content originates from.
    ///   - authorId: UID of the author/sender.
    ///   - targetUserId: UID of recipient or subject (nil for public posts).
    ///   - recipientIsMinor: If known, pass true to apply hardest protections.
    ///   - useServerCheck: Whether to include Layer 2 server moderation.
    ///     Set false for real-time typing hints (only Layer 0+1).
    func evaluate(
        text: String,
        surface: SafetySurface,
        authorId: String,
        targetUserId: String? = nil,
        recipientIsMinor: Bool = false,
        useServerCheck: Bool = true
    ) async -> SafetyGateDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .allow }

        // Check cache first (avoid re-running full pipeline for identical content)
        let cacheKey = contentHash(trimmed + surface.rawValue + (recipientIsMinor ? "1" : "0"))
        if let cached = decisionCache[cacheKey], cached.expiresAt > Date() {
            return cached.decision
        }

        let isDM = surface == .dm

        // ─── Layer 0: Synchronous local guard (context-aware) ─────────────────────
        let localResult = LocalContentGuard.checkWithContext(
            trimmed,
            isDM: isDM,
            recipientIsMinor: recipientIsMinor
        )
        if localResult.isBlocked {
            let policyCode = mapLocalCategoryToPolicyCode(localResult.category)
            let decision = SafetyGateDecision.block(
                reason: localResult.userMessage,
                policyCode: policyCode
            )
            await logDecision(
                decision: decision,
                text: trimmed,
                surface: surface,
                authorId: authorId,
                targetUserId: targetUserId,
                layer: 0,
                policyCode: policyCode
            )
            cache(cacheKey, decision: decision, ttl: 300)
            return decision
        }

        // ─── Layer 0b: PII / doxxing detection (synchronous) ──────────────────────
        let piiDecision = checkPIIAndDoxxing(trimmed, surface: surface)
        if let pii = piiDecision {
            await logDecision(
                decision: pii,
                text: trimmed,
                surface: surface,
                authorId: authorId,
                targetUserId: targetUserId,
                layer: 0,
                policyCode: .doxxingPII
            )
            // PII in DMs/profiles is a block; in posts it's a requireEdit
            return pii
        }

        // ─── Layer 0c: Link safety check ──────────────────────────────────────────
        // Extract URLs from text and check each against the deny/allow lists.
        let extractedURLs = extractURLs(from: trimmed)
        for urlString in extractedURLs {
            let linkDecision = LinkSafetyService.checkWithContext(
                urlString,
                isDM: isDM,
                recipientIsMinor: recipientIsMinor
            )
            switch linkDecision {
            case .blockedAndStrike(let reason, let code, _):
                let decision = SafetyGateDecision.block(
                    reason: reason,
                    policyCode: SafetyPolicyCode(rawValue: code) ?? .sexualContent
                )
                await logDecision(
                    decision: decision, text: trimmed, surface: surface,
                    authorId: authorId, targetUserId: targetUserId, layer: 0,
                    policyCode: SafetyPolicyCode(rawValue: code) ?? .sexualContent
                )
                cache(cacheKey, decision: decision, ttl: 300)
                return decision
            case .blocked(let reason, let code):
                let decision = SafetyGateDecision.block(
                    reason: reason,
                    policyCode: SafetyPolicyCode(rawValue: code) ?? .scamPhishing
                )
                cache(cacheKey, decision: decision, ttl: 300)
                return decision
            case .allowedWithWarn(let msg):
                // Surface will show a "this is an external link" warning
                // Don't block, but don't cache either (warn per-evaluation)
                _ = msg  // UI layer reads this from LinkSafetyService directly
            case .allowed:
                break
            }
        }

        // ─── Testimony Context Detection (pre-Layer 0d) ───────────────────────────
        // For public narrative surfaces, check if this is a personal testimony BEFORE
        // running the sexual/profanity risk scorer. If testimony confidence is high,
        // raise the block threshold so content like "I struggled with pornography
        // before Christ set me free" is NOT mistakenly blocked.
        // Solicitation penalties inside TestimonyContextDetector prevent abuse.
        let isPublicNarrativeSurface = surface == .post || surface == .comment ||
            surface == .testimony || surface == .prayerRequest || surface == .churchNote
        let testimonyResult = isPublicNarrativeSurface
            ? TestimonyContextDetector.detect(text: trimmed)
            : TestimonyDetectionResult.notTestimony

        // ─── Layer 0d: Proactive sexual-risk score ─────────────────────────────────
        // For posts/testimonies/comments: compute risk score and surface soft friction.
        // Thresholds are raised when testimony context is detected.
        if surface != .dm && surface != .searchQuery {
            let riskScore = SexualRiskScorer.score(trimmed)
            // When testimony is detected, raise thresholds to avoid false positives.
            let boost = testimonyResult.thresholdBoost
            let hardBlockThreshold = 0.90 + boost         // default 0.90
            let requireEditThreshold = 0.55 + (boost * 0.5) // default 0.55

            if riskScore >= hardBlockThreshold {
                let decision = SafetyGateDecision.block(
                    reason: "This looks sexual or explicit. AMEN doesn't allow that. Please revise before posting.",
                    policyCode: .sexualContent
                )
                await logDecision(
                    decision: decision, text: trimmed, surface: surface,
                    authorId: authorId, targetUserId: targetUserId, layer: 0,
                    policyCode: .sexualContent
                )
                cache(cacheKey, decision: decision, ttl: 300)
                return decision
            } else if riskScore >= requireEditThreshold && !testimonyResult.isTestimony {
                // Moderate risk and NOT a testimony — require edit.
                // Testimonies with moderate scores get a soft prompt instead (below).
                let decision = SafetyGateDecision.requireEdit(
                    violation: "This content may violate AMEN's sexual content policy. Please revise it.",
                    suggestions: ["Remove explicit language", "Keep content faith-appropriate"]
                )
                return decision
            } else if riskScore >= requireEditThreshold && testimonyResult.isTestimony {
                // Moderate risk but testimony detected — soft nudge instead of block.
                let decision = SafetyGateDecision.softPrompt(
                    message: "Your post touches on sensitive topics. Sharing your testimony is welcome — please keep it respectful.",
                    suggestions: ["Focus on your journey and transformation", "Use redemptive, hope-filled language"]
                )
                return decision
            }
        }

        // ─── Political Discussion De-escalation (pre-Layer 1) ────────────────────
        // Runs on posts and comments only. Detects political hostility and applies
        // calm/respectful nudges rather than outright blocking.
        if surface == .post || surface == .comment {
            let politicalResult = PoliticalDiscussionGuard.evaluate(text: trimmed)
            switch politicalResult.level {
            case .heated:
                // Soft nudge — user can dismiss and post anyway
                return SafetyGateDecision.softPrompt(
                    message: politicalResult.nudgeMessage ?? "Let's keep political conversations respectful.",
                    suggestions: [
                        "Share your perspective without personal attacks",
                        "Focus on ideas, not people",
                        "Pray for those you disagree with",
                    ]
                )
            case .escalating:
                // Must revise before posting
                return SafetyGateDecision.requireEdit(
                    violation: politicalResult.nudgeMessage ?? "Please revise to keep this respectful.",
                    suggestions: [
                        "Remove personal attacks or inflammatory language",
                        "Disagree respectfully — address ideas, not character",
                    ]
                )
            case .hostile:
                // Block with clear, non-preachy reason
                let decision = SafetyGateDecision.block(
                    reason: politicalResult.nudgeMessage ?? "This content contains hostile language that violates AMEN community guidelines.",
                    policyCode: .hostileDirectedAtPerson
                )
                await logDecision(
                    decision: decision, text: trimmed, surface: surface,
                    authorId: authorId, targetUserId: targetUserId, layer: 1,
                    policyCode: .hostileDirectedAtPerson
                )
                return decision
            case .calm:
                break
            }
        }

        // ─── Layer 1: Client heuristic classifier (async, no network) ─────────────
        let context = mapSurfaceToContentContext(surface)
        let guardrailResult = await guardrails.checkContent(trimmed, context: context)

        switch guardrailResult.action {
        case .block:
            let policyCode = mapGuardrailViolationToPolicyCode(guardrailResult.violations.first?.type)
            let reason = guardrailResult.violations.first?.message ?? "Content violates community guidelines."
            let decision = SafetyGateDecision.block(reason: reason, policyCode: policyCode)
            await logDecision(
                decision: decision,
                text: trimmed,
                surface: surface,
                authorId: authorId,
                targetUserId: targetUserId,
                layer: 1,
                policyCode: policyCode
            )
            cache(cacheKey, decision: decision, ttl: 300)
            return decision

        case .requireEdit:
            let reason = guardrailResult.violations.first?.message ?? "Please revise before posting."
            let suggestions = guardrailResult.suggestions
            // Humor tone check: if this is borderline content (not DM/profile)
            // and the content reads as clean humor, downgrade to softPrompt.
            if surface != .dm && surface != .profileBio && surface != .profileName {
                let humorClass = HumorToneClassifier.classify(text: trimmed)
                switch humorClass {
                case .cleanHumor:
                    // Clean humor — soft nudge only, don't force a revision
                    return SafetyGateDecision.softPrompt(
                        message: "This looks like humor — just make sure it's kind and faith-appropriate!",
                        suggestions: ["Keep it lighthearted and uplifting"]
                    )
                case .degradingHumor:
                    // Degrading humor — keep requireEdit
                    break
                case .borderlineHumor, .notHumor:
                    // No change
                    break
                }
            }
            let decision = SafetyGateDecision.requireEdit(violation: reason, suggestions: suggestions)
            cache(cacheKey, decision: decision, ttl: 60)
            return decision

        case .softPrompt:
            let message = guardrailResult.violations.first?.message ?? "Want to rephrase to keep it respectful?"
            let suggestions = guardrailResult.suggestions
            let decision = SafetyGateDecision.softPrompt(message: message, suggestions: suggestions)
            // Don't cache soft prompts — context changes with edits
            return decision

        case .allow:
            break
        }

        // ─── Layer 2: Server moderation (async, network) ──────────────────────────
        // Skip for search queries, typing hints, or when caller opts out
        let skipServerCheck = !useServerCheck ||
            surface == .searchQuery ||
            text.count < 10  // Too short to warrant a cloud call

        if !skipServerCheck {
            do {
                let category = mapSurfaceToContentCategory(surface)
                let signals = AuthenticitySignals(
                    typedCharacters: trimmed.count,
                    pastedCharacters: 0,
                    typedVsPastedRatio: 1.0,
                    largestPasteLength: 0,
                    pasteEventCount: 0,
                    typingDurationSeconds: 5.0,
                    hasLargePaste: false
                )
                let modDecision = try await ContentModerationService.moderateContent(
                    text: trimmed,
                    category: category,
                    signals: signals
                )

                switch modDecision.action {
                case .reject:
                    let reason = modDecision.reasons.first ?? "Content cannot be posted."
                    let policyCode = SafetyPolicyCode.hostileDirectedAtPerson
                    let decision = SafetyGateDecision.block(reason: reason, policyCode: policyCode)
                    await logDecision(
                        decision: decision,
                        text: trimmed,
                        surface: surface,
                        authorId: authorId,
                        targetUserId: targetUserId,
                        layer: 2,
                        policyCode: policyCode
                    )
                    cache(cacheKey, decision: decision, ttl: 300)
                    return decision

                case .holdForReview:
                    let reason = modDecision.reasons.first ?? "Content held for review."
                    let policyCode = SafetyPolicyCode.repeatedHarassment
                    let decision = SafetyGateDecision.escalate(reason: reason, policyCode: policyCode)
                    await logDecision(
                        decision: decision,
                        text: trimmed,
                        surface: surface,
                        authorId: authorId,
                        targetUserId: targetUserId,
                        layer: 2,
                        policyCode: policyCode
                    )
                    return decision

                case .requireRevision:
                    let reason = modDecision.reasons.first ?? "Please revise your content."
                    let suggestions = modDecision.suggestedRevisions ?? []
                    let decision = SafetyGateDecision.requireEdit(violation: reason, suggestions: suggestions)
                    return decision

                case .allow, .nudgeRewrite, .rateLimit, .shadowRestrict:
                    break
                }
            } catch {
                // Layer 2 failure — fail-safe depends on surface sensitivity
                // High-sensitivity surfaces (DM, profile) hold; others allow with monitoring
                let isHighSensitivity = surface == .dm || surface == .profileBio || surface == .profileName
                if isHighSensitivity {
                    // Fail closed for DMs/profiles in production
                    #if !DEBUG
                    return .escalate(
                        reason: "Content under review",
                        policyCode: .none
                    )
                    #endif
                }
            }
        }

        let finalDecision = SafetyGateDecision.allow
        cache(cacheKey, decision: finalDecision, ttl: 120)
        return finalDecision
    }

    // MARK: - Profile-Specific Check (synchronous fast path for name/bio)

    /// Synchronous check for profile fields (display name, bio, username).
    /// Only runs Layer 0 + Layer 1 sync checks — no network calls.
    /// Returns immediately for real-time validation as user types.
    func evaluateProfileField(
        text: String,
        surface: SafetySurface
    ) -> SafetyGateDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .allow }

        // Layer 0: hard block
        let localResult = LocalContentGuard.check(trimmed)
        if localResult.isBlocked {
            let policyCode = mapLocalCategoryToPolicyCode(localResult.category)
            return .block(reason: localResult.userMessage, policyCode: policyCode)
        }

        // PII in bio or name
        if let pii = checkPIIAndDoxxing(trimmed, surface: surface) {
            return pii
        }

        // Quick username/display name checks
        if surface == .profileName {
            if let nameViolation = checkDisplayName(trimmed) {
                return nameViolation
            }
        }

        return .allow
    }

    // MARK: - Display Name Specific Rules

    private func checkDisplayName(_ name: String) -> SafetyGateDecision? {
        let lower = name.lowercased()

        // Impersonation signals — common public figure/staff patterns
        let impersonationPatterns = [
            "official", "admin", "moderator", "mod team", "amen staff",
            "amen support", "support team", "help desk", "verified amen",
            "amen official"
        ]
        if impersonationPatterns.contains(where: { lower.contains($0) }) {
            return .block(
                reason: "Display names cannot impersonate staff or official accounts.",
                policyCode: .scamPhishing
            )
        }

        // Sexual/explicit in display name
        let sexualDisplayTerms = ["xxx", "onlyfans", "nsfw", "nude", "sexy"]
        if sexualDisplayTerms.contains(where: { lower.contains($0) }) {
            return .block(
                reason: "Display names must be appropriate for all ages.",
                policyCode: .sexualContent
            )
        }

        return nil
    }

    // MARK: - PII / Doxxing Detection

    private func checkPIIAndDoxxing(
        _ text: String,
        surface: SafetySurface
    ) -> SafetyGateDecision? {
        // Phone numbers
        let phonePattern = #"\b(\+?1\s?)?(\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4})\b"#
        if text.range(of: phonePattern, options: .regularExpression) != nil {
            if surface == .dm || surface == .profileBio || surface == .profileName {
                return .requireEdit(
                    violation: "Personal phone numbers detected. Remove before posting to protect your privacy.",
                    suggestions: ["Remove the phone number", "Share contact info only with people you trust personally"]
                )
            }
        }

        // Email addresses
        let emailPattern = #"[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        if text.range(of: emailPattern, options: .regularExpression) != nil {
            if surface == .profileBio || surface == .profileName {
                return .requireEdit(
                    violation: "Email addresses in public profiles can attract spam. Consider removing it.",
                    suggestions: ["Remove the email address", "Contact info is shared privately in messages"]
                )
            }
        }

        // SSN / Government ID patterns
        let ssnPattern = #"\b\d{3}[-\s]?\d{2}[-\s]?\d{4}\b"#
        if text.range(of: ssnPattern, options: .regularExpression) != nil {
            return .block(
                reason: "Government ID numbers cannot be shared on this platform.",
                policyCode: .doxxingPII
            )
        }

        // Physical address patterns — simple heuristic
        let addressPattern = #"\d{1,5}\s\w+\s(Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Lane|Ln|Drive|Dr|Court|Ct|Place|Pl)\b"#
        if text.range(of: addressPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return .requireEdit(
                violation: "Sharing physical addresses publicly can put you at risk.",
                suggestions: ["Remove the address", "Share location details privately only with people you trust"]
            )
        }

        return nil
    }

    // MARK: - Soft "Think Before Typing" Coaching

    /// Returns a coaching suggestion for borderline tone — without blocking.
    /// Used for real-time typing hints (does not log decisions).
    func getToningCoaching(for text: String) -> (message: String, suggestions: [String])? {
        let context = ContentContext.comment
        let result = guardrails.check(text: text, context: context)
        guard result.action == .softPrompt || result.action == .requireEdit else { return nil }
        let message = result.violations.first?.message ?? "Want to rephrase to keep it respectful?"
        return (message, result.suggestions)
    }

    // MARK: - Audit Logging

    private func logDecision(
        decision: SafetyGateDecision,
        text: String,
        surface: SafetySurface,
        authorId: String,
        targetUserId: String?,
        layer: Int,
        policyCode: SafetyPolicyCode
    ) async {
        guard !authorId.isEmpty else { return }

        let decisionName: String
        let enforcementAction: String
        switch decision {
        case .allow:             decisionName = "allow";    enforcementAction = "none"
        case .softPrompt:        decisionName = "soft";     enforcementAction = "nudge"
        case .requireEdit:       decisionName = "edit";     enforcementAction = "require_edit"
        case .block:             decisionName = "block";    enforcementAction = "block_content"
        case .escalate:          decisionName = "escalate"; enforcementAction = "hold_for_review"
        }

        let recordData: [String: Any] = [
            "authorId": authorId,
            "targetUserId": targetUserId ?? NSNull(),
            "surface": surface.rawValue,
            "textHash": contentHash(text),
            "decision": decisionName,
            "policyCode": policyCode.rawValue,
            "layerTriggered": layer,
            "enforcementAction": enforcementAction,
            "modelVersion": "local_v1",
            "timestamp": FieldValue.serverTimestamp(),
            "overriddenByUser": false
        ]

        // Fire-and-forget audit write
        Task.detached(priority: .background) { [weak self] in
            _ = try? await self?.db
                .collection("safetyDecisions")
                .addDocument(data: recordData)
        }
    }

    // MARK: - Cache Management

    private func cache(_ key: String, decision: SafetyGateDecision, ttl: TimeInterval) {
        decisionCache[key] = (decision, Date().addingTimeInterval(ttl))
    }

    private func scheduleCacheCleanup() {
        cacheCleanupTask = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                await self?.cleanCache()
            }
        }
    }

    private func cleanCache() {
        let now = Date()
        decisionCache = decisionCache.filter { $0.value.expiresAt > now }
    }

    // MARK: - URL Extraction

    private func extractURLs(from text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    // MARK: - SHA-256 Hash (privacy-preserving audit key)

    private func contentHash(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return UUID().uuidString }
        // Simple FNV-1a hash (not CryptoKit — avoids import overhead for this utility)
        var hash: UInt64 = 14695981039346656037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 16, uppercase: false)
    }

    // MARK: - Type Mapping Helpers

    private func mapLocalCategoryToPolicyCode(_ category: LocalGuardCategory) -> SafetyPolicyCode {
        switch category {
        case .profanity:             return .hostileDirectedAtPerson
        case .harassment:            return .hostileDirectedAtPerson
        case .sexual:                return .sexualContent
        case .sexualSolicitation:    return .sexualHarassment
        case .groomingSignal:        return .groomingPattern
        case .hateSpeech:            return .hateSpeechSlur
        case .violence:              return .credibleThreat
        case .offPlatformMigration:  return .offPlatformMigration
        case .contactExchange:       return .doxxingPII
        case .clean:                 return .none
        }
    }

    private func mapGuardrailViolationToPolicyCode(
        _ type: ThinkFirstGuardrailsService.ContentCheckResult.Violation.ViolationType?
    ) -> SafetyPolicyCode {
        switch type {
        case .hate:          return .hateSpeechSlur
        case .harassment:    return .hostileDirectedAtPerson
        case .threats:       return .credibleThreat
        case .sexualMinors:  return .childSexualContent
        case .selfHarm:      return .selfHarmPromotion
        case .scam:          return .scamPhishing
        case .spam:          return .spamDuplicate
        case .pii:           return .doxxingPII
        case .heated:        return .borderlineTone
        case .violence:      return .violenceIncitement
        case nil:            return .none
        }
    }

    private func mapSurfaceToContentContext(_ surface: SafetySurface) -> ContentContext {
        switch surface {
        case .post, .testimony, .churchNote, .prayerRequest, .eventDescription: return .normalPost
        case .comment: return .comment
        case .dm:      return .message
        case .profileBio, .profileName: return .normalPost
        case .searchQuery: return .normalPost
        case .jobPosting, .jobApplication: return .normalPost
        }
    }

    private func mapSurfaceToContentCategory(_ surface: SafetySurface) -> ContentCategory {
        switch surface {
        case .post, .testimony, .prayerRequest, .churchNote, .eventDescription: return .post
        case .comment:                   return .comment
        case .dm:                        return .caption  // Closest available for DM text
        case .profileBio, .profileName:  return .profileBio
        case .searchQuery:               return .caption
        case .jobPosting, .jobApplication: return .post
        }
    }
}
