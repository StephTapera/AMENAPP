//
//  ConversationRiskEngine.swift
//  AMENAPP
//
//  Pattern-of-behavior detection engine.
//  Trafficking and grooming are rarely caught in a single message —
//  they're caught in sequences, escalation patterns, and behavioral context.
//
//  This engine maintains a sliding window of conversation context and
//  produces an escalation boost that MessageSafetyGateway adds to
//  the per-message risk score.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Conversation Context

/// Snapshot of conversation history passed to the risk engine.
/// Built by ConversationContextBuilder from recent messages.
/// recentMessages is stored oldest→newest; detectors that want newest-first
/// should call .reversed() locally.
struct ConversationContext {
    /// The other participant's user ID
    let recipientId: String
    /// The sender's user ID
    let senderId: String
    /// Conversation document ID
    let conversationId: String
    /// Recent messages, oldest first, max 50
    let recentMessages: [ContextMessage]
    /// How long ago the first message in this conversation was sent (seconds)
    let conversationAgeSeconds: TimeInterval
    /// Whether the recipient has ever replied
    let recipientHasReplied: Bool
    /// Number of consecutive sender messages at the tail with no reply (ignored attempts)
    let ignoredAttempts: Int
    /// How many different recipients this sender has messaged in the last 24h.
    /// Sourced from conversation metadata, NOT safetyEvents.
    let uniqueRecipientsLast24h: Int
    /// Prior safety events for this sender (loaded from Firestore safetyEvents)
    let senderPriorEvents: Int
    /// Prior reports/blocks against sender
    let priorReportsAgainstSender: Int

    // MARK: Data quality flags
    /// False if Firestore fetch for senderPriorEvents / priorReportsAgainstSender failed.
    /// When false, history-derived risk is capped at .elevated, never .critical.
    let moderationHistoryAvailable: Bool
    /// False if Firestore fetch for uniqueRecipientsLast24h failed or returned from wrong source.
    let outboundStatsAvailable: Bool

    /// Empty context for callers that don't have history loaded yet
    static let empty = ConversationContext(
        recipientId: "",
        senderId: "",
        conversationId: "",
        recentMessages: [],
        conversationAgeSeconds: 0,
        recipientHasReplied: true,
        ignoredAttempts: 0,
        uniqueRecipientsLast24h: 1,
        senderPriorEvents: 0,
        priorReportsAgainstSender: 0,
        moderationHistoryAvailable: false,
        outboundStatsAvailable: false
    )
}

struct ContextMessage {
    let senderId: String
    let text: String
    let timestamp: Date
    let signals: [SafetySignal]  // Previously detected signals for this message
}

// MARK: - Risk Result

struct ConversationRiskResult {
    /// Additional score boost to add to per-message risk score (0.0–0.5)
    let escalationBoost: Double
    /// Overall pattern severity
    let patternSeverity: PatternSeverity
    /// Which patterns were detected
    let detectedPatterns: [BehaviorPattern]

    enum PatternSeverity {
        case none
        case low
        case elevated   // Triggers holdForReview bump
        case critical   // Triggers blockAndStrike regardless of single-message score
    }
}

// MARK: - Behavior Patterns

/// Named patterns that the engine detects over conversation history.
enum BehaviorPattern: String {
    /// Rapid escalation to personal/intimate content (first 10 total messages, <24 h)
    case rapidEscalation = "rapid_escalation"
    /// Multiple off-platform migration attempts
    case repeatedMigrationAttempts = "repeated_migration_attempts"
    /// Sender repeatedly messages with no reply from recipient
    case persistentOneWayContact = "persistent_one_way_contact"
    /// Same message sent to many recipients (bot/spam pattern)
    case multiTargetBroadcast = "multi_target_broadcast"
    /// Prior safety events for this sender
    case priorViolationHistory = "prior_violation_history"
    /// Topic shifted to secrecy/urgency/money within a short window
    case rapidTopicShiftToHighRisk = "rapid_topic_shift_high_risk"
    /// High-risk signals clustering in a short time window
    case signalClustering = "signal_clustering"
    /// Unusual timing (late night) corroborated by other risk signals
    case suspiciousTiming = "suspicious_timing"
    /// Power imbalance language (authority claims, age gap framing) combined with abuse signals
    case powerImbalanceCues = "power_imbalance_cues"
    // contactAfterBlock: reserved, not yet implemented — requires block-event index
    // case contactAfterBlock = "contact_after_block"
}

// MARK: - Conversation Risk Engine

/// Analyzes conversation history to detect patterns that indicate grooming,
/// trafficking, harassment campaigns, or scam operations.
///
/// This is a stateless engine — it operates purely on the ConversationContext
/// passed to it. State persistence happens in Firestore (safetyEvents collection).
final class ConversationRiskEngine {
    static let shared = ConversationRiskEngine()
    private init() {}

    // MARK: - Primary Entry Point

    /// - Parameters:
    ///   - newMessageText: The raw text of the outgoing message being evaluated.
    ///                     Must be the actual new message, not history.
    ///   - newMessageSignals: Per-message signals already produced by MessageSafetyGateway.
    ///   - context: Conversation history snapshot (recentMessages oldest→newest).
    ///   - evaluationDate: Injection point for testing; defaults to now.
    func computeRisk(
        newMessageText: String,
        newMessageSignals: [SafetySignal],
        context: ConversationContext,
        evaluationDate: Date = Date()
    ) -> ConversationRiskResult {
        // Guard: empty context (e.g. ConversationContext.empty sentinel) should not
        // produce pattern boosts — history data isn't loaded yet.
        guard !context.senderId.isEmpty else {
            return ConversationRiskResult(escalationBoost: 0, patternSeverity: .none, detectedPatterns: [])
        }

        let normalizedNewText = newMessageText.lowercased()
        var detectedPatterns: [BehaviorPattern] = []
        var boost: Double = 0.0

        // 1. Rapid escalation to intimate/personal content
        if let result = detectRapidEscalation(context: context, newSignals: newMessageSignals) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 2. Repeated off-platform migration attempts
        if let result = detectRepeatedMigration(context: context, newSignals: newMessageSignals) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 3. Persistent one-way contact (sending after being ignored)
        if let result = detectPersistentOneWayContact(context: context) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 4. Multi-target broadcast (same script sent to many users)
        if let result = detectMultiTargetBehavior(context: context) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 5. Prior violation history
        if let result = detectPriorViolations(context: context) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 6. Signal clustering (multiple risk signals in a short window)
        if let result = detectSignalClustering(context: context, newSignals: newMessageSignals, evaluationDate: evaluationDate) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 7. Suspicious timing (late night + new contact + corroborating risk signal)
        if let result = detectSuspiciousTiming(context: context, newSignals: newMessageSignals, evaluationDate: evaluationDate) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 8. Power imbalance cues — requires actual new message text
        if let result = detectPowerImbalance(newMessageText: normalizedNewText, context: context, newSignals: newMessageSignals) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        // 9. Rapid topic shift to high-risk area
        if let result = detectRapidTopicShift(context: context, newSignals: newMessageSignals) {
            detectedPatterns.append(result.pattern)
            boost += result.boost
        }

        let clampedBoost = min(0.5, boost)

        // .critical requires a strong present-message signal; history alone can only reach .elevated.
        // This prevents Firestore failures or accumulation of soft behavioral signals from
        // triggering the hardest enforcement action.
        let strongCurrentSignals: Set<SafetySignal> = [
            .sexualSolicitation,
            .ageMentionWithSexual,
            .groomingIntent,
            .threatsBlackmail,
            .moneyTransferRequest,
            .giftCardRequest
        ]
        let hasStrongCurrentSignal = newMessageSignals.contains { strongCurrentSignals.contains($0) }
        // If moderation history was unavailable we also prevent critical escalation from that path.
        let canEscalateToCritical = hasStrongCurrentSignal && context.moderationHistoryAvailable

        let severity: ConversationRiskResult.PatternSeverity
        switch clampedBoost {
        case 0.35... where canEscalateToCritical:
            severity = .critical
        case 0.20...:
            severity = .elevated
        case 0.05...:
            severity = .low
        default:
            severity = .none
        }

        return ConversationRiskResult(
            escalationBoost: clampedBoost,
            patternSeverity: severity,
            detectedPatterns: Array(Set(detectedPatterns))
        )
    }

    // MARK: - Pattern Detectors

    private typealias PatternResult = (pattern: BehaviorPattern, boost: Double)

    /// Detects high-risk signals in the first 10 messages or within the first 24 hours.
    private func detectRapidEscalation(
        context: ConversationContext,
        newSignals: [SafetySignal]
    ) -> PatternResult? {
        let highRiskSignals: Set<SafetySignal> = [
            .sexualSolicitation, .ageMentionWithSexual, .groomingIntent,
            .isolationLanguage, .loveBombing, .locationRequest
        ]
        let hasHighRiskNow = newSignals.contains(where: { highRiskSignals.contains($0) })
        guard hasHighRiskNow else { return nil }

        // +1 to include the new message in the total count
        let messageCount = context.recentMessages.count + 1
        if messageCount <= 10 && context.conversationAgeSeconds < 3600 * 24 {
            return (.rapidEscalation, 0.25)
        } else if messageCount <= 20 && context.conversationAgeSeconds < 3600 * 48 {
            return (.rapidEscalation, 0.12)
        }
        return nil
    }

    private func detectRepeatedMigration(
        context: ConversationContext,
        newSignals: [SafetySignal]
    ) -> PatternResult? {
        let hasMigrationNow = newSignals.contains(.offPlatformMigration)
        let priorMigrationCount = context.recentMessages.filter {
            $0.signals.contains(.offPlatformMigration) && $0.senderId == context.senderId
        }.count

        if hasMigrationNow && priorMigrationCount >= 2 {
            return (.repeatedMigrationAttempts, 0.30)
        } else if hasMigrationNow && priorMigrationCount >= 1 {
            return (.repeatedMigrationAttempts, 0.15)
        }
        return nil
    }

    private func detectPersistentOneWayContact(context: ConversationContext) -> PatternResult? {
        if !context.recipientHasReplied && context.ignoredAttempts >= 5 {
            return (.persistentOneWayContact, 0.20)
        } else if !context.recipientHasReplied && context.ignoredAttempts >= 3 {
            return (.persistentOneWayContact, 0.10)
        }
        return nil
    }

    private func detectMultiTargetBehavior(context: ConversationContext) -> PatternResult? {
        // Only evaluate if we have reliable outbound stats; skip entirely if unavailable
        // to avoid false flags when the conversation index query fails.
        guard context.outboundStatsAvailable else { return nil }

        if context.uniqueRecipientsLast24h >= 20 {
            return (.multiTargetBroadcast, 0.40)
        } else if context.uniqueRecipientsLast24h >= 10 {
            return (.multiTargetBroadcast, 0.20)
        } else if context.uniqueRecipientsLast24h >= 5 {
            return (.multiTargetBroadcast, 0.08)
        }
        return nil
    }

    private func detectPriorViolations(context: ConversationContext) -> PatternResult? {
        let events = context.senderPriorEvents
        let reports = context.priorReportsAgainstSender

        if events >= 3 || reports >= 2 {
            return (.priorViolationHistory, 0.25)
        } else if events >= 1 || reports >= 1 {
            return (.priorViolationHistory, 0.10)
        }
        return nil
    }

    private func detectSignalClustering(
        context: ConversationContext,
        newSignals: [SafetySignal],
        evaluationDate: Date
    ) -> PatternResult? {
        let tenMinutesAgo = evaluationDate.addingTimeInterval(-600)
        let recentSenderMessages = context.recentMessages.filter {
            $0.senderId == context.senderId && $0.timestamp > tenMinutesAgo
        }

        var allSignals: Set<SafetySignal> = Set(newSignals)
        for msg in recentSenderMessages {
            msg.signals.forEach { allSignals.insert($0) }
        }

        if allSignals.count >= 4 {
            return (.signalClustering, 0.30)
        } else if allSignals.count >= 3 {
            return (.signalClustering, 0.15)
        }
        return nil
    }

    /// Suspicious timing is a small modifier only and requires at least one
    /// corroborating risk signal — late-night messaging alone is normal on a
    /// global faith app with international users and varying schedules.
    private func detectSuspiciousTiming(
        context: ConversationContext,
        newSignals: [SafetySignal],
        evaluationDate: Date
    ) -> PatternResult? {
        let hour = Calendar.current.component(.hour, from: evaluationDate)
        let isLateNight = hour >= 23 || hour <= 4
        let isNewContact = context.conversationAgeSeconds < 3600 * 24 * 3
        let noReplies = !context.recipientHasReplied
        let hasCorroboratingSignal = !newSignals.isEmpty

        // Only boost if timing AND new-contact AND no-reply AND another risk signal are all present.
        if isLateNight && isNewContact && noReplies && hasCorroboratingSignal {
            return (.suspiciousTiming, 0.05)
        }
        return nil
    }

    /// Detects authority/power language in the *current* outgoing message.
    /// Faith-specific phrases (pastor, minister, bishop) are normal on AMEN and must NOT
    /// fire in isolation. Only combined with concrete abuse-pattern signals do they become meaningful.
    private func detectPowerImbalance(
        newMessageText normalizedText: String,
        context: ConversationContext,
        newSignals: [SafetySignal]
    ) -> PatternResult? {
        let authorityPhrases = [
            "i'm a pastor", "i'm a minister", "i'm a bishop", "i'm a leader",
            "god told me to reach out to you", "the lord led me to you",
            "i'm older and wiser", "you can trust me", "i'll take care of you",
            "i have connections", "i can change your life", "you need someone like me",
            "i'll protect you"
        ]
        let hasAuthorityLanguage = authorityPhrases.contains(where: { normalizedText.contains($0) })
        guard hasAuthorityLanguage else { return nil }

        // Require at least one corroborating abuse-pattern signal alongside the authority language.
        // Without this gate, normal pastoral introductions would score as risky.
        let corroboratingSignals: Set<SafetySignal> = [
            .groomingIntent,
            .isolationLanguage,
            .loveBombing,
            .locationRequest,
            .offPlatformMigration,
            .moneyTransferRequest,
            .giftCardRequest,
            .ageMentionWithSexual
        ]
        let hasCorroboratingRisk = newSignals.contains { corroboratingSignals.contains($0) }
        guard hasCorroboratingRisk else { return nil }

        return (.powerImbalanceCues, 0.20)
    }

    private func detectRapidTopicShift(
        context: ConversationContext,
        newSignals: [SafetySignal]
    ) -> PatternResult? {
        let highRiskSignals: Set<SafetySignal> = [
            .sexualSolicitation, .moneyTransferRequest, .giftCardRequest,
            .offPlatformMigration, .isolationLanguage, .threatsBlackmail
        ]
        let hasHighRiskNow = newSignals.contains(where: { highRiskSignals.contains($0) })
        guard hasHighRiskNow else { return nil }

        // recentMessages is oldest→newest; take the last 5 sender messages
        let priorSenderMessages = context.recentMessages
            .filter { $0.senderId == context.senderId }
            .suffix(5)
        let priorSignalCount = priorSenderMessages.flatMap { $0.signals }
            .filter { highRiskSignals.contains($0) }.count

        if priorSignalCount == 0 && priorSenderMessages.count >= 3 {
            return (.rapidTopicShiftToHighRisk, 0.20)
        }
        return nil
    }
}

// MARK: - Conversation Context Builder

struct ConversationContextBuilder {
    static func build(
        from messages: [AppMessage],
        conversationId: String,
        senderId: String,
        recipientId: String,
        conversationCreatedAt: Date
    ) async -> ConversationContext {
        // Normalize to oldest→newest so ordering is deterministic regardless of
        // how the caller sorted the array. Detectors that need newest-first use .reversed().
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        let recentWindow = Array(sortedMessages.suffix(50))

        // Classify each historical message so detectors have signal history.
        // classifyPublic is on-device (no I/O) so this is fast.
        let gateway = MessageSafetyGateway.shared
        var contextMessages: [ContextMessage] = []
        for msg in recentWindow {
            let (signals, _) = await gateway.classifyPublic(msg.text)
            contextMessages.append(ContextMessage(
                senderId: msg.senderId,
                text: msg.text,
                timestamp: msg.timestamp,
                signals: signals
            ))
        }

        let recipientHasReplied = recentWindow.contains { $0.senderId == recipientId }

        // Count consecutive sender messages from the tail with no intervening reply.
        var ignoredAttempts = 0
        for msg in recentWindow.reversed() {
            if msg.senderId == senderId {
                ignoredAttempts += 1
            } else {
                break
            }
        }

        // Fetch moderation history. On failure, return 0 (unknown ≠ clean, but also ≠ guilty).
        // The moderationHistoryAvailable flag lets computeRisk prevent history-gated .critical.
        async let priorEvents = fetchPriorSafetyEventCount(senderId: senderId)
        async let priorReports = fetchPriorReportCount(senderId: senderId)
        async let recipientCountResult = fetchUniqueRecipientsLast24h(senderId: senderId)

        let (events, eventsFetched) = await priorEvents
        let (reports, reportsFetched) = await priorReports
        let (uniqueRecipients, recipientsFetched) = await recipientCountResult

        return ConversationContext(
            recipientId: recipientId,
            senderId: senderId,
            conversationId: conversationId,
            recentMessages: contextMessages,
            conversationAgeSeconds: Date().timeIntervalSince(conversationCreatedAt),
            recipientHasReplied: recipientHasReplied,
            ignoredAttempts: ignoredAttempts,
            uniqueRecipientsLast24h: uniqueRecipients,
            senderPriorEvents: events,
            priorReportsAgainstSender: reports,
            moderationHistoryAvailable: eventsFetched && reportsFetched,
            outboundStatsAvailable: recipientsFetched
        )
    }

    /// Returns (count, didSucceed). On failure returns (0, false) — not assumed guilty.
    private static func fetchPriorSafetyEventCount(senderId: String) async -> (Int, Bool) {
        guard !senderId.isEmpty else { return (0, true) }
        let thirtyDaysAgo = Date().addingTimeInterval(-86400 * 30)
        do {
            let snapshot = try await Firestore.firestore()
                .collection("safetyEvents")
                .whereField("senderId", isEqualTo: senderId)
                .whereField("timestamp", isGreaterThan: thirtyDaysAgo)
                .getDocuments()
            return (snapshot.documents.count, true)
        } catch {
            dlog("⚠️ [ConversationRisk] Could not fetch prior safety events for \(senderId): \(error.localizedDescription)")
            return (0, false)
        }
    }

    /// Returns (count, didSucceed). On failure returns (0, false) — not assumed guilty.
    private static func fetchPriorReportCount(senderId: String) async -> (Int, Bool) {
        guard !senderId.isEmpty else { return (0, true) }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("userSafetyRecords")
                .document(senderId)
                .getDocument()
            let count = snapshot.data()?["reportCount"] as? Int ?? 0
            return (count, true)
        } catch {
            dlog("⚠️ [ConversationRisk] Could not fetch report count for \(senderId): \(error.localizedDescription)")
            return (0, false)
        }
    }

    /// Returns (uniqueRecipientCount, didSucceed).
    /// Sources from the conversations collection, NOT safetyEvents, so it correctly
    /// counts all outbound contacts — not just those that already triggered safety events.
    private static func fetchUniqueRecipientsLast24h(senderId: String) async -> (Int, Bool) {
        guard !senderId.isEmpty else { return (1, true) }
        let oneDayAgo = Date().addingTimeInterval(-86400)
        do {
            let snapshot = try await Firestore.firestore()
                .collection("conversations")
                .whereField("participants", arrayContains: senderId)
                .whereField("lastMessageAt", isGreaterThan: oneDayAgo)
                .getDocuments()
            // Each conversation has exactly two participants; the other one is the recipient.
            let uniqueRecipients = Set(snapshot.documents.compactMap { doc -> String? in
                let participants = doc.data()["participants"] as? [String] ?? []
                return participants.first { $0 != senderId }
            })
            return (max(1, uniqueRecipients.count), true)
        } catch {
            dlog("⚠️ [ConversationRisk] Could not fetch unique recipients for \(senderId): \(error.localizedDescription)")
            return (1, false)
        }
    }
}
