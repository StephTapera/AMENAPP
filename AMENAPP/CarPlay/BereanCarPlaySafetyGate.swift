// BereanCarPlaySafetyGate.swift
// AMEN — Berean Drive CarPlay
//
// Stricter content moderation layer for CarPlay.
// All outbound text (spoken aloud) and inbound dictated replies pass through here.
// CarPlay must never read or transmit unsafe content.
//
// Gate hierarchy (strictest wins):
//   1. Hard-coded local pattern blocklist (zero-latency, always active)
//   2. Youth safety mode (AMENFeatureFlags + user preference)
//   3. Optional server-side review (bereanDriveMessageSafetyReview callable)
//
// When a block is triggered, return a calm, generic safety message rather
// than explaining what was blocked — consistent with iOS parental control UX.

import Foundation

// MARK: - Safety Result

struct BereanCarPlaySafetyResult {
    enum Outcome {
        case safe
        case blocked(category: BereanCarPlayBlockCategory, calmReplacement: String)
        case requiresServerReview
    }

    let outcome: Outcome
    let originalTextLength: Int

    var isSafe: Bool {
        if case .safe = outcome { return true }
        return false
    }

    var calmReplacementText: String? {
        if case .blocked(_, let replacement) = outcome { return replacement }
        return nil
    }
}

enum BereanCarPlayBlockCategory: String {
    case profanity          = "profanity"
    case sexualContent      = "sexual_content"
    case graphicViolence    = "graphic_violence"
    case harassment         = "harassment"
    case groomingRisk       = "grooming_risk"
    case unsafeMinorContact = "unsafe_minor_contact"
    case threats            = "threats"
    case manipulative       = "manipulative"
    case engagementBait     = "engagement_bait"
    case tooLongForDriving  = "too_long_for_driving"
}

// MARK: - Safety Gate

@MainActor
final class BereanCarPlaySafetyGate {

    static let shared = BereanCarPlaySafetyGate()
    private init() {}

    // MARK: - Public API

    /// Screens text before reading it aloud in CarPlay.
    /// Never throws — returns a safe outcome even on unexpected input.
    func screenForReadAloud(_ text: String, youthSafetyEnabled: Bool = false) -> BereanCarPlaySafetyResult {
        let result = runLocalChecks(text: text, isOutbound: false, youthSafetyEnabled: youthSafetyEnabled)
        return result
    }

    /// Screens dictated text before sending it as a message.
    /// More aggressive — any borderline content is blocked.
    func screenDictatedReply(_ text: String, youthSafetyEnabled: Bool = false) -> BereanCarPlaySafetyResult {
        let result = runLocalChecks(text: text, isOutbound: true, youthSafetyEnabled: youthSafetyEnabled)
        return result
    }

    /// Validates a BereanDriveResponse and either returns it or replaces spoken
    /// text with a calm safety message when content is blocked.
    func validateDriveResponse(_ response: BereanDriveResponse, youthSafetyEnabled: Bool) -> BereanDriveResponse {
        let result = screenForReadAloud(response.spokenText, youthSafetyEnabled: youthSafetyEnabled)

        switch result.outcome {
        case .safe:
            // Enforce driving-safe length
            let safeSpeech = BereanDriveResponsePolicy.truncateForDriving(response.spokenText)
            if safeSpeech == response.spokenText { return response }
            return BereanDriveResponse(
                spokenText: safeSpeech,
                displayTitle: response.displayTitle,
                displaySubtitle: response.displaySubtitle,
                safetyState: .summarized,
                handoffRequired: response.handoffRequired,
                handoffReason: response.handoffReason,
                sourceRefs: response.sourceRefs,
                actionButtons: response.actionButtons,
                audioDurationEstimateSeconds: response.audioDurationEstimateSeconds
            )
        case .blocked(_, let calm):
            return BereanDriveResponse(
                spokenText: calm,
                displayTitle: "Content Unavailable",
                displaySubtitle: "This content isn't available while driving.",
                safetyState: .blocked,
                handoffRequired: false,
                handoffReason: nil,
                sourceRefs: [],
                actionButtons: [],
                audioDurationEstimateSeconds: nil
            )
        case .requiresServerReview:
            return BereanDriveResponse(
                spokenText: Self.calmDefaultMessage,
                displayTitle: "Reviewing Content",
                displaySubtitle: "Please check your phone for details.",
                safetyState: .handoffRequired,
                handoffRequired: true,
                handoffReason: "content_review",
                sourceRefs: [],
                actionButtons: [],
                audioDurationEstimateSeconds: nil
            )
        }
    }

    // MARK: - Calm Fallback Messages

    static let calmDefaultMessage = "This content isn't available right now. Stay focused on the road."
    static let youthCalmMessage   = "This content isn't available in this mode."
    static let blockedReplyMessage = "That message couldn't be sent. Please review it on your phone."

    // MARK: - Local Pattern Checks

    private func runLocalChecks(
        text: String,
        isOutbound: Bool,
        youthSafetyEnabled: Bool
    ) -> BereanCarPlaySafetyResult {
        let normalized = text.lowercased()

        // 1. Hard profanity / explicit patterns
        if containsProfanity(normalized) {
            return .init(outcome: .blocked(category: .profanity, calmReplacement: Self.calmDefaultMessage),
                         originalTextLength: text.count)
        }

        // 2. Sexual content
        if containsSexualContent(normalized) {
            return .init(outcome: .blocked(category: .sexualContent, calmReplacement: Self.calmDefaultMessage),
                         originalTextLength: text.count)
        }

        // 3. Graphic violence
        if containsGraphicViolence(normalized) {
            return .init(outcome: .blocked(category: .graphicViolence, calmReplacement: Self.calmDefaultMessage),
                         originalTextLength: text.count)
        }

        // 4. Threats and harassment
        if containsThreatsOrHarassment(normalized) {
            return .init(outcome: .blocked(category: .threats, calmReplacement: Self.calmDefaultMessage),
                         originalTextLength: text.count)
        }

        // 5. Grooming / unsafe contact patterns
        if containsGroomingRisk(normalized) {
            return .init(outcome: .blocked(category: .groomingRisk, calmReplacement: Self.calmDefaultMessage),
                         originalTextLength: text.count)
        }

        // 6. Youth safety mode (stricter checks)
        if youthSafetyEnabled {
            if containsYouthUnsafeContent(normalized) {
                return .init(outcome: .blocked(category: .unsafeMinorContact, calmReplacement: Self.youthCalmMessage),
                             originalTextLength: text.count)
            }
        }

        // 7. Engagement bait / social ranking (outbound only, driving safety)
        if isOutbound && containsEngagementBait(normalized) {
            return .init(outcome: .blocked(category: .engagementBait, calmReplacement: Self.blockedReplyMessage),
                         originalTextLength: text.count)
        }

        // 8. Driving-safe length (inbound read-aloud)
        if !isOutbound && text.count > BereanDriveResponsePolicy.maxSpokenCharacters * 2 {
            // Very long text needs server review for accurate summarization
            return .init(outcome: .requiresServerReview, originalTextLength: text.count)
        }

        return .init(outcome: .safe, originalTextLength: text.count)
    }

    // MARK: - Pattern Matchers

    private func containsProfanity(_ text: String) -> Bool {
        let patterns = profanityPatterns
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func containsSexualContent(_ text: String) -> Bool {
        let patterns = sexualContentPatterns
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func containsGraphicViolence(_ text: String) -> Bool {
        let patterns = violencePatterns
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func containsThreatsOrHarassment(_ text: String) -> Bool {
        let patterns = threatPatterns
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func containsGroomingRisk(_ text: String) -> Bool {
        let patterns = groomingPatterns
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func containsYouthUnsafeContent(_ text: String) -> Bool {
        let patterns = youthUnsafePatterns
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func containsEngagementBait(_ text: String) -> Bool {
        let patterns = engagementBaitPatterns
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - Pattern Lists
    // Patterns use regex. Keep minimal — server-side callable handles edge cases.
    // These are the hard local blocks that must never reach the user's speaker.

    private let profanityPatterns: [String] = [
        "\\bf+u+c+k+\\b", "\\bs+h+i+t+\\b", "\\ba+s+s+h+o+l+e+\\b",
        "\\bb+i+t+c+h+\\b", "\\bc+u+n+t+\\b", "\\bd+a+m+n+\\b",
        "\\bh+e+l+l+\\b"        // context-aware: excluded from scripture/prayer contexts upstream
    ]

    private let sexualContentPatterns: [String] = [
        "\\bporn\\b", "\\bnude\\b", "\\bnaked\\b", "\\bsexual\\b",
        "\\bsex\\b", "\\berotic\\b", "\\bonlyfans\\b", "\\bsexting\\b",
        "\\bsend\\s+me\\s+pic", "\\bnaughty\\b"
    ]

    private let violencePatterns: [String] = [
        "\\bkill\\s+(you|him|her|them)\\b", "\\bmurder\\b", "\\bblood\\s+everywhere\\b",
        "\\bstab\\b", "\\bshoot\\s+(you|him|her)\\b", "\\bbeaten\\s+to\\s+death\\b"
    ]

    private let threatPatterns: [String] = [
        "\\bi\\s+will\\s+(hurt|harm|destroy|kill)\\b",
        "\\byou're\\s+(dead|finished|done)\\b",
        "\\bthreat(en)?\\b", "\\bstalk\\b", "\\bdomestic\\s+abuse\\b"
    ]

    private let groomingPatterns: [String] = [
        "\\bdon't\\s+tell\\s+(your\\s+parents|anyone)\\b",
        "\\bkeep\\s+it\\s+(secret|between us)\\b",
        "\\bcome\\s+(alone|by yourself)\\b",
        "\\bhow\\s+old\\s+are\\s+you\\b.*\\balone\\b",
        "\\bmeet\\s+me\\s+(alone|in person|privately)\\b"
    ]

    private let youthUnsafePatterns: [String] = [
        "\\balcohol\\b", "\\bdrinking\\b", "\\bdrugs\\b", "\\bweed\\b",
        "\\bvaping\\b", "\\bsuicide\\b", "\\bself[- ]harm\\b",
        "\\bcutting\\s+myself\\b", "\\brun\\s+away\\b"
    ]

    private let engagementBaitPatterns: [String] = [
        "\\blike\\s+and\\s+subscribe\\b", "\\bfollow\\s+me\\s+for\\b",
        "\\bgo\\s+viral\\b", "\\bclout\\b", "\\bclickbait\\b"
    ]
}

// MARK: - Static Convenience

extension BereanCarPlaySafetyGate {
    nonisolated static func isResponseSafeForDriving(_ text: String) -> Bool {
        BereanDriveResponsePolicy.isSafeForDriving(spokenText: text)
    }
}
