// PoliticalDiscussionGuard.swift
// AMENAPP
//
// De-escalation logic for political discussions on AMEN.
//
// Policy:
//   ALLOW:   Respectful opinions, prayer for leaders, civic participation, policy discussion
//   NUDGE:   First sign of heated political tone → soft prompt to stay constructive
//   REQUIRE: Escalating hostility (insults + political) → must revise before posting
//   COOLDOWN: Sustained hostile chain in a thread → 60-second reply throttle
//
// This guard does NOT silence political opinions.
// It only intervenes when political discussion becomes hostile, personal, or abusive.
//
// Architecture:
//  - `PoliticalDiscussionGuard.evaluate()` — per-message evaluation
//  - `PoliticalDiscussionGuard.evaluateThread()` — thread-level escalation detection
//  - Thread-level state is in-memory only; no Firestore writes from this layer

import Foundation

// MARK: - Result

enum PoliticalToneLevel {
    case calm           // Respectful discussion — allow
    case heated         // Political + hostile tone — soft prompt
    case escalating     // Political + personal attacks — require edit
    case hostile        // Sustained hostile thread — trigger cooldown
}

struct PoliticalGuardResult {
    let level: PoliticalToneLevel
    let nudgeMessage: String?

    var requiresIntervention: Bool { level != .calm }

    static let calm = PoliticalGuardResult(level: .calm, nudgeMessage: nil)
}

// MARK: - Guard

enum PoliticalDiscussionGuard {

    // MARK: - Political topic signals
    // Broad enough to catch most political discussions without over-triggering
    private static let politicalTopics: [String] = [
        "democrat", "republican", "liberal", "conservative", "progressive", "maga",
        "left wing", "right wing", "leftist", "rightist", "socialist", "communist",
        "trump", "biden", "obama", "election", "vote", "ballot", "congress", "senate",
        "politician", "politics", "political", "government", "policy", "immigration",
        "abortion", "gun control", "gun rights", "taxes", "welfare", "socialism",
        "capitalism", "woke", "cancel culture", "deep state", "mainstream media",
        "fake news", "propaganda", "blm", "antifa", "maga", "far left", "far right",
        "the left", "the right",
    ]

    // MARK: - Hostility signals (combined with political = intervention needed)
    private static let hostilitySignals: [String] = [
        // Personal attacks
        "you're an idiot", "you are an idiot", "you're stupid", "you are stupid",
        "you're a moron", "you are a moron", "what an idiot", "total idiot",
        "brainwashed", "brain dead", "sheep", "sheeple", "bootlicker",
        "snowflake", "triggered", "soy boy", "karen",
        // Dismissiveness / contempt
        "wake up", "do your research", "you people", "your kind",
        "go back to", "typical liberal", "typical conservative", "typical democrat",
        "typical republican", "all you people", "people like you",
        // Inflammatory framing
        "you want to destroy", "you hate america", "you hate this country",
        "communist", "fascist", "nazi",  // when used as insults
        "traitor", "enemy of", "un-american",
        // Aggressive rhetoric
        "i hope you", "deserve what", "you'll get what", "come for you",
        "should be", "need to be removed", "needs to be locked up",
    ]

    // MARK: - Calm political discussion signals (these REDUCE intervention likelihood)
    private static let respectfulPoliticalSignals: [String] = [
        "i believe", "in my opinion", "i think", "i feel",
        "praying for", "pray for our leaders", "pray for our country",
        "let's pray", "we should pray",
        "i respect", "i understand your point", "i see your perspective",
        "good point", "that's fair", "i can see why",
        "as christians", "from a biblical perspective", "scripture says",
        "love your neighbor", "love your enemy",
        "regardless of politics", "beyond politics", "above politics",
        "civility", "respectful", "productive conversation",
        "let's discuss", "i'd like to understand",
        "i disagree but", "i disagree respectfully",
    ]

    // MARK: - Primary API

    /// Evaluate a single message/post for political hostility.
    /// Returns the tone level and an appropriate intervention message.
    static func evaluate(text: String) -> PoliticalGuardResult {
        let lower = text.lowercased()

        // Quick exit: no political topic detected
        let hasPoliticalTopic = politicalTopics.contains { lower.contains($0) }
        guard hasPoliticalTopic else { return .calm }

        // Check for respectful signals — these reduce intervention
        let respectfulCount = respectfulPoliticalSignals.filter { lower.contains($0) }.count
        if respectfulCount >= 2 {
            // Two or more calm/respectful signals override mild hostility
            return .calm
        }

        // Count hostility signals
        let hostilityCount = hostilitySignals.filter { lower.contains($0) }.count

        switch hostilityCount {
        case 0:
            // Political topic but no hostility — allow
            return .calm

        case 1:
            // First sign of heated tone — soft nudge
            return PoliticalGuardResult(
                level: .heated,
                nudgeMessage: "Let's keep political conversations respectful and constructive on AMEN."
            )

        case 2:
            // Multiple hostility signals — require edit
            return PoliticalGuardResult(
                level: .escalating,
                nudgeMessage: "This message contains language that may come across as hostile. Please revise it to keep the conversation civil."
            )

        default:
            // High hostility — treat as hostile
            return PoliticalGuardResult(
                level: .hostile,
                nudgeMessage: "This content appears to be hostile. Political discussions are welcome but must remain respectful."
            )
        }
    }

    // MARK: - Thread-Level Escalation Detection

    /// Evaluate a sequence of recent comments in a thread to detect sustained escalation.
    /// - Parameter recentTexts: The last N comments in the thread (most recent last).
    /// - Returns: The aggregate thread-level tone.
    static func evaluateThread(recentTexts: [String]) -> PoliticalToneLevel {
        guard recentTexts.count >= 3 else { return .calm }

        var heatedCount = 0
        var escalatingCount = 0

        for text in recentTexts.suffix(6) { // look at last 6 messages
            let result = evaluate(text: text)
            switch result.level {
            case .heated:    heatedCount += 1
            case .escalating, .hostile: escalatingCount += 1
            case .calm: break
            }
        }

        if escalatingCount >= 2 {
            return .hostile         // 2+ escalating = trigger thread cooldown
        } else if heatedCount >= 3 {
            return .escalating      // 3+ heated = require edit on next message
        } else if heatedCount >= 1 {
            return .heated          // 1+ heated = soft prompt
        }
        return .calm
    }
}
