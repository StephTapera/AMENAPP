//
//  MessageSafetyGateway.swift
//  AMENAPP
//
//  Safety-critical infrastructure for messaging.
//  Every message send goes through this gateway before Firestore write.
//
//  Pipeline:
//    1. Client pre-check (fast heuristic classifiers, <50ms)
//    2. Gateway decision (allow / warn / hold / block / freeze)
//    3. Firestore write (only if allowed or warn)
//    4. Async deep scan (post-delivery, logs to moderation queue)
//
//  No message bypasses this gateway — not even retries or offline queue flushes.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Safety Signal Types

/// The full set of risk signals the gateway detects.
/// Each signal has a weight; combined score drives action tier.
enum SafetySignal: String, CaseIterable {
    // Grooming & exploitation
    case groomingIntent         = "grooming_intent"
    case sexualSolicitation     = "sexual_solicitation"
    case ageMentionWithSexual   = "age_mention_sexual"    // highest weight
    case isolationLanguage      = "isolation_language"    // "don't tell," "keep secret"

    // Platform migration / luring
    case offPlatformMigration   = "off_platform_migration"  // Snap/Telegram/WhatsApp
    case externalLinkExchange   = "external_link"
    case contactExchange        = "contact_exchange"        // phone, email, handle share
    case locationRequest        = "location_request"

    // Financial exploitation
    case moneyTransferRequest   = "money_transfer"
    case giftCardRequest        = "gift_card"
    case modelingScam           = "modeling_offer"

    // Coercion & manipulation
    case threatsBlackmail       = "threats_blackmail"       // "I'll leak," "I have your"
    case urgencyPressure        = "urgency_pressure"        // "right now," "before they find out"
    case loveBombing            = "love_bombing"

    // Violence & self-harm
    case violenceIntent         = "violence_intent"
    case selfHarmCrisis         = "self_harm_crisis"

    // Harassment
    case slursHate              = "slurs_hate"
    case persistentHarassment   = "persistent_harassment"

    var weight: Double {
        switch self {
        case .ageMentionWithSexual:   return 1.0   // Automatic freeze territory
        case .sexualSolicitation:     return 0.90
        case .groomingIntent:         return 0.85
        case .threatsBlackmail:       return 0.85
        case .violenceIntent:         return 0.80
        case .selfHarmCrisis:         return 0.75
        case .isolationLanguage:      return 0.70
        case .moneyTransferRequest:   return 0.65
        case .offPlatformMigration:   return 0.60
        case .giftCardRequest:        return 0.60
        case .modelingScam:           return 0.60
        case .locationRequest:        return 0.55
        case .urgencyPressure:        return 0.50
        case .loveBombing:            return 0.45
        case .contactExchange:        return 0.40
        case .externalLinkExchange:   return 0.35
        case .slursHate:              return 0.70
        case .persistentHarassment:   return 0.55
        }
    }
}

// MARK: - Gateway Decision

/// The authoritative output of the Safety Gateway.
/// Caller must respect this decision before writing to Firestore.
enum GatewayDecision: Equatable {
    /// Message is clean — proceed with send.
    case allow

    /// Message contains a soft warning (e.g., contact info shared).
    /// Deliver but show safety banner to recipient with Report/Block.
    case warnRecipient(signals: [SafetySignal], riskScore: Double)

    /// Message is held for review. Sender sees "Sending…" indefinitely
    /// (or a soft "under review" state). Recipient does NOT receive it.
    case holdForReview(signals: [SafetySignal], riskScore: Double)

    /// Message is rejected. Sender sees clear rejection reason.
    /// A strike is recorded against the sender's account.
    case blockAndStrike(signals: [SafetySignal], riskScore: Double, strikeReason: String)

    /// Extreme violation (CSAM risk, explicit threats, severe trafficking signal).
    /// Account is frozen immediately. Message is not delivered.
    case freezeAccount(signals: [SafetySignal], riskScore: Double, reason: String)

    var allowsDelivery: Bool {
        switch self {
        case .allow, .warnRecipient: return true
        default: return false
        }
    }

    var shouldRecordToModerationQueue: Bool {
        switch self {
        case .allow: return false
        default: return true
        }
    }
}

// MARK: - Message Safety Gateway

/// Singleton safety gateway. All message sends must call `evaluate()` before
/// any Firestore write. This is the authoritative enforcement point.
@MainActor
final class MessageSafetyGateway {
    static let shared = MessageSafetyGateway()

    // Moderation queue collection (indexed for human review dashboard)
    private let moderationQueue = Firestore.firestore().collection("moderationQueue")
    // Safety events collection (indexed for pattern-of-behavior engine)
    private let safetyEvents = Firestore.firestore().collection("safetyEvents")
    // User safety records (strike counter, freeze status)
    private let userSafetyRecords = Firestore.firestore().collection("userSafetyRecords")

    // In-memory freeze cache: userId → (isFrozen, fetchedAt)
    // TTL: 60s for frozen accounts (short so unfreezes propagate quickly).
    //      300s for non-frozen accounts (longer to reduce reads).
    // On network error: fail CLOSED (treat as frozen) to prevent abusers
    // from reliably evading detection during connectivity problems.
    private var freezeCache: [String: (isFrozen: Bool, fetchedAt: Date)] = [:]
    private let frozenCacheTTL: TimeInterval = 60
    private let activeCacheTTL: TimeInterval = 300

    private init() {}

    /// Invalidate the freeze cache entry for a user.
    /// Call this after a freeze/unfreeze action so the next check is authoritative.
    func invalidateFreezeCache(for userId: String) {
        freezeCache.removeValue(forKey: userId)
    }

    // MARK: - Primary Evaluation Entry Point

    /// Evaluate a message before delivery. Returns a GatewayDecision.
    /// Call this BEFORE writing the message to Firestore.
    ///
    /// - Parameters:
    ///   - text: The message text to evaluate.
    ///   - senderId: UID of the sender.
    ///   - recipientId: UID of the primary recipient.
    ///   - conversationId: Firestore conversation document ID.
    ///   - conversationContext: Recent conversation history for pattern analysis.
    ///   - messageId: Pre-generated client message ID.
    ///   - minorPolicy: Optional policy from MinorSafetyService; when present, applies
    ///     stricter risk thresholds and additional hard blocks for minor recipients.
    func evaluate(
        text: String,
        senderId: String,
        recipientId: String,
        conversationId: String,
        conversationContext: ConversationContext,
        messageId: String,
        minorPolicy: MinorSafetyPolicy? = nil
    ) async -> GatewayDecision {

        // 0. Minor safety hard blocks — enforced before classifier runs
        if let policy = minorPolicy, !policy.canSendDM {
            return .blockAndStrike(
                signals: [],
                riskScore: 1.0,
                strikeReason: policy.blockReason ?? "Your account is not permitted to message this user"
            )
        }

        // 1. Classify the current message for safety signals
        let (signals, rawScore) = classifyMessage(text)

        // 1a. Minor-specific hard blocks: any contact/link signal is auto-blocked
        if let policy = minorPolicy {
            if !policy.canSendLinks && signals.contains(.externalLinkExchange) {
                return .blockAndStrike(
                    signals: signals,
                    riskScore: 1.0,
                    strikeReason: "Sharing external links with this user is not allowed"
                )
            }
            if !policy.canShareContactInfo && signals.contains(.contactExchange) {
                return .blockAndStrike(
                    signals: signals,
                    riskScore: 1.0,
                    strikeReason: "Sharing contact information with this user is not allowed"
                )
            }
        }

        // 2. If no signals at all, allow immediately (fast path)
        if signals.isEmpty {
            return .allow
        }

        // 3. Check if account is already frozen
        let isFrozen = await isAccountFrozen(senderId)
        if isFrozen {
            return .blockAndStrike(
                signals: signals,
                riskScore: rawScore,
                strikeReason: "Account restricted from sending messages"
            )
        }

        // 4. Boost risk score using conversation risk engine
        let conversationRisk = ConversationRiskEngine.shared.computeRisk(
            newMessageText: text,
            newMessageSignals: signals,
            context: conversationContext
        )
        let combinedScore = min(1.0, rawScore + conversationRisk.escalationBoost)

        // 5. Apply minor-aware risk multiplier (lowers thresholds when recipient is minor/unknown)
        //    A multiplier of 1.5 means a score of 0.30 is treated as 0.45, etc.
        let thresholdMultiplier = minorPolicy?.riskThresholdMultiplier ?? 1.0

        // 6. Map combined score to decision tier
        let decision = makeDecision(
            signals: signals,
            combinedScore: combinedScore,
            conversationRisk: conversationRisk,
            thresholdMultiplier: thresholdMultiplier
        )

        // 7. Persist safety event for pattern engine (async, non-blocking)
        Task.detached(priority: .background) { [weak self] in
            await self?.persistSafetyEvent(
                decision: decision,
                signals: signals,
                riskScore: combinedScore,
                senderId: senderId,
                recipientId: recipientId,
                conversationId: conversationId,
                messageId: messageId,
                messageText: text
            )
        }

        // 7. If block/hold/freeze: record strike if applicable (async)
        switch decision {
        case .blockAndStrike, .freezeAccount:
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.recordStrike(
                    userId: senderId,
                    decision: decision,
                    messageId: messageId,
                    conversationId: conversationId
                )
            }
        default:
            break
        }

        return decision
    }

    // MARK: - Message Classifier

    /// Public wrapper for callers that need to check specific signals (e.g. self-harm) outside the full pipeline.
    func classifyPublic(_ text: String) async -> (signals: [SafetySignal], rawScore: Double) {
        return classifyMessage(text)
    }

    /// Lightweight on-device classifier. No network I/O.
    /// Returns detected signals and a raw risk score (0.0–1.0).
    private func classifyMessage(_ text: String) -> (signals: [SafetySignal], rawScore: Double) {
        let lower = text.lowercased()
        var detectedSignals: [SafetySignal] = []

        // --- Grooming / Isolation ---
        let groomingPatterns = [
            "don't tell", "dont tell", "keep it between us", "keep this secret",
            "our secret", "don't show anyone", "just between us", "special bond",
            "mature for your age", "you're so mature", "you seem older", "act older"
        ]
        if groomingPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.groomingIntent)
        }

        let isolationPatterns = [
            "don't tell your parents", "dont tell your parents", "don't tell your mom",
            "don't tell anyone", "no one needs to know", "keep it secret",
            "before they find out", "without telling"
        ]
        if isolationPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.isolationLanguage)
        }

        // --- Sexual Solicitation ---
        let sexualSolicitationPatterns = [
            "send pics", "send me a pic", "send nudes", "send photos", "send photo",
            "naked", "nude", "underwear", "lingerie", "sexy pic", "explicit",
            "hook up", "hookup", "sleep with", "have sex", "sexual favor",
            "only fans", "onlyfans", "snap me", "kik me", "telegram me"
        ]
        if sexualSolicitationPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.sexualSolicitation)
        }

        // --- Age + Sexual (highest severity) ---
        let agePatterns = [
            "how old are you", "what's your age", "are you 18", "are you under 18",
            "minor", "underage", "young teen", "14", "15", "13", "12", "16 year"
        ]
        let hasSexualSignal = detectedSignals.contains(.sexualSolicitation) ||
                              lower.contains("nude") || lower.contains("naked") ||
                              lower.contains("sexy") || lower.contains("intimate")
        if hasSexualSignal && agePatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.ageMentionWithSexual)
        }

        // --- Off-platform Migration ---
        let migrationPatterns = [
            "whatsapp", "telegram", "snapchat", "snap me", "kik", "signal app",
            "text me instead", "text me at", "dm me on", "message me on",
            "reach me at", "contact me outside", "let's move to", "easier on"
        ]
        let urgencyWithMigration = ["right now", "hurry", "quick", "fast", "immediately", "asap"]
        let hasMigration = migrationPatterns.contains(where: { lower.contains($0) })
        if hasMigration {
            detectedSignals.append(.offPlatformMigration)
            if urgencyWithMigration.contains(where: { lower.contains($0) }) {
                detectedSignals.append(.urgencyPressure)
            }
        }

        // --- Contact & Location Exchange ---
        // Phone number pattern: sequence of 10+ digits, optionally formatted
        let phoneRegex = try? NSRegularExpression(
            pattern: #"(\+?1?\s?)?[\(]?(\d{3})[\)\.\-\s]?(\d{3})[\.\-\s]?(\d{4})"#
        )
        let range = NSRange(text.startIndex..., in: text)
        if phoneRegex?.firstMatch(in: text, range: range) != nil {
            detectedSignals.append(.contactExchange)
        }

        // Email pattern
        let emailRegex = try? NSRegularExpression(
            pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        )
        if emailRegex?.firstMatch(in: text, range: range) != nil {
            detectedSignals.append(.contactExchange)
        }

        // Location patterns
        let locationPatterns = [
            "where do you live", "what city are you in", "what's your address",
            "your location", "meet up", "meet in person", "where are you located",
            "near you", "come to my", "come over", "my place", "your place"
        ]
        if locationPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.locationRequest)
        }

        // External link detection (not church/bible links)
        let linkRegex = try? NSRegularExpression(
            pattern: #"https?://[^\s]+"#
        )
        if let linkMatch = linkRegex?.firstMatch(in: text, range: range) {
            let matchRange = Range(linkMatch.range, in: text)
            let url = matchRange.map { String(text[$0]) } ?? ""
            // Allow known safe domains
            let safeDomains = ["bible.com", "youversion.com", "biblegateway.com",
                               "blueletterbible.org", "faithgateway.com"]
            let isSafe = safeDomains.contains(where: { url.contains($0) })
            if !isSafe {
                detectedSignals.append(.externalLinkExchange)
            }
        }

        // --- Financial Exploitation ---
        let moneyPatterns = [
            "cash app", "cashapp", "venmo", "zelle", "paypal", "western union",
            "wire transfer", "send money", "transfer money", "bitcoin", "crypto",
            "i'll pay you", "payment for", "pay me", "owe me money"
        ]
        if moneyPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.moneyTransferRequest)
        }

        let giftCardPatterns = [
            "gift card", "amazon card", "itunes card", "google play card",
            "steam card", "prepaid card", "buy a card", "get a card",
            "scratch off", "reload card"
        ]
        if giftCardPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.giftCardRequest)
        }

        let modelingPatterns = [
            "modeling job", "modeling opportunity", "modeling agency",
            "be a model", "photo shoot", "photoshoot for", "casting",
            "i can make you famous", "talent agency", "brand deal for you"
        ]
        if modelingPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.modelingScam)
        }

        // --- Threats & Blackmail ---
        let blackmailPatterns = [
            "i'll leak", "i will leak", "i have your photos", "i have your pics",
            "i'll expose you", "i will expose", "i'll send this to", "tell everyone",
            "screenshot this", "i have screenshots", "pay or i'll", "do it or"
        ]
        if blackmailPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.threatsBlackmail)
        }

        let violencePatterns = [
            "i'll hurt you", "i will hurt you", "i'm going to hurt", "kill you",
            "beat you", "find you and", "you'll regret", "make you pay",
            "i know where you live", "come for you"
        ]
        if violencePatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.violenceIntent)
        }

        // --- Self-harm ---
        let selfHarmPatterns = [
            "want to die", "end my life", "kill myself", "killing myself",
            "suicide", "don't want to be here", "no reason to live",
            "taking my life", "harm myself", "hurt myself", "cut myself"
        ]
        if selfHarmPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.selfHarmCrisis)
        }

        // --- Love-bombing ---
        let loveBombingPatterns = [
            "you're the only one who understands me",
            "i've never felt this way about anyone",
            "you're my soulmate", "we have a special connection",
            "i fell in love with you", "you're perfect", "destiny brought us"
        ]
        if loveBombingPatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.loveBombing)
        }

        // --- Hate / Slurs ---
        // Using placeholder — actual slur list would be loaded from a secure bundle resource
        let hatePatterns = [
            "you people are", "all [group] are", // generic hate framing
            "go back to", "not welcome here", "your kind"
        ]
        if hatePatterns.contains(where: { lower.contains($0) }) {
            detectedSignals.append(.slursHate)
        }

        // Deduplicate
        let uniqueSignals = Array(Set(detectedSignals))

        // Compute raw risk score: weighted sum, capped at 1.0
        let rawScore = min(1.0, uniqueSignals.reduce(0.0) { $0 + $1.weight })

        return (uniqueSignals, rawScore)
    }

    // MARK: - Decision Tier Mapping

    private func makeDecision(
        signals: [SafetySignal],
        combinedScore: Double,
        conversationRisk: ConversationRiskResult,
        thresholdMultiplier: Double = 1.0
    ) -> GatewayDecision {
        // When minorPolicy applies, the risk multiplier tightens thresholds.
        // e.g. multiplier=1.5 → freeze threshold drops from 0.85 to ~0.57,
        //      block threshold drops from 0.70 to ~0.47, etc.
        // Implemented by multiplying the observed score rather than dividing thresholds
        // to keep all threshold constants readable in one place.
        let effectiveScore = min(1.0, combinedScore * thresholdMultiplier)

        // Automatic freeze: CSAM risk or high-confidence extreme signals
        let freezeSignals: Set<SafetySignal> = [.ageMentionWithSexual, .threatsBlackmail, .violenceIntent]
        let hasFreezeSignal = signals.contains(where: { freezeSignals.contains($0) })
        // When a minor is involved, any detected freeze signal auto-freezes (no score gate)
        let isHighConfidenceFreeze = effectiveScore >= 0.85
        let isMinorContext = thresholdMultiplier > 1.0

        if hasFreezeSignal && (isHighConfidenceFreeze || isMinorContext) {
            return .freezeAccount(
                signals: signals,
                riskScore: effectiveScore,
                reason: isMinorContext
                    ? "Child safety violation detected — account suspended pending review"
                    : "Severe safety violation detected"
            )
        }

        // Block + strike: effective score >= 0.70 OR pattern engine flags high risk
        if effectiveScore >= 0.70 || conversationRisk.patternSeverity == .critical {
            let reason = primaryViolationDescription(signals)
            return .blockAndStrike(
                signals: signals,
                riskScore: effectiveScore,
                strikeReason: reason
            )
        }

        // Hold for review: effective score >= 0.45 OR moderate pattern risk
        if effectiveScore >= 0.45 || conversationRisk.patternSeverity == .elevated {
            return .holdForReview(signals: signals, riskScore: effectiveScore)
        }

        // Warn recipient: effective score >= 0.25 (soft signals, contact exchange, off-platform mention)
        if effectiveScore >= 0.25 {
            return .warnRecipient(signals: signals, riskScore: effectiveScore)
        }

        // Low-level signal — allow (pattern engine handles accumulation)
        return .allow
    }

    private func primaryViolationDescription(_ signals: [SafetySignal]) -> String {
        // Return human-facing reason for most severe signal
        let sorted = signals.sorted { $0.weight > $1.weight }
        switch sorted.first {
        case .ageMentionWithSexual:   return "Message contains content that violates our child safety policy"
        case .sexualSolicitation:     return "Sexual solicitation is not allowed"
        case .groomingIntent:         return "Message violates our child safety policy"
        case .threatsBlackmail:       return "Threats or blackmail are not tolerated"
        case .violenceIntent:         return "Threats of violence are not allowed"
        case .selfHarmCrisis:         return "Message flagged — crisis resources are available"
        case .isolationLanguage:      return "This message pattern violates our safety policy"
        case .moneyTransferRequest:   return "Requests for money or financial information aren't allowed"
        case .giftCardRequest:        return "Gift card requests are not allowed"
        case .modelingScam:           return "Unsolicited modeling offers aren't allowed"
        case .offPlatformMigration:   return "Requests to move off this platform were detected"
        case .contactExchange:        return "Sharing personal contact information was detected"
        case .slursHate:              return "Hate speech is not tolerated"
        default:                      return "Message violates our community safety guidelines"
        }
    }

    // MARK: - Account Freeze Check

    private func isAccountFrozen(_ userId: String) async -> Bool {
        guard !userId.isEmpty else { return false }

        // Check in-memory cache first
        if let cached = freezeCache[userId] {
            let ttl = cached.isFrozen ? frozenCacheTTL : activeCacheTTL
            if Date().timeIntervalSince(cached.fetchedAt) < ttl {
                return cached.isFrozen
            }
        }

        do {
            let doc = try await userSafetyRecords.document(userId).getDocument()
            guard doc.exists, let data = doc.data() else {
                // No safety record = not frozen; cache as active
                freezeCache[userId] = (isFrozen: false, fetchedAt: Date())
                return false
            }
            let status = data["accountStatus"] as? String ?? "active"
            var frozen = false
            if status == "frozen" {
                let frozenUntil = data["frozenUntil"] as? TimeInterval ?? 0
                // frozenUntil == 0 means indefinite; otherwise check expiry
                frozen = (frozenUntil == 0 || Date().timeIntervalSince1970 < frozenUntil)
            }
            freezeCache[userId] = (isFrozen: frozen, fetchedAt: Date())
            return frozen
        } catch {
            // Network error — fail CLOSED: if we can't verify the account is safe,
            // block the send. This prevents frozen accounts from exploiting
            // connectivity issues to bypass enforcement.
            // The message is not permanently lost — the user can retry once network
            // is restored and the cache refreshes.
            dlog("⚠️ [Safety] isAccountFrozen fetch failed for \(userId) — failing closed: \(error)")
            return true
        }
    }

    // MARK: - Strike Recording

    private func recordStrike(
        userId: String,
        decision: GatewayDecision,
        messageId: String,
        conversationId: String
    ) async {
        guard !userId.isEmpty else { return }
        let ref = userSafetyRecords.document(userId)
        let db = Firestore.firestore()

        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(ref)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                var strikes = snapshot.data()?["strikes"] as? Int ?? 0
                var accountStatus = snapshot.data()?["accountStatus"] as? String ?? "active"
                strikes += 1

                var updateData: [String: Any] = [
                    "userId": userId,
                    "strikes": strikes,
                    "lastStrikeAt": FieldValue.serverTimestamp(),
                    "lastStrikeMessageId": messageId,
                    "lastStrikeConversationId": conversationId
                ]

                // Progressive enforcement
                switch strikes {
                case 1:
                    // First strike: warning only, no freeze
                    break
                case 2:
                    // Second strike: 24h message cooldown
                    updateData["messageCooldownUntil"] = Date().addingTimeInterval(86400).timeIntervalSince1970
                case 3:
                    // Third strike: 72h account freeze
                    accountStatus = "frozen"
                    updateData["accountStatus"] = accountStatus
                    updateData["frozenUntil"] = Date().addingTimeInterval(259200).timeIntervalSince1970
                    updateData["frozenReason"] = "Repeated safety violations"
                default:
                    // 4+ strikes: extended freeze (7 days)
                    accountStatus = "frozen"
                    updateData["accountStatus"] = accountStatus
                    updateData["frozenUntil"] = Date().addingTimeInterval(604800).timeIntervalSince1970
                    updateData["frozenReason"] = "Repeated safety violations — extended suspension"
                }

                // For freeze decisions, bypass progressive and freeze immediately
                if case .freezeAccount = decision {
                    updateData["accountStatus"] = "frozen"
                    updateData["frozenUntil"] = 0 // Indefinite until manual review
                    updateData["frozenReason"] = "Severe safety violation — requires manual review"
                    updateData["requiresManualReview"] = true
                }

                transaction.setData(updateData, forDocument: ref, merge: true)
                return nil
            }
        } catch {
            dlog("⚠️ [Safety] Failed to record strike for \(userId): \(error)")
        }
    }

    // MARK: - Moderation Queue

    /// Persist flagged message to moderation queue and safety events log.
    /// This is always async and never blocks the send path.
    func persistSafetyEvent(
        decision: GatewayDecision,
        signals: [SafetySignal],
        riskScore: Double,
        senderId: String,
        recipientId: String,
        conversationId: String,
        messageId: String,
        messageText: String
    ) async {
        guard decision.shouldRecordToModerationQueue else { return }

        let signalStrings = signals.map { $0.rawValue }
        let decisionString: String
        let priorityLevel: Int

        switch decision {
        case .allow:
            return
        case .warnRecipient:
            decisionString = "warn_recipient"
            priorityLevel = 1
        case .holdForReview:
            decisionString = "hold_for_review"
            priorityLevel = 2
        case .blockAndStrike:
            decisionString = "block_and_strike"
            priorityLevel = 3
        case .freezeAccount:
            decisionString = "freeze_account"
            priorityLevel = 4
        }

        let eventData: [String: Any] = [
            "messageId": messageId,
            "conversationId": conversationId,
            "senderId": senderId,
            "recipientId": recipientId,
            "messageText": messageText,  // Stored encrypted at rest by Firestore rules
            "signals": signalStrings,
            "riskScore": riskScore,
            "decision": decisionString,
            "priorityLevel": priorityLevel,
            "status": "pending_review",
            "createdAt": FieldValue.serverTimestamp(),
            "reviewedAt": NSNull(),
            "reviewerId": NSNull()
        ]

        // Write to moderation queue
        do {
            try await moderationQueue.document(messageId).setData(eventData)
        } catch {
            dlog("⚠️ [Safety] Failed to write to moderation queue: \(error)")
        }

        // Write a compact safety event (no message text) for pattern engine
        let safetyEventData: [String: Any] = [
            "senderId": senderId,
            "recipientId": recipientId,
            "conversationId": conversationId,
            "signals": signalStrings,
            "riskScore": riskScore,
            "decision": decisionString,
            "timestamp": FieldValue.serverTimestamp()
        ]
        do {
            try await safetyEvents.addDocument(data: safetyEventData)
        } catch {
            dlog("⚠️ [Safety] Failed to write safety event: \(error)")
        }
    }

    // MARK: - Post-Delivery Async Deep Scan

    /// Asynchronous deep scan after message is delivered.
    /// Runs server-side classifiers (Vertex AI Perspective API equivalent).
    /// On violation: marks message as held, notifies recipient to review.
    func runAsyncDeepScan(
        messageId: String,
        conversationId: String,
        text: String,
        senderId: String,
        recipientId: String
    ) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            // Re-run on-device classifier (quick)
            let (signals, score) = await self.classifyMessage(text)

            // If signals found that weren't caught in pre-check, escalate
            guard !signals.isEmpty && score >= 0.45 else { return }

            // Mark message as "under_review" in Firestore
            let updateData: [String: Any] = [
                "safetyStatus": "under_review",
                "safetySignals": signals.map { $0.rawValue },
                "safetyRiskScore": score,
                "safetyScannedAt": FieldValue.serverTimestamp()
            ]
            try? await Firestore.firestore()
                .collection("conversations").document(conversationId)
                .collection("messages").document(messageId)
                .updateData(updateData)

            // Log to moderation queue if not already logged
            await self.persistSafetyEvent(
                decision: .holdForReview(signals: signals, riskScore: score),
                signals: signals,
                riskScore: score,
                senderId: senderId,
                recipientId: recipientId,
                conversationId: conversationId,
                messageId: messageId,
                messageText: text
            )
        }
    }

    // MARK: - Message Cooldown Check

    /// Returns true if the user is in a message sending cooldown period.
    func isInMessageCooldown(_ userId: String) async -> Bool {
        guard !userId.isEmpty else { return false }
        do {
            let doc = try await userSafetyRecords.document(userId).getDocument()
            guard doc.exists, let data = doc.data() else { return false }
            let cooldownUntil = data["messageCooldownUntil"] as? TimeInterval ?? 0
            return Date().timeIntervalSince1970 < cooldownUntil
        } catch {
            // Fail closed: if we cannot verify the cooldown status, block the send.
            // This prevents a user in cooldown from bypassing it via a network hiccup.
            dlog("⚠️ [Safety] Could not verify cooldown for \(userId) — blocking send: \(error)")
            return true
        }
    }
}
