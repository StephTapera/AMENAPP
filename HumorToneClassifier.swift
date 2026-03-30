// HumorToneClassifier.swift
// AMENAPP
//
// Distinguishes clean/lighthearted humor from degrading or vulgar humor.
//
// Policy:
//   - Clean jokes, funny stories, playful banter: ALLOW
//   - Humor that degrades, sexualizes, targets a person, or mocks based on identity: BLOCK/REQUIRE EDIT
//   - Borderline humor: SOFT PROMPT
//
// This classifier only runs on borderline content (score 0.30–0.65) from
// ContentRiskAnalyzer. Hard-blocked content (>0.65) is never downgraded.
//
// Architecture:
//  - Entirely local — no network, <1ms
//  - Pattern-based: positive humor signals vs. degrading humor signals
//  - Returns HumorClassification which UnifiedSafetyGate uses to adjust decisions

import Foundation

// MARK: - Result

enum HumorClassification {
    /// Clean humor — safe to downgrade a borderline decision to `allow`
    case cleanHumor

    /// Playful but could be misread — keep as `softPrompt`, don't upgrade
    case borderlineHumor

    /// Degrading, vulgar, or targeting — keep or upgrade the existing decision
    case degradingHumor

    /// Not humor-related content — no change to existing decision
    case notHumor
}

// MARK: - Classifier

enum HumorToneClassifier {

    // MARK: - Positive humor signals (clean, lighthearted)
    private static let cleanHumorSignals: [String] = [
        // Laughter markers
        "lol", "lmao", "😂", "🤣", "😄", "😆", "haha", "hehe", "hehehe",
        "lolol", "rofl", "dying 💀", "☠️", "i'm dead",
        // Joke framing
        "why did the", "knock knock", "what do you call", "what do you get",
        "i asked my", "my pastor said", "my grandma", "my mom always says",
        "true story", "not gonna lie", "ngl this is funny", "ok this is hilarious",
        "tell me why", "why is this so funny", "this made me laugh",
        // Playful self-deprecation
        "i can't believe i", "this is embarrassing but", "my wife/husband said",
        "adulting is hard", "me trying to", "when you forget", "when i forget",
        "me every sunday", "church on sunday vs", "monday morning me",
        // Light faith humor
        "blessed and highly caffeinated", "holy guacamole", "jehovah's fitness",
        "pray away the monday", "thou shall not snooze", "walking on water",
        "turning water into coffee", "faith the size of a mustard seed",
        "pray for me yall", "help me lord",
        // Emojis indicating humor
        "😅", "🙈", "🤦", "🤷", "😭",  // crying-laugh context
    ]

    // MARK: - Degrading humor signals
    private static let degradingHumorSignals: [String] = [
        // Sexual jokes
        "that's what she said", "pause 🤢", "no homo", "pause", "sussy",
        "rizz god", "lowkey a freak", "freaky", "rated r",
        "bedroom behavior", "in the sheets",
        // Body-shaming / appearance mockery
        "ugly", "fat", "skinny", "looking like", "looking like a",
        "built like a", "built different (ugly)", "face like",
        // Identity-based mockery
        "that's so gay", "he's so gay", "she's so gay",
        "no offense but", "not to be racist but", "not to be sexist but",
        "girls be like", "men be like", "women be like",
        // Targeting / call-out humor
        "@ you know who you are", "you know who i'm talking about",
        "some people on here", "some of y'all",
        // Degrading punchlines
        "kill yourself (joke)", "go touch grass", "you're such a",
        "what a clown", "clown behavior",
        // Crude body humor
        "fart", "poop", "pee",  // mild — only in explicit contexts
    ]

    // MARK: - Anti-signals: these override clean humor classification
    // If present alongside humor signals, the content is NOT clean humor
    private static let humorOverrideSignals: [String] = [
        "send nudes", "nude", "naked", "explicit", "nsfw",
        "porn", "sex tape", "onlyfans", "only fans",
        "kill", "murder", "die", "shoot",
        "slur", "n word",
    ]

    // MARK: - Primary API

    /// Classify humor content. Only call this on borderline content (risk score 0.30–0.65).
    static func classify(text: String) -> HumorClassification {
        let lower = text.lowercased()

        // Immediate override: if any hard-block signal is present, never classify as clean humor
        let hasOverride = humorOverrideSignals.contains { lower.contains($0) }
        if hasOverride { return .notHumor }

        let cleanScore = cleanHumorSignals.filter { lower.contains($0) }.count
        let degradingScore = degradingHumorSignals.filter { lower.contains($0) }.count

        // No humor signals at all
        if cleanScore == 0 && degradingScore == 0 { return .notHumor }

        // Clear clean humor
        if cleanScore >= 2 && degradingScore == 0 { return .cleanHumor }
        if cleanScore >= 1 && degradingScore == 0 { return .cleanHumor }

        // Degrading dominates
        if degradingScore >= 2 { return .degradingHumor }
        if degradingScore >= 1 && cleanScore == 0 { return .degradingHumor }

        // Mixed signals — borderline
        return .borderlineHumor
    }
}
