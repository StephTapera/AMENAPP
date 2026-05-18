//
//  SelahAISafetyPreflight.swift
//  AMENAPP
//
//  Local first-line safety gate for user-typed input flowing into the
//  Selah AI surfaces (Reflection Rewriting, Scripture Companion). The
//  server-side `BereanAPIClient.makeChatPreflight()` already performs the
//  authoritative crisis classification before any Berean Chat call. This
//  client-side gate is a defense-in-depth layer that:
//
//   * Short-circuits *before* the network call when the input clearly
//     names self-harm / suicidal intent — so we never echo crisis text
//     back through a creative-rewriting model.
//   * Returns a care-first response with concrete crisis-line guidance.
//
//  This is deliberately conservative — false positives are acceptable
//  here because the user can still proceed by editing the input. False
//  negatives (missed crisis input) are caught by the server-side check.
//

import Foundation

enum SelahAISafetyPreflight {

    /// Outcome of running the local preflight.
    enum Decision: Equatable {
        case allow
        case blockedCrisis(careMessage: String)
    }

    /// Inspect raw user input and decide whether to allow it through.
    static func evaluate(_ raw: String) -> Decision {
        let normalized = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .allow }

        // Word-boundary patterns for the highest-signal crisis terms only.
        // We intentionally keep this list short — the canonical classifier
        // lives server-side. We just want to refuse to "rewrite" suicidal
        // ideation into a poem or prayer.
        let crisisRegexes: [NSRegularExpression] = [
            try? NSRegularExpression(pattern: #"\bsuicide\b"#),
            try? NSRegularExpression(pattern: #"\bsuicidal\b"#),
            try? NSRegularExpression(pattern: #"\bkill (?:myself|me)\b"#),
            try? NSRegularExpression(pattern: #"\bend my (?:life|own life)\b"#),
            try? NSRegularExpression(pattern: #"\bself[- ]?harm\b"#),
            try? NSRegularExpression(pattern: #"\bhurt(?:ing)? myself\b"#),
            try? NSRegularExpression(pattern: #"\bcutting myself\b"#),
            try? NSRegularExpression(pattern: #"\bwant to die\b"#)
        ].compactMap { $0 }

        let range = NSRange(normalized.startIndex..., in: normalized)
        let matched = crisisRegexes.contains {
            $0.firstMatch(in: normalized, range: range) != nil
        }
        if matched {
            return .blockedCrisis(careMessage: Self.careMessage)
        }
        return .allow
    }

    /// Care-first response surfaced when the local preflight blocks.
    /// Wording aligns with the host app's crisis support patterns —
    /// gentle, non-judgmental, points at real resources.
    static let careMessage = """
    Before we go further: what you wrote sounds heavy. You're not alone, and \
    your life matters deeply. If you're in immediate danger or thinking about \
    suicide, please reach out right now:

    • United States — call or text 988 (Suicide & Crisis Lifeline)
    • United Kingdom & Ireland — call 116 123 (Samaritans)
    • International — visit findahelpline.com to find a local line

    You can also talk to someone you trust, or go to your nearest emergency room. \
    When you feel safe, come back to Selah and we'll keep walking with you.
    """
}
