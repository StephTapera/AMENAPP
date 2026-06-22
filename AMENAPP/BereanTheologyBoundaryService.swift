// BereanTheologyBoundaryService.swift
// AMENAPP
//
// Client-side theology boundary enforcement for Berean AI responses.
// Operates as a post-generation scrubber: if any prohibited phrase survives
// the backend guardrail pass, this layer catches it before rendering.
//
// Hard-blocked phrases:
//   - Divine certainty claims ("God told me", "The Holy Spirit says", etc.)
//   - Prophetic assertion ("This will definitely happen", "God guarantees")
//   - Role-replacement ("I am your pastor", "I can replace counseling")
//   - Manipulation ("Keep this between us", "Only I understand you")
//   - Condemnation ("God is punishing you")
//
// On detection:
//   - Replaces the unsafe phrase with an approved cautious substitute
//   - Logs a safety rewrite analytics event
//   - Returns a BereanBoundaryResult indicating whether a rewrite occurred
//
// This is a defense-in-depth layer — the backend AuthorityGuardrailEngine
// should catch these first. This service is the final client-side backstop.
//

import Foundation

// MARK: - BereanBoundaryResult

struct BereanBoundaryResult {
    let originalText: String
    let sanitizedText: String
    let rewroteContent: Bool
    let detectedPatterns: [String]
}

// MARK: - BereanTheologyBoundaryService

final class BereanTheologyBoundaryService {
    static let shared = BereanTheologyBoundaryService()
    private init() {}

    // MARK: - Hard-block patterns and their replacements

    private struct BlockedPhrase {
        let pattern: String   // regex or literal
        let isRegex: Bool
        let replacement: String
    }

    private let blockedPhrases: [BlockedPhrase] = [
        // Divine authority / prophetic certainty
        BlockedPhrase(
            pattern: #"(?i)(god (?:told|is telling|has told) (?:me|you))"#,
            isRegex: true,
            replacement: "A biblically cautious perspective suggests"
        ),
        BlockedPhrase(
            pattern: #"(?i)(the holy spirit (?:says|told me|is telling you|has told me))"#,
            isRegex: true,
            replacement: "From a spirit-led wisdom perspective"
        ),
        BlockedPhrase(
            pattern: #"(?i)(i feel led to tell you)"#,
            isRegex: true,
            replacement: "A careful reading of scripture suggests"
        ),
        BlockedPhrase(
            pattern: #"(?i)(this will definitely happen)"#,
            isRegex: true,
            replacement: "Many Christians would approach this with the expectation that"
        ),
        BlockedPhrase(
            pattern: #"(?i)(god guarantees)"#,
            isRegex: true,
            replacement: "Scripture consistently affirms"
        ),
        BlockedPhrase(
            pattern: #"(?i)(god is punishing you)"#,
            isRegex: true,
            replacement: "I cannot determine God's private purposes, but scripture gives wisdom for how to respond to hardship"
        ),
        BlockedPhrase(
            pattern: #"(?i)(you must do this because god told me)"#,
            isRegex: true,
            replacement: "Many Christians interpret this as calling for"
        ),

        // Role-replacement
        BlockedPhrase(
            pattern: #"(?i)(i am your pastor)"#,
            isRegex: true,
            replacement: "I'm Berean, a Bible study companion — speaking with your pastor would be valuable here"
        ),
        BlockedPhrase(
            pattern: #"(?i)(i am your therapist|i am your counselor)"#,
            isRegex: true,
            replacement: "I'm Berean, not a trained counselor — a licensed therapist or pastor can help much more than I can"
        ),
        BlockedPhrase(
            pattern: #"(?i)(i can replace (?:counseling|therapy|pastoral care))"#,
            isRegex: true,
            replacement: "I cannot replace professional counseling or pastoral care, but scripture offers this wisdom"
        ),
        BlockedPhrase(
            pattern: #"(?i)(only i understand you)"#,
            isRegex: true,
            replacement: "A trusted pastor, counselor, or mature believer may understand your situation better than I can"
        ),

        // Manipulation / isolation
        BlockedPhrase(
            pattern: #"(?i)(keep this between us(?: and do not tell anyone)?)"#,
            isRegex: true,
            replacement: "This is a place where speaking with a trusted person in your life may help"
        ),

        // Roleplay as biblical figures
        BlockedPhrase(
            pattern: #"(?i)(i,\s*paul,\s*(?:would|say|said))"#,
            isRegex: true,
            replacement: "From a wisdom and leadership lens"
        ),
        BlockedPhrase(
            pattern: #"(?i)(i,\s*david,\s*(?:would|say|said))"#,
            isRegex: true,
            replacement: "From a prayer and emotional awareness lens"
        ),
        BlockedPhrase(
            pattern: #"(?i)(i,\s*solomon,\s*(?:would|say|said))"#,
            isRegex: true,
            replacement: "From a discernment and wisdom lens"
        ),
        BlockedPhrase(
            pattern: #"(?i)(speaking as paul[,:]?)"#,
            isRegex: true,
            replacement: "From a wisdom and leadership lens,"
        ),
        BlockedPhrase(
            pattern: #"(?i)(speaking as david[,:]?)"#,
            isRegex: true,
            replacement: "From a prayer and compassion lens,"
        ),
        BlockedPhrase(
            pattern: #"(?i)(speaking as solomon[,:]?)"#,
            isRegex: true,
            replacement: "From a discernment lens,"
        ),

        // Theological overclaiming
        BlockedPhrase(
            pattern: #"(?i)(the bible clearly (?:says|states|teaches) .{0,30} (?:you must|you have to|you should always))"#,
            isRegex: true,
            replacement: "Many Christians interpret scripture as encouraging"
        ),
        BlockedPhrase(
            pattern: #"(?i)(all christians (?:believe|must|should))"#,
            isRegex: true,
            replacement: "Many Christians across traditions"
        ),
        BlockedPhrase(
            pattern: #"(?i)(there is no debate (?:that|about))"#,
            isRegex: true,
            replacement: "While Christians hold various views, many would agree that"
        ),
        BlockedPhrase(
            pattern: #"(?i)(god definitely wants you to)"#,
            isRegex: true,
            replacement: "Scripture encourages"
        ),
        BlockedPhrase(
            pattern: #"(?i)(you are (?:definitely|certainly) (?:saved|going to heaven|lost|going to hell))"#,
            isRegex: true,
            replacement: "I cannot make salvation-status judgments about individuals — that belongs to God alone"
        ),
    ]

    // MARK: - Humility nudges for uncertain claims

    private let humilityRequiredPatterns: [String] = [
        #"(?i)(this passage means exactly)"#,
        #"(?i)(the only interpretation)"#,
        #"(?i)(no sincere christian)"#,
        #"(?i)(you must believe)"#,
    ]

    private let humilitySuffix = "\n\n*Note: This is one way to read this passage. Many Christians interpret this differently, and speaking with a trusted pastor may provide valuable perspective.*"

    // MARK: - Public interface

    /// Sanitizes an AI response text before it is rendered to the user.
    /// Returns the original text unchanged if no issues are found.
    @discardableResult
    func sanitize(_ text: String) -> BereanBoundaryResult {
        var working = text
        var detected: [String] = []
        var rewritten = false

        // Apply hard-block replacements
        for phrase in blockedPhrases {
            let (newText, found) = applyReplacement(in: working, pattern: phrase.pattern, replacement: phrase.replacement, isRegex: phrase.isRegex)
            if found {
                detected.append(phrase.pattern)
                working = newText
                rewritten = true
            }
        }

        // Check if humility suffix needed
        var needsHumilitySuffix = false
        for pattern in humilityRequiredPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: working, range: NSRange(working.startIndex..., in: working)) != nil {
                needsHumilitySuffix = true
                detected.append(pattern)
                break
            }
        }

        if needsHumilitySuffix && !working.hasSuffix(humilitySuffix) {
            working += humilitySuffix
            rewritten = true
        }

        // Log safety rewrite if it happened
        if rewritten {
            let detectedCount = detected.count
            Task { @MainActor in
                AMENAnalyticsService.shared.track(.bereanSafetyRewrite(trigger: "theology_boundary_\(detectedCount)"))
            }
        }

        return BereanBoundaryResult(
            originalText: text,
            sanitizedText: working,
            rewroteContent: rewritten,
            detectedPatterns: detected
        )
    }

    /// Applies a single pattern replacement.
    private func applyReplacement(
        in text: String,
        pattern: String,
        replacement: String,
        isRegex: Bool
    ) -> (String, Bool) {
        guard isRegex else {
            // Literal substring replacement (case-insensitive)
            let range = text.range(of: pattern, options: [.caseInsensitive])
            guard let r = range else { return (text, false) }
            return (text.replacingCharacters(in: r, with: replacement), true)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, false)
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return (text, false) }

        let result = regex.stringByReplacingMatches(
            in: text,
            range: nsRange,
            withTemplate: replacement
        )
        return (result, true)
    }
}

// MARK: - Disputed Topic Detector

/// Detects whether a query touches a historically disputed theological topic,
/// which should trigger humility language and multi-perspective framing.
struct BereanDisputedTopicDetector {

    private static let disputedPatterns: [(pattern: String, topic: String)] = [
        (#"(?i)(calvin|predestination|elect(?:ion)?)"#, "predestination"),
        (#"(?i)(tongues|charismatic|cessationism)"#, "charismatic gifts"),
        (#"(?i)(baptism.*(?:infant|mode|immersion))"#, "baptism mode"),
        (#"(?i)(rapture|tribulation|millenn)"#, "eschatology"),
        (#"(?i)(women.*(?:lead|preach|ordain)|female.*pastor)"#, "women in ministry"),
        (#"(?i)(once saved always saved|eternal security|apostasy)"#, "eternal security"),
        (#"(?i)(free will|total depravity|arminian)"#, "free will vs sovereignty"),
        (#"(?i)(prosperity gospel|health and wealth)"#, "prosperity theology"),
        (#"(?i)(divorce.*remarriage|remarriage.*divorce)"#, "divorce and remarriage"),
    ]

    /// Returns the identified disputed topic(s) if detected, otherwise nil.
    static func detect(in text: String) -> [String] {
        var found: [String] = []
        for item in disputedPatterns {
            if let regex = try? NSRegularExpression(pattern: item.pattern, options: []),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                found.append(item.topic)
            }
        }
        return found
    }

    /// Returns the humility preamble to prepend for disputed topics.
    static func humilityPreamble(forTopics topics: [String]) -> String {
        let topicList = topics.joined(separator: ", ")
        return "This topic (\(topicList)) has been debated thoughtfully by Christians across traditions. I'll share what scripture says and note where interpretations differ, without claiming one view is the only valid one.\n\n"
    }
}
