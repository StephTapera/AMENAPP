//
//  HeyFeedNLParser.swift
//  AMENAPP
//
//  Parses user natural-language feed commands into HeyFeedParsedIntent.
//  Deterministic rules + synonym expansion. No API calls.
//  Version 1: keyword matching. Future: semantic embeddings via server.
//

import Foundation

// MARK: - Parser

@MainActor
final class HeyFeedNLParser {

    static let shared = HeyFeedNLParser()
    private init() {}

    private let version = 1

    // MARK: - Public API

    func parse(_ text: String) -> HeyFeedParsedIntent {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return fallback(original: text)
        }

        let action    = detectAction(normalized)
        let targets   = detectTargets(normalized)
        let duration  = detectDuration(normalized)
        let strength  = detectStrength(normalized)
        let conf      = computeConfidence(targets: targets, action: action)

        return HeyFeedParsedIntent(
            action: action,
            targets: targets,
            duration: duration,
            strength: strength,
            confidence: conf,
            originalText: text,
            requiresConfirmation: conf < 0.55 || targets.isEmpty,
            parserVersion: version
        )
    }

    // MARK: - Action Detection

    private func detectAction(_ text: String) -> HeyFeedNLAction {
        let increaseWords = ["more", "show me more", "give me more", "see more", "want more",
                             "increase", "prioritize", "boost", "focus on", "lot of",
                             "more of", "show more", "surface more", "keep showing",
                             "especially", "specifically more", "really want"]
        let decreaseWords = ["less", "fewer", "reduce", "cut back", "not as much", "not much",
                             "tone down", "see less", "show less", "deprioritize", "avoid",
                             "limit", "cut down on", "dial back", "not interested in",
                             "stop showing", "less of", "much less"]
        let muteWords     = ["no more", "stop", "hide", "mute", "block", "never want",
                             "don't show", "dont show", "never show", "remove all",
                             "sick of", "tired of", "enough of", "no more of"]
        let exploreWords  = ["explore", "discover", "try new", "something new",
                             "new creators", "mix it up", "variety", "different", "broaden"]
        let balanceWords  = ["balance", "reset", "rebalance", "neutral", "mix",
                             "normal", "go back to normal", "default", "clear"]

        if muteWords.contains(where: { text.contains($0) })     { return .mute }
        if increaseWords.contains(where: { text.contains($0) }) { return .increase }
        if decreaseWords.contains(where: { text.contains($0) }) { return .decrease }
        if exploreWords.contains(where: { text.contains($0) })  { return .explore }
        if balanceWords.contains(where: { text.contains($0) })  { return .balance }

        // Default: if sentence reads like a request, assume increase
        return .increase
    }

    // MARK: - Target Detection

    private func detectTargets(_ text: String) -> [HeyFeedNLTarget] {
        var found: [HeyFeedNLTarget] = []

        for rule in targetRules {
            if rule.keywords.contains(where: { text.contains($0) }) {
                let conf = min(1.0, Double(rule.keywords.filter { text.contains($0) }.count) * 0.4 + 0.55)
                found.append(HeyFeedNLTarget(
                    id: rule.id,
                    type: rule.type,
                    label: rule.label,
                    confidence: conf
                ))
            }
        }

        // Special: relationship (people I follow)
        if text.contains("people i follow") || text.contains("followed accounts") ||
           text.contains("from people i know") || text.contains("accounts i follow") {
            found.append(HeyFeedNLTarget(id: "relationship_followed", type: .relationship,
                                         label: "People you follow", confidence: 0.92))
        }
        // Special: locality
        if text.contains("nearby") || text.contains("near me") || text.contains("local") ||
           text.contains("my area") || text.contains("in my city") {
            found.append(HeyFeedNLTarget(id: "local_relevance", type: .locality,
                                         label: "Local content", confidence: 0.88))
        }
        // Special: repetition
        if text.contains("repetitive") || text.contains("same thing") || text.contains("over and over") ||
           text.contains("already seen") || text.contains("repeating") {
            found.append(HeyFeedNLTarget(id: "repetition", type: .format,
                                         label: "Repetitive content", confidence: 0.90))
        }
        // Special: intensity/heaviness
        if text.contains("intense") || text.contains("heavy") || text.contains("lighter") ||
           text.contains("calmer") || text.contains("calm") || text.contains("lighter content") {
            found.append(HeyFeedNLTarget(id: "intensity", type: .intensity,
                                         label: "Heavy/intense content", confidence: 0.85))
        }

        return found
    }

    // MARK: - Duration Detection

    private func detectDuration(_ text: String) -> HeyFeedDuration {
        if text.contains("tonight") || text.contains("right now") ||
           text.contains("just now") || text.contains("at the moment") {
            return .session
        }
        if text.contains("today") || text.contains("this afternoon") ||
           text.contains("this morning") || text.contains("this evening") {
            return .today
        }
        if text.contains("this week") || text.contains("next few days") ||
           text.contains("week") || text.contains("7 days") || text.contains("few days") {
            return .sevenDays
        }
        if text.contains("3 days") || text.contains("three days") ||
           text.contains("for a bit") || text.contains("for a while") {
            return .threeDays
        }
        if text.contains("always") || text.contains("from now on") ||
           text.contains("permanently") || text.contains("forever") {
            return .persistent
        }
        // Default: 3 days (matches Threads' default)
        return .threeDays
    }

    // MARK: - Strength Detection

    private func detectStrength(_ text: String) -> Double {
        let strong   = ["a lot", "much more", "mostly", "really", "way more", "way less",
                        "so much", "definitely", "absolutely", "all the time", "only"]
        let moderate = ["some", "a bit", "somewhat", "kind of", "a little more", "a few",
                        "occasionally", "sometimes", "when possible"]
        let soft     = ["tiny bit", "barely", "slight", "just a touch", "slightly"]

        if strong.contains(where: { text.contains($0) })   { return 0.90 }
        if moderate.contains(where: { text.contains($0) }) { return 0.55 }
        if soft.contains(where: { text.contains($0) })     { return 0.30 }
        return 0.70
    }

    // MARK: - Confidence

    private func computeConfidence(targets: [HeyFeedNLTarget], action: HeyFeedNLAction) -> Double {
        guard !targets.isEmpty else { return 0.20 }
        let avgTargetConf = targets.map(\.confidence).reduce(0, +) / Double(targets.count)
        let targetBonus   = min(0.15, Double(targets.count - 1) * 0.08)
        return min(0.97, avgTargetConf + targetBonus)
    }

    // MARK: - Fallback

    private func fallback(original: String) -> HeyFeedParsedIntent {
        HeyFeedParsedIntent(action: .balance, targets: [], duration: .threeDays,
                            strength: 0.5, confidence: 0.10, originalText: original,
                            requiresConfirmation: true, parserVersion: version)
    }

    // MARK: - Target Rules Table

    private struct TargetRule {
        let id: String
        let label: String
        let type: HeyFeedNLTargetType
        let keywords: [String]
    }

    private let targetRules: [TargetRule] = [
        TargetRule(id: "testimonies", label: "Testimonies", type: .topic,
                   keywords: ["testimon", "miracle", "story", "stories", "what god did",
                              "real stories", "what happened", "answered prayer"]),
        TargetRule(id: "prayer_requests", label: "Prayer requests", type: .topic,
                   keywords: ["prayer request", "pray for", "need prayer", "prayer",
                              "intercession", "prayer support"]),
        TargetRule(id: "bible_teaching", label: "Bible teaching", type: .topic,
                   keywords: ["bible teaching", "biblical", "teaching", "sermon", "devotional",
                              "word of god", "scripture", "preaching", "verse", "bible study",
                              "book study"]),
        TargetRule(id: "practical_faith", label: "Practical faith", type: .topic,
                   keywords: ["practical", "how to", "apply", "daily life", "faith in action",
                              "real faith", "practical advice", "everyday faith"]),
        TargetRule(id: "encouragement", label: "Encouragement", type: .topic,
                   keywords: ["encouragement", "uplifting", "hope", "positive", "inspiring",
                              "motivated", "uplift", "good news", "feel good"]),
        TargetRule(id: "church_discovery", label: "Church discovery", type: .topic,
                   keywords: ["church", "churches", "congregation", "ministry", "local church",
                              "church near", "find a church", "church community", "fellowship"]),
        TargetRule(id: "debate", label: "Debates/arguments", type: .topic,
                   keywords: ["debate", "argument", "arguments", "controversy", "controversial",
                              "politics", "political", "heated", "conflict", "fighting",
                              "drama", "drama"]),
        TargetRule(id: "promotional_content", label: "Promotional content", type: .topic,
                   keywords: ["promo", "promotional", "marketing", "advertisement", "spam",
                              "selling", "product", "church marketing", "ads"]),
        TargetRule(id: "grief_support", label: "Grief & support", type: .topic,
                   keywords: ["grief", "loss", "grieving", "mourning", "sad", "mental health",
                              "struggle", "hard time", "difficult", "support"]),
        TargetRule(id: "worship_music", label: "Worship & music", type: .topic,
                   keywords: ["worship", "music", "song", "songs", "praise", "hymn",
                              "worship song", "christian music"]),
        TargetRule(id: "theology", label: "Theology", type: .topic,
                   keywords: ["theology", "doctrine", "deep dive", "theological", "apologetics",
                              "deeper", "in-depth", "commentary"]),
        TargetRule(id: "community", label: "Community life", type: .topic,
                   keywords: ["community", "fellowship", "connection", "people", "relationships",
                              "meet people", "christian community"]),
        TargetRule(id: "tone_calm", label: "Calm content", type: .tone,
                   keywords: ["calm", "calmer", "quiet", "peaceful", "gentle", "soft", "serene",
                              "lighter", "light"]),
        TargetRule(id: "tone_encouraging", label: "Encouraging tone", type: .tone,
                   keywords: ["encouraging", "uplifting", "positive", "warm", "kind", "loving"]),
        TargetRule(id: "tone_intense", label: "Intense/heavy", type: .tone,
                   keywords: ["intense", "heavy", "serious", "deep", "hard-hitting",
                              "challenging", "convicting"]),
        TargetRule(id: "format_short", label: "Short posts", type: .format,
                   keywords: ["short", "quick", "brief", "bite-sized", "snippets", "short posts"]),
        TargetRule(id: "format_long", label: "Long-form content", type: .format,
                   keywords: ["long", "detailed", "in-depth", "long-form", "thoughtful",
                              "well-written", "thorough"]),
        TargetRule(id: "format_video", label: "Videos", type: .format,
                   keywords: ["video", "videos", "clips", "reels", "watch", "watch content"]),
        TargetRule(id: "creator_individual", label: "Individual creators", type: .creatorType,
                   keywords: ["individual", "real people", "personal", "creators",
                              "normal people", "members", "regular people"]),
        TargetRule(id: "creator_church", label: "Church accounts", type: .creatorType,
                   keywords: ["church account", "church page", "ministry account",
                              "organization", "official"]),
    ]
}
