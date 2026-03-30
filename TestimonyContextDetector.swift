// TestimonyContextDetector.swift
// AMENAPP
//
// Detects whether user-generated content is a personal testimony or
// repentance narrative, so the moderation pipeline can avoid false-positive
// blocks on legitimate faith content that happens to reference past sin.
//
// Design principles:
//  - Entirely local — no network dependency
//  - Runs before Layer 0 in UnifiedSafetyGate so it can soften thresholds
//  - Only applies to public surfaces (.post, .comment, .testimony, .prayerRequest)
//  - Never exempts obviously explicit or solicitation content regardless of score
//
// Detection signals:
//  1. Past-tense narrative markers ("I used to", "before I", "I was", "years ago")
//  2. Repentance / transformation language ("changed my life", "set me free", "God healed")
//  3. Faith context markers ("Christ", "Jesus", "God", "faith", "church")
//  4. First-person past narrative structure (I + past-tense verb + sin/struggle)
//  5. Redemption arc language ("now I", "today I am", "I am free")

import Foundation

// MARK: - Result

struct TestimonyDetectionResult {
    /// Confidence that this content is a personal testimony (0.0 – 1.0)
    let confidence: Double

    /// Whether the pipeline should apply testimony-aware lenient thresholds
    var isTestimony: Bool { confidence >= 0.55 }

    /// How much to raise the block threshold for sexual/profanity categories.
    /// Added to existing scores before blocking, effectively giving testimonies
    /// more headroom before the gate fires.
    var thresholdBoost: Double {
        switch confidence {
        case 0.80...: return 0.40  // very strong testimony signal — generous headroom
        case 0.65..<0.80: return 0.30
        case 0.55..<0.65: return 0.20
        default: return 0.0
        }
    }

    static let notTestimony = TestimonyDetectionResult(confidence: 0.0)
}

// MARK: - Detector

enum TestimonyContextDetector {

    // MARK: - Past-tense narrative markers
    private static let pastTenseMarkers: [String] = [
        "i used to", "i used to be", "used to struggle", "used to live",
        "before i knew", "before i met", "before christ", "before jesus",
        "before god", "before i became", "before i was saved", "before i was born again",
        "i was once", "i was addicted", "i was living", "i was trapped",
        "i was caught", "i was lost", "i was broken",
        "years ago i", "years ago my", "as a child i", "growing up i",
        "when i was", "back then i", "in my past", "my old life",
        "i spent years", "i struggled for years", "for a long time i",
        "during that time i", "at that point in my life",
        "looking back", "i remember when", "there was a time when",
        "in my twenties", "in my teens", "in high school", "in college",
        "before i turned my life around", "the person i used to be",
    ]

    // MARK: - Repentance / transformation language
    private static let repentanceMarkers: [String] = [
        "changed my life", "transformed my life", "turned my life around",
        "set me free", "freed me from", "delivered me from", "delivered me out of",
        "healed me", "god healed", "jesus healed", "christ healed",
        "saved me from", "rescued me from", "pulled me out of",
        "i repented", "i repent", "i confessed", "i asked forgiveness",
        "i surrendered", "i gave my life", "gave my heart to",
        "i encountered", "i met jesus", "i met god", "i met christ",
        "born again", "new creation", "new life in christ", "my testimony",
        "my story of", "this is my story", "sharing my story",
        "i want to share", "i'm sharing this", "being transparent",
        "being vulnerable", "being open about", "opening up about",
        "testimony of how", "how god", "how jesus", "how christ",
        "no longer", "i am no longer", "i am free now", "i am free from",
        "i have been set free", "i have been delivered",
    ]

    // MARK: - Faith context markers
    private static let faithMarkers: [String] = [
        "jesus", "christ", "god", "holy spirit", "lord",
        "faith", "prayer", "church", "scripture", "bible",
        "gospel", "salvation", "grace", "mercy", "forgiveness",
        "redemption", "baptism", "pastor", "ministry", "worship",
        "testimony", "disciple", "disciple of", "follower of christ",
        "follower of jesus", "christian", "believer",
        "the lord", "my savior", "my lord", "my redeemer",
        "his grace", "his mercy", "the cross", "the blood of",
        "born again", "eternal life", "heaven", "the kingdom",
    ]

    // MARK: - Redemption arc / present-state markers
    private static let redemptionArcMarkers: [String] = [
        "now i am", "now i'm", "today i am", "today i'm",
        "i am free", "i am healed", "i am restored", "i am whole",
        "i have overcome", "i have victory", "i am victorious",
        "walking in freedom", "walking in victory", "walking with god",
        "i no longer", "no longer bound", "no longer controlled",
        "he restored", "god restored", "jesus restored",
        "my life is different", "my life has changed",
        "i can now", "i am able to", "i'm able to",
        "praise god", "thank god", "glory to god", "to god be",
        "if you're struggling", "if you struggle", "you are not alone",
        "there is hope", "there is healing", "healing is possible",
        "i hope this helps", "sharing this to encourage",
        "sharing this so others", "maybe this will help",
    ]

    // MARK: - Primary API

    /// Analyze text and return a confidence score for personal testimony content.
    /// Thread-safe — purely functional, no shared mutable state.
    static func detect(text: String) -> TestimonyDetectionResult {
        guard text.count >= 30 else { return .notTestimony }

        let lower = text.lowercased()
        var score: Double = 0.0

        // ── Signal 1: Past-tense narrative markers (0.0 – 0.35) ─────────────────
        let pastMatches = pastTenseMarkers.filter { lower.contains($0) }.count
        let pastScore = min(Double(pastMatches) * 0.12, 0.35)
        score += pastScore

        // ── Signal 2: Repentance / transformation language (0.0 – 0.35) ─────────
        let repentanceMatches = repentanceMarkers.filter { lower.contains($0) }.count
        let repentanceScore = min(Double(repentanceMatches) * 0.15, 0.35)
        score += repentanceScore

        // ── Signal 3: Faith context (0.0 – 0.20) ─────────────────────────────────
        let faithMatches = faithMarkers.filter { lower.contains($0) }.count
        let faithScore = min(Double(faithMatches) * 0.05, 0.20)
        score += faithScore

        // ── Signal 4: Redemption arc / present state (0.0 – 0.20) ────────────────
        let redemptionMatches = redemptionArcMarkers.filter { lower.contains($0) }.count
        let redemptionScore = min(Double(redemptionMatches) * 0.10, 0.20)
        score += redemptionScore

        // ── Compound boost: past + repentance + faith all present ────────────────
        if pastScore > 0 && repentanceScore > 0 && faithScore > 0 {
            score += 0.15
        }

        // ── Penalise if content looks present-tense solicitation ─────────────────
        // These are hard signals that override testimony detection:
        // "send me", "looking for", "available now", explicit pricing, etc.
        let solicitationPenalties = [
            "send me", "send us", "looking for", "available now", "dm me",
            "hit me up", "contact me for", "prices", "rates", "booking",
            "only fans", "onlyfans", "cam", "explicit",
        ]
        let penaltyCount = solicitationPenalties.filter { lower.contains($0) }.count
        score -= Double(penaltyCount) * 0.25

        let finalScore = max(0.0, min(score, 1.0))
        return TestimonyDetectionResult(confidence: finalScore)
    }
}
