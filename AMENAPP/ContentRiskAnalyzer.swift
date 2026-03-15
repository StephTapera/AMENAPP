// ContentRiskAnalyzer.swift
// AMENAPP
//
// On-device content risk scoring for user-generated text.
// Detects: emotional distress, self-harm/crisis, violence/threats,
//          illegal activity (drugs/trafficking), financial distress,
//          harassment/exploitation.
//
// Architecture:
//   - Entirely local — no network round-trip for scoring
//   - Signal-based weighted scoring (0.0 – 1.0 per category)
//   - Returns ContentRiskResult with primary category, total score,
//     per-category breakdown, and matched signals for explainability
//   - quickScan() is fast (< 1ms) for passive feed scanning
//   - analyze() is thorough (runs all categories + context boost)
//
// Privacy: no raw text is ever stored or transmitted.
// Only category/score is surfaced to SafetyOrchestrator for audit logging.

import Foundation

// MARK: - Content Context

/// Where the content is being submitted or scanned from.
/// Used to apply context-appropriate scoring boosts.
enum SafetyContentContext: String {
    case post           = "post"
    case comment        = "comment"
    case prayerRequest  = "prayer_request"
    case testimony      = "testimony"
    case message        = "message"
    case churchNote     = "church_note"
    case profile        = "profile"
    case unknown        = "unknown"
    case jobPosting     = "job_posting"
    case jobApplication = "job_application"

    /// Contexts that carry higher emotional weight (e.g. prayer requests expect vulnerability)
    var isHighEmotionalContext: Bool {
        switch self {
        case .prayerRequest, .testimony, .jobApplication: return true
        default: return false
        }
    }
}

// MARK: - Risk Category

/// The primary risk category identified in a piece of content.
enum ContentRiskCategory: String, CaseIterable, Equatable {
    case none                   = "none"
    case emotionalDistress      = "emotional_distress"
    case selfHarmCrisis         = "self_harm_crisis"
    case violenceThreat         = "violence_threat"
    case illegalActivity        = "illegal_activity"
    case financialDistress      = "financial_distress"
    case harassmentExploitation = "harassment_exploitation"
    /// Sexual exploitation, grooming, trafficking, solicitation, predatory contact
    case groomingTrafficking    = "grooming_trafficking"
    /// Explicit sexual content, nudity descriptions, pornographic solicitation
    case explicitSexual         = "explicit_sexual"
    /// Profanity, vulgarity, hate slurs
    case profanityHate          = "profanity_hate"
    /// Spam, scam, phishing, impersonation, financial fraud
    case spamScam               = "spam_scam"
}

// MARK: - Risk Result

/// The output of a content risk analysis pass.
struct ContentRiskResult {
    /// The dominant risk category (highest score)
    let primaryCategory: ContentRiskCategory

    /// Aggregate risk score for the primary category (0.0 – 1.0)
    let totalScore: Double

    /// Per-category scores for all categories analyzed
    let categoryScores: [ContentRiskCategory: Double]

    /// Human-readable signal labels that fired (for moderator explainability)
    let matchedSignals: [String]

    /// True if the result came from a full analyze() pass (vs. quickScan)
    let isDeepScan: Bool

    static var clean: ContentRiskResult {
        ContentRiskResult(
            primaryCategory: .none,
            totalScore: 0.0,
            categoryScores: [:],
            matchedSignals: [],
            isDeepScan: false
        )
    }
}

// MARK: - Signal Definition

private struct RiskSignal {
    /// Display name for moderator explainability
    let label: String

    /// The pattern to match (lowercased text)
    let pattern: String

    /// Base weight contribution to the category score (0.0 – 1.0)
    let weight: Double

    /// If true, use whole-word matching only
    let wholeWord: Bool

    init(_ label: String, _ pattern: String, weight: Double, wholeWord: Bool = false) {
        self.label = label
        self.pattern = pattern
        self.weight = weight
        self.wholeWord = wholeWord
    }
}

// MARK: - Analyzer

/// On-device content risk analyzer.
/// Thread-safe — `analyze()` and `quickScan()` can be called from any thread.
final class ContentRiskAnalyzer {
    static let shared = ContentRiskAnalyzer()
    private init() { buildCaches() }

    // MARK: - Signal Tables

    // ── Emotional Distress ────────────────────────────────────────────────────
    private let distressSignals: [RiskSignal] = [
        RiskSignal("hopelessness",        "there's no point",         weight: 0.55),
        RiskSignal("hopelessness",        "nothing matters anymore",  weight: 0.55),
        RiskSignal("hopelessness",        "feel completely lost",     weight: 0.45),
        RiskSignal("hopelessness",        "no hope",                  weight: 0.50),
        RiskSignal("hopelessness",        "hopeless",                 weight: 0.40, wholeWord: true),
        RiskSignal("hopelessness",        "no reason to go on",       weight: 0.70),
        RiskSignal("hopelessness",        "no reason to keep going",  weight: 0.65),
        RiskSignal("isolation",           "nobody cares",             weight: 0.40),
        RiskSignal("isolation",           "no one cares",             weight: 0.40),
        RiskSignal("isolation",           "completely alone",         weight: 0.38),
        RiskSignal("isolation",           "all alone",                weight: 0.30),
        RiskSignal("isolation",           "feels like nobody",        weight: 0.35),
        RiskSignal("worthlessness",       "worthless",                weight: 0.50, wholeWord: true),
        RiskSignal("worthlessness",       "i am nothing",             weight: 0.50),
        RiskSignal("worthlessness",       "i'm nothing",              weight: 0.50),
        RiskSignal("worthlessness",       "i don't matter",           weight: 0.45),
        RiskSignal("worthlessness",       "i'm a burden",             weight: 0.60),
        RiskSignal("worthlessness",       "i am a burden",            weight: 0.60),
        RiskSignal("worthlessness",       "better off without me",    weight: 0.75),
        RiskSignal("exhaustion",          "so tired of everything",   weight: 0.30),
        RiskSignal("exhaustion",          "can't take it anymore",    weight: 0.50),
        RiskSignal("exhaustion",          "can't do this anymore",    weight: 0.45),
        RiskSignal("sadness-severe",      "crying all the time",      weight: 0.30),
        RiskSignal("sadness-severe",      "can't stop crying",        weight: 0.35),
        RiskSignal("emptiness",           "feel empty inside",        weight: 0.40),
        RiskSignal("emptiness",           "feel empty",               weight: 0.30),
        RiskSignal("emptiness",           "numb to everything",       weight: 0.38),
        RiskSignal("despair",             "deeply depressed",         weight: 0.42),
        RiskSignal("despair",             "deep depression",          weight: 0.40),
        RiskSignal("despair",             "drowning in depression",   weight: 0.45),
        RiskSignal("despair",             "never gets better",        weight: 0.38),
        RiskSignal("abandonment",         "god has abandoned me",     weight: 0.45),
        RiskSignal("abandonment",         "god doesn't care",         weight: 0.35),
    ]

    // ── Self-Harm / Crisis ────────────────────────────────────────────────────
    private let crisisSignals: [RiskSignal] = [
        RiskSignal("suicide-direct",      "want to kill myself",      weight: 0.95),
        RiskSignal("suicide-direct",      "going to kill myself",     weight: 0.95),
        RiskSignal("suicide-direct",      "plan to kill myself",      weight: 0.95),
        RiskSignal("suicide-direct",      "want to end my life",      weight: 0.90),
        RiskSignal("suicide-direct",      "planning to end my life",  weight: 0.92),
        RiskSignal("suicide-direct",      "thinking about suicide",   weight: 0.85),
        RiskSignal("suicide-direct",      "suicidal thoughts",        weight: 0.82),
        RiskSignal("suicide-direct",      "suicidal ideation",        weight: 0.85),
        RiskSignal("suicide-indirect",    "not be here anymore",      weight: 0.70),
        RiskSignal("suicide-indirect",    "won't be here anymore",    weight: 0.72),
        RiskSignal("suicide-indirect",    "world better without me",  weight: 0.78),
        RiskSignal("suicide-indirect",    "everyone better off",      weight: 0.65),
        RiskSignal("suicide-indirect",    "done with this life",      weight: 0.60),
        RiskSignal("suicide-indirect",    "tired of being alive",     weight: 0.72),
        RiskSignal("self-harm-direct",    "cutting myself",           weight: 0.85),
        RiskSignal("self-harm-direct",    "hurting myself",           weight: 0.75),
        RiskSignal("self-harm-direct",    "harm myself",              weight: 0.78),
        RiskSignal("self-harm-direct",    "hurt myself",              weight: 0.60),
        RiskSignal("self-harm-direct",    "self harm",                weight: 0.75),
        RiskSignal("self-harm-direct",    "self-harm",                weight: 0.75),
        RiskSignal("means-reference",     "pills to end",             weight: 0.88),
        RiskSignal("means-reference",     "overdose",                 weight: 0.65, wholeWord: true),
        RiskSignal("means-reference",     "jump off",                 weight: 0.60),
        RiskSignal("means-reference",     "rope around",              weight: 0.80),
        RiskSignal("goodbye-signal",      "goodbye everyone",         weight: 0.72),
        RiskSignal("goodbye-signal",      "saying goodbye",           weight: 0.60),
        RiskSignal("goodbye-signal",      "my final",                 weight: 0.40),
        RiskSignal("goodbye-signal",      "last time writing",        weight: 0.65),
        RiskSignal("goodbye-signal",      "won't post again",         weight: 0.55),
    ]

    // ── Violence / Threats ────────────────────────────────────────────────────
    private let violenceSignals: [RiskSignal] = [
        RiskSignal("explicit-threat",     "going to kill",            weight: 0.88),
        RiskSignal("explicit-threat",     "i will kill",              weight: 0.90),
        RiskSignal("explicit-threat",     "want to kill",             weight: 0.70),
        RiskSignal("explicit-threat",     "kill you",                 weight: 0.80),
        RiskSignal("explicit-threat",     "going to hurt",            weight: 0.70),
        RiskSignal("explicit-threat",     "i will hurt",              weight: 0.72),
        RiskSignal("explicit-threat",     "will make you pay",        weight: 0.65),
        RiskSignal("explicit-threat",     "you'll pay for this",      weight: 0.60),
        RiskSignal("explicit-threat",     "you're dead",              weight: 0.75),
        RiskSignal("weapon-reference",    "shoot you",                weight: 0.78),
        RiskSignal("weapon-reference",    "bring a gun",              weight: 0.80),
        RiskSignal("weapon-reference",    "stab you",                 weight: 0.78),
        RiskSignal("weapon-reference",    "with a knife",             weight: 0.50),
        RiskSignal("mass-violence",       "mass shooting",            weight: 0.90),
        RiskSignal("mass-violence",       "bomb threat",              weight: 0.92),
        RiskSignal("mass-violence",       "attack the",               weight: 0.55),
        RiskSignal("mass-violence",       "blow up",                  weight: 0.65),
        RiskSignal("domestic-violence",   "beat her",                 weight: 0.72),
        RiskSignal("domestic-violence",   "beat him",                 weight: 0.72),
        RiskSignal("domestic-violence",   "hit her",                  weight: 0.45),
        RiskSignal("domestic-violence",   "choke",                    weight: 0.50, wholeWord: true),
        RiskSignal("violent-language",    "wanna fight",              weight: 0.45),
        RiskSignal("violent-language",    "come at me",               weight: 0.35),
        RiskSignal("violent-language",    "catch these hands",        weight: 0.42),
    ]

    // ── Illegal Activity ──────────────────────────────────────────────────────
    private let illegalSignals: [RiskSignal] = [
        // Drug dealing
        RiskSignal("drug-deal",           "selling drugs",            weight: 0.80),
        RiskSignal("drug-deal",           "buying drugs",             weight: 0.78),
        RiskSignal("drug-deal",           "fronting",                 weight: 0.35),
        RiskSignal("drug-deal",           "plug for",                 weight: 0.50),
        RiskSignal("drug-deal",           "got packs",                weight: 0.55),
        RiskSignal("drug-deal",           "hit my line",              weight: 0.35),
        RiskSignal("drug-deal",           "drop off",                 weight: 0.20),
        RiskSignal("drug-slang",          "white girl",               weight: 0.35),
        RiskSignal("drug-slang",          "loud pack",                weight: 0.55),
        RiskSignal("drug-slang",          "percs",                    weight: 0.50, wholeWord: true),
        RiskSignal("drug-slang",          "xanny",                    weight: 0.50, wholeWord: true),
        RiskSignal("drug-slang",          "blues",                    weight: 0.30, wholeWord: true),
        RiskSignal("drug-slang",          "fetty",                    weight: 0.55, wholeWord: true),
        RiskSignal("drug-explicit",       "cocaine",                  weight: 0.70, wholeWord: true),
        RiskSignal("drug-explicit",       "heroin",                   weight: 0.72, wholeWord: true),
        RiskSignal("drug-explicit",       "fentanyl",                 weight: 0.80, wholeWord: true),
        RiskSignal("drug-explicit",       "meth",                     weight: 0.65, wholeWord: true),
        RiskSignal("drug-explicit",       "crack rock",               weight: 0.78),
        // Trafficking signals (contextual — require other signals to score high)
        RiskSignal("trafficking",         "send me girls",            weight: 0.75),
        RiskSignal("trafficking",         "girls available",          weight: 0.65),
        RiskSignal("trafficking",         "escort service",           weight: 0.58),
        RiskSignal("trafficking",         "willing to work",          weight: 0.25),
        RiskSignal("trafficking",         "outcall",                  weight: 0.50),
        // Financial fraud
        RiskSignal("fraud",               "cash app flip",            weight: 0.80),
        RiskSignal("fraud",               "double your money",        weight: 0.65),
        RiskSignal("fraud",               "guaranteed investment",    weight: 0.55),
        RiskSignal("fraud",               "send bitcoin",             weight: 0.50),
        RiskSignal("fraud",               "wire transfer",            weight: 0.30),
        RiskSignal("fraud",               "i got hacked dm",          weight: 0.70),
    ]

    // ── Financial Distress ────────────────────────────────────────────────────
    private let financialDistressSignals: [RiskSignal] = [
        RiskSignal("eviction",            "about to be evicted",      weight: 0.72),
        RiskSignal("eviction",            "getting evicted",          weight: 0.68),
        RiskSignal("eviction",            "can't pay rent",           weight: 0.65),
        RiskSignal("eviction",            "behind on rent",           weight: 0.60),
        RiskSignal("eviction",            "being evicted",            weight: 0.70),
        RiskSignal("utilities",           "lights got cut off",       weight: 0.65),
        RiskSignal("utilities",           "power got cut",            weight: 0.60),
        RiskSignal("utilities",           "no electricity",           weight: 0.45),
        RiskSignal("utilities",           "gas got cut",              weight: 0.58),
        RiskSignal("food-insecurity",     "can't afford food",        weight: 0.65),
        RiskSignal("food-insecurity",     "haven't eaten",            weight: 0.55),
        RiskSignal("food-insecurity",     "no food in the house",     weight: 0.65),
        RiskSignal("food-insecurity",     "going hungry",             weight: 0.58),
        RiskSignal("debt-crisis",         "drowning in debt",         weight: 0.65),
        RiskSignal("debt-crisis",         "collections calling",      weight: 0.50),
        RiskSignal("debt-crisis",         "debt collectors",          weight: 0.48),
        RiskSignal("debt-crisis",         "can't pay bills",          weight: 0.55),
        RiskSignal("debt-crisis",         "filing for bankruptcy",    weight: 0.60),
        RiskSignal("unemployment",        "lost my job",              weight: 0.45),
        RiskSignal("unemployment",        "laid off",                 weight: 0.40),
        RiskSignal("unemployment",        "unemployed",               weight: 0.38, wholeWord: true),
        RiskSignal("homeless",            "sleeping in my car",       weight: 0.72),
        RiskSignal("homeless",            "lost my home",             weight: 0.65),
        RiskSignal("homeless",            "no place to stay",         weight: 0.62),
        RiskSignal("homeless",            "living on the street",     weight: 0.70),
    ]

    // ── Harassment / Exploitation ─────────────────────────────────────────────
    private let harassmentSignals: [RiskSignal] = [
        RiskSignal("direct-abuse",        "shut up",                  weight: 0.35),
        RiskSignal("direct-abuse",        "you're stupid",            weight: 0.40),
        RiskSignal("direct-abuse",        "you're disgusting",        weight: 0.50),
        RiskSignal("direct-abuse",        "go kill yourself",         weight: 0.90),
        RiskSignal("direct-abuse",        "kys",                      weight: 0.85, wholeWord: true),
        RiskSignal("direct-abuse",        "nobody wants you",         weight: 0.60),
        RiskSignal("direct-abuse",        "you don't belong here",    weight: 0.55),
        RiskSignal("direct-abuse",        "leave the community",      weight: 0.42),
        RiskSignal("blackmail",           "expose you",               weight: 0.60),
        RiskSignal("blackmail",           "i have your photos",       weight: 0.72),
        RiskSignal("blackmail",           "send money or i'll",       weight: 0.85),
        RiskSignal("blackmail",           "share your nudes",         weight: 0.88),
        RiskSignal("solicitation",        "send me nudes",            weight: 0.90),
        RiskSignal("solicitation",        "send pics",                weight: 0.55),
        RiskSignal("solicitation",        "only fans",                weight: 0.50),
        RiskSignal("predatory",           "how old are you",          weight: 0.45),
        RiskSignal("predatory",           "are you a minor",          weight: 0.55),
        RiskSignal("predatory",           "are you 18",               weight: 0.50),
        RiskSignal("predatory",           "meet up alone",            weight: 0.58),
        RiskSignal("identity-attack",     "i know where you live",    weight: 0.78),
        RiskSignal("identity-attack",     "i found your address",     weight: 0.80),
        RiskSignal("identity-attack",     "doxxing",                  weight: 0.75, wholeWord: true),
    ]

    // ── Grooming / Trafficking / Child Exploitation ───────────────────────────
    private let groomingSignals: [RiskSignal] = [
        RiskSignal("age-probe",           "how old are you",          weight: 0.48),
        RiskSignal("age-probe",           "what grade are you in",    weight: 0.52),
        RiskSignal("age-probe",           "are you a minor",          weight: 0.60),
        RiskSignal("age-probe",           "are you 18",               weight: 0.55),
        RiskSignal("age-probe",           "are you over 18",          weight: 0.50),
        RiskSignal("age-probe",           "how young are you",        weight: 0.65),
        RiskSignal("secrecy",             "don't tell your parents",  weight: 0.90),
        RiskSignal("secrecy",             "don't tell anyone",        weight: 0.68),
        RiskSignal("secrecy",             "keep this between us",     weight: 0.72),
        RiskSignal("secrecy",             "our secret",               weight: 0.70),
        RiskSignal("secrecy",             "just between us",          weight: 0.62),
        RiskSignal("secrecy",             "delete this after",        weight: 0.65),
        RiskSignal("platform-escape",     "snapchat me",              weight: 0.55),
        RiskSignal("platform-escape",     "add me on snap",           weight: 0.52),
        RiskSignal("platform-escape",     "text me privately",        weight: 0.50),
        RiskSignal("platform-escape",     "let's talk on telegram",   weight: 0.62),
        RiskSignal("platform-escape",     "move to another app",      weight: 0.58),
        RiskSignal("meetup-pressure",     "meet up alone",            weight: 0.75),
        RiskSignal("meetup-pressure",     "meet me alone",            weight: 0.78),
        RiskSignal("meetup-pressure",     "come meet me",             weight: 0.62),
        RiskSignal("meetup-pressure",     "where do you live",        weight: 0.58),
        RiskSignal("coercion",            "i'll buy you",             weight: 0.52),
        RiskSignal("coercion",            "i'll give you money",      weight: 0.60),
        RiskSignal("coercion",            "you're so mature",         weight: 0.52),
        RiskSignal("coercion",            "not like other kids",      weight: 0.65),
        RiskSignal("coercion",            "special friend",           weight: 0.45),
        RiskSignal("trafficking",         "send me girls",            weight: 0.90),
        RiskSignal("trafficking",         "girls available",          weight: 0.75),
        RiskSignal("trafficking",         "escort service",           weight: 0.75),
        RiskSignal("trafficking",         "paid companionship",       weight: 0.70),
        RiskSignal("trafficking",         "outcall",                  weight: 0.65),
        RiskSignal("trafficking",         "looking for girls",        weight: 0.68),
        RiskSignal("trafficking",         "come work for me",         weight: 0.65),
        RiskSignal("sextortion",          "share your nudes",         weight: 0.95),
        RiskSignal("sextortion",          "send me nudes",            weight: 0.95),
        RiskSignal("sextortion",          "i have your photos",       weight: 0.80),
        RiskSignal("sextortion",          "i'll expose you",          weight: 0.75),
        RiskSignal("sextortion",          "leak your pics",           weight: 0.82),
    ]

    // ── Explicit Sexual Content ───────────────────────────────────────────────
    private let explicitSexualSignals: [RiskSignal] = [
        RiskSignal("explicit-request",    "send pics",                weight: 0.62),
        RiskSignal("explicit-request",    "send nude",                weight: 0.92),
        RiskSignal("explicit-request",    "send naked",               weight: 0.90),
        RiskSignal("explicit-request",    "send body pics",           weight: 0.82),
        RiskSignal("explicit-request",    "rate my body",             weight: 0.72),
        RiskSignal("explicit-request",    "onlyfans",                 weight: 0.68),
        RiskSignal("explicit-request",    "only fans",                weight: 0.65),
        RiskSignal("explicit-desc",       "sex tape",                 weight: 0.85),
        RiskSignal("explicit-desc",       "porn",                     weight: 0.72, wholeWord: true),
        RiskSignal("explicit-desc",       "pornography",              weight: 0.85, wholeWord: true),
        RiskSignal("explicit-desc",       "nude photo",               weight: 0.85),
        RiskSignal("explicit-desc",       "naked photo",              weight: 0.85),
        RiskSignal("explicit-desc",       "explicit photo",           weight: 0.80),
        RiskSignal("sexual-solicitation", "looking for hookup",       weight: 0.75),
        RiskSignal("sexual-solicitation", "hook up tonight",          weight: 0.80),
        RiskSignal("sexual-solicitation", "casual sex",               weight: 0.82),
        RiskSignal("sexual-solicitation", "sex for money",            weight: 0.90),
        RiskSignal("sexual-solicitation", "pay for sex",              weight: 0.90),
    ]

    // ── Profanity / Hate Speech ───────────────────────────────────────────────
    // Weights tuned for a Christian 13+ platform: strong profanity triggers block;
    // context-neutral words like "hell" get minimal weight to avoid false positives.
    private let profanitySignals: [RiskSignal] = [
        RiskSignal("profanity-strong",    "motherf",                  weight: 0.78),
        RiskSignal("profanity-strong",    "bitch",                    weight: 0.58, wholeWord: true),
        RiskSignal("profanity-strong",    "b*tch",                    weight: 0.58),
        RiskSignal("profanity-strong",    "fuck",                     weight: 0.65, wholeWord: true),
        RiskSignal("profanity-strong",    "f*ck",                     weight: 0.62),
        RiskSignal("profanity-strong",    "f**k",                     weight: 0.60),
        RiskSignal("profanity-strong",    "shit",                     weight: 0.48, wholeWord: true),
        RiskSignal("profanity-strong",    "s*it",                     weight: 0.45),
        RiskSignal("profanity-strong",    "sh!t",                     weight: 0.45),
        RiskSignal("profanity-strong",    "asshole",                  weight: 0.58, wholeWord: true),
        RiskSignal("profanity-strong",    "a$$hole",                  weight: 0.55),
        RiskSignal("profanity-strong",    "bastard",                  weight: 0.48, wholeWord: true),
        RiskSignal("profanity-strong",    "b!tch",                    weight: 0.55),
        // Hate slurs — immediate block
        RiskSignal("hate-slur",           "white power",              weight: 0.95),
        RiskSignal("hate-slur",           "heil",                     weight: 0.90, wholeWord: true),
        RiskSignal("hate-slur",           "sub-human",                weight: 0.80),
        RiskSignal("hate-speech",         "go back to your country",  weight: 0.85),
        RiskSignal("hate-speech",         "your kind",                weight: 0.48),
    ]

    // ── Spam / Scam / Phishing ────────────────────────────────────────────────
    private let spamScamSignals: [RiskSignal] = [
        RiskSignal("cash-flip",           "cash app flip",            weight: 0.90),
        RiskSignal("cash-flip",           "flip your money",          weight: 0.85),
        RiskSignal("cash-flip",           "double your money",        weight: 0.75),
        RiskSignal("investment-scam",     "guaranteed investment",    weight: 0.68),
        RiskSignal("investment-scam",     "guaranteed returns",       weight: 0.65),
        RiskSignal("crypto-scam",         "send bitcoin",             weight: 0.65),
        RiskSignal("crypto-scam",         "send crypto",              weight: 0.60),
        RiskSignal("phishing",            "confirm your password",    weight: 0.65),
        RiskSignal("phishing",            "verify your account",      weight: 0.48),
        RiskSignal("hacked-scam",         "i got hacked dm",          weight: 0.82),
        RiskSignal("impersonation",       "official amen support",    weight: 0.78),
        RiskSignal("impersonation",       "amen team here",           weight: 0.72),
        RiskSignal("prize-scam",          "claim your prize",         weight: 0.68),
        RiskSignal("prize-scam",          "you've been selected",     weight: 0.52),
    ]

    // MARK: - Regex Cache

    private var regexCache: [String: NSRegularExpression] = [:]

    private func buildCaches() {
        // Pre-compile any patterns that benefit from regex (whole-word signals)
        let allSignals = distressSignals + crisisSignals + violenceSignals +
                         illegalSignals + financialDistressSignals + harassmentSignals +
                         groomingSignals + explicitSexualSignals + profanitySignals + spamScamSignals
        for signal in allSignals where signal.wholeWord {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: signal.pattern))\\b"
            regexCache[signal.pattern] = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        }
    }

    // MARK: - Public API

    /// Full multi-category analysis. Returns complete scoring breakdown.
    /// Safe to call from a background Task.
    func analyze(text: String, context: SafetyContentContext) -> ContentRiskResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .clean
        }

        let lower = text.lowercased()
        var scores: [ContentRiskCategory: Double] = [:]
        var allMatchedSignals: [String] = []

        // Score each category
        let (distress, dSignals)    = score(lower, signals: distressSignals)
        let (crisis, cSignals)      = score(lower, signals: crisisSignals)
        let (violence, vSignals)    = score(lower, signals: violenceSignals)
        let (illegal, iSignals)     = score(lower, signals: illegalSignals)
        let (financial, fSignals)   = score(lower, signals: financialDistressSignals)
        let (harass, hSignals)      = score(lower, signals: harassmentSignals)
        let (grooming, gSignals)    = score(lower, signals: groomingSignals)
        let (explicit, eSignals)    = score(lower, signals: explicitSexualSignals)
        let (profanity, pSignals)   = score(lower, signals: profanitySignals)
        let (spam, spamSignals)     = score(lower, signals: spamScamSignals)

        scores[.emotionalDistress]       = distress
        scores[.selfHarmCrisis]          = crisis
        scores[.violenceThreat]          = violence
        scores[.illegalActivity]         = illegal
        scores[.financialDistress]       = financial
        scores[.harassmentExploitation]  = harass
        scores[.groomingTrafficking]     = grooming
        scores[.explicitSexual]          = explicit
        scores[.profanityHate]           = profanity
        scores[.spamScam]               = spam

        allMatchedSignals = dSignals + cSignals + vSignals + iSignals + fSignals + hSignals
                          + gSignals + eSignals + pSignals + spamSignals

        // Crisis always wins if high-scoring
        if crisis > 0.50 {
            scores[.selfHarmCrisis] = min(1.0, crisis * contextBoost(context, for: .selfHarmCrisis))
        }

        // Apply mild boost for high-emotional contexts (prayer requests, testimonies)
        if context.isHighEmotionalContext {
            scores[.emotionalDistress] = min(1.0, (scores[.emotionalDistress] ?? 0) * 1.15)
        }

        // Find primary category
        let primaryEntry = scores
            .filter { $0.value > 0.05 }
            .max(by: { $0.value < $1.value })

        guard let primary = primaryEntry else {
            return .clean
        }

        return ContentRiskResult(
            primaryCategory: primary.key,
            totalScore: min(1.0, primary.value),
            categoryScores: scores,
            matchedSignals: Array(Set(allMatchedSignals)).sorted(),
            isDeepScan: true
        )
    }

    /// Lightweight scan — only checks the highest-priority categories.
    /// Intended for passive feed scanning. Always fast (< 1ms).
    func quickScan(text: String) -> ContentRiskResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .clean
        }

        let lower = text.lowercased()

        // Crisis is first-priority
        let (crisis, cSignals) = score(lower, signals: crisisSignals)
        if crisis > 0.35 {
            return ContentRiskResult(
                primaryCategory: .selfHarmCrisis,
                totalScore: min(1.0, crisis),
                categoryScores: [.selfHarmCrisis: crisis],
                matchedSignals: cSignals,
                isDeepScan: false
            )
        }

        // Violence second
        let (violence, vSignals) = score(lower, signals: violenceSignals)
        if violence > 0.40 {
            return ContentRiskResult(
                primaryCategory: .violenceThreat,
                totalScore: min(1.0, violence),
                categoryScores: [.violenceThreat: violence],
                matchedSignals: vSignals,
                isDeepScan: false
            )
        }

        // Grooming / trafficking / child safety — third priority
        let (grooming, gSignals) = score(lower, signals: groomingSignals)
        if grooming > 0.35 {
            return ContentRiskResult(
                primaryCategory: .groomingTrafficking,
                totalScore: min(1.0, grooming),
                categoryScores: [.groomingTrafficking: grooming],
                matchedSignals: gSignals,
                isDeepScan: false
            )
        }

        // Explicit sexual content — fourth priority
        let (explicit, eSignals) = score(lower, signals: explicitSexualSignals)
        if explicit > 0.35 {
            return ContentRiskResult(
                primaryCategory: .explicitSexual,
                totalScore: min(1.0, explicit),
                categoryScores: [.explicitSexual: explicit],
                matchedSignals: eSignals,
                isDeepScan: false
            )
        }

        // Distress (passive awareness)
        let (distress, dSignals) = score(lower, signals: distressSignals)
        if distress > 0.30 {
            return ContentRiskResult(
                primaryCategory: .emotionalDistress,
                totalScore: min(1.0, distress),
                categoryScores: [.emotionalDistress: distress],
                matchedSignals: dSignals,
                isDeepScan: false
            )
        }

        return .clean
    }

    // MARK: - Scoring Engine

    /// Returns a clamped score (0–1) and the list of matched signal labels.
    private func score(_ lower: String, signals: [RiskSignal]) -> (Double, [String]) {
        var totalWeight = 0.0
        var matchedLabels: [String] = []

        for signal in signals {
            if matches(lower, signal: signal) {
                totalWeight += signal.weight
                if !matchedLabels.contains(signal.label) {
                    matchedLabels.append(signal.label)
                }
            }
        }

        // Sigmoid-style soft cap so stacking many weak signals doesn't max score easily
        let score = totalWeight / (totalWeight + 0.60)
        return (min(1.0, score), matchedLabels)
    }

    private func matches(_ lower: String, signal: RiskSignal) -> Bool {
        if signal.wholeWord, let regex = regexCache[signal.pattern] {
            let range = NSRange(lower.startIndex..., in: lower)
            return regex.firstMatch(in: lower, options: [], range: range) != nil
        }
        return lower.contains(signal.pattern)
    }

    // MARK: - Context Boost

    private func contextBoost(_ context: SafetyContentContext, for category: ContentRiskCategory) -> Double {
        switch (context, category) {
        case (.prayerRequest, .selfHarmCrisis):   return 1.10
        case (.prayerRequest, .emotionalDistress): return 1.12
        case (.testimony, .selfHarmCrisis):        return 1.08
        case (.message, .harassmentExploitation):  return 1.15
        case (.message, .violenceThreat):          return 1.10
        default: return 1.0
        }
    }
}
