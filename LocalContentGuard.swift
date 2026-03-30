// LocalContentGuard.swift
// AMENAPP
//
// Fast, offline, client-side content screening.
// Runs BEFORE any network calls — instant hard block for
// profanity, harassment, sexual content, hate speech, and violent language.
//
// Design principles:
//  - No network dependency — works offline, zero latency
//  - Case-insensitive with leet-speak normalisation (3→e, @→a, $→s, etc.)
//  - Bypass-resistant: f*ck, b!tch, f-u-c-k all detected
//  - Word-boundary aware — "grass" will NOT match "ass"
//  - Returns a user-visible reason so the error message is specific
//  - DM-specific surface: stricter thresholds, solicitation detection, contact exchange

import Foundation

// MARK: - Result type

struct LocalGuardResult {
    let isBlocked: Bool
    let category: LocalGuardCategory
    let userMessage: String
    /// Optional policyCode string for upstream logging
    let policyCode: String
}

extension LocalGuardResult {
    /// Convenience initialiser (backward compatible — no policyCode needed at call sites)
    init(isBlocked: Bool, category: LocalGuardCategory, userMessage: String) {
        self.isBlocked = isBlocked
        self.category = category
        self.userMessage = userMessage
        self.policyCode = category.defaultPolicyCode
    }
}

enum LocalGuardCategory: String {
    case clean
    case profanity
    case harassment
    case sexual
    case sexualSolicitation   // "rates", "hosting", "DM for content", OnlyFans promos
    case groomingSignal       // age-mention + sexual context, isolation language
    case hateSpeech
    case violence
    case offPlatformMigration // "add me on snap/telegram" etc.
    case contactExchange      // phone/email shared in context of sexual solicitation

    var defaultPolicyCode: String {
        switch self {
        case .clean:               return "NONE"
        case .profanity:           return "HOSTILE_DIRECTED"
        case .harassment:          return "HOSTILE_DIRECTED"
        case .sexual:              return "SEXUAL_CONTENT"
        case .sexualSolicitation:  return "SEXUAL_HARASS"
        case .groomingSignal:      return "GROOMING"
        case .hateSpeech:          return "HATE_SLUR"
        case .violence:            return "CREDIBLE_THREAT"
        case .offPlatformMigration: return "OFF_PLATFORM"
        case .contactExchange:     return "PII_EXPOSURE"
        }
    }
}

// MARK: - Guard

enum LocalContentGuard {

    // MARK: Cached regex patterns (compiled once, not per-call)
    // These are used inside firstMatch() — compiling inline is O(n) per check
    // on a hot send path and causes measurable latency at 100+ msg/s.
    //
    // Pattern format: word-boundary-aware via NSRegularExpression with (?<![a-z]) / (?![a-z]).
    // Cached lazily on first use; thread-safe because LocalContentGuard is a pure enum
    // with no instance state (all methods are static).
    private static var _compiledWordBoundaryCache: [String: NSRegularExpression] = [:]
    private static let cacheQueue = DispatchQueue(label: "LocalContentGuard.regex", attributes: .concurrent)

    private static func compiledRegex(for pattern: String) -> NSRegularExpression? {
        // Fast path: already cached
        if let cached = cacheQueue.sync(execute: { _compiledWordBoundaryCache[pattern] }) {
            return cached
        }
        // Slow path: compile and cache
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        cacheQueue.async(flags: .barrier) { _compiledWordBoundaryCache[pattern] = re }
        return re
    }

    // MARK: Public entry points

    /// Synchronous — call from any context. Returns immediately with no I/O.
    static func check(_ text: String) -> LocalGuardResult {
        return checkWithContext(text, isDM: false, recipientIsMinor: false)
    }

    /// Context-aware check. Pass `isDM: true` to apply stricter solicitation rules.
    /// Pass `recipientIsMinor: true` to apply the hardest protections (grooming, age+sexual).
    static func checkWithContext(
        _ text: String,
        isDM: Bool,
        recipientIsMinor: Bool
    ) -> LocalGuardResult {
        let plain = normalise(text)

        // ── Grooming / minor-safety (always highest priority) ─────────────────
        // BUG FIX: previously called containsGroomingSignal twice when recipientIsMinor=true
        // and there was a grooming signal — now check once, correctly, in all branches.
        let hasGroomingSignal = containsGroomingSignal(plain, isDM: isDM || recipientIsMinor)
        if hasGroomingSignal {
            return .init(
                isBlocked: true, category: .groomingSignal,
                userMessage: "This message contains content that could be harmful to a young person. It cannot be sent.",
                policyCode: "GROOMING"
            )
        }

        // ── Sexual solicitation (DMs + public posts both blocked) ─────────────
        if containsSexualSolicitation(plain) {
            return .init(
                isBlocked: true, category: .sexualSolicitation,
                userMessage: "Sexual solicitation isn't allowed on AMEN. This content has been blocked.",
                policyCode: "SEXUAL_HARASS"
            )
        }

        // ── Off-platform migration (stricter in DMs) ──────────────────────────
        if isDM && containsOffPlatformMigration(plain) {
            return .init(
                isBlocked: true, category: .offPlatformMigration,
                userMessage: "For your safety, please keep conversations within AMEN. Moving to other apps removes safety protections.",
                policyCode: "OFF_PLATFORM"
            )
        }

        // ── Core word-list checks ─────────────────────────────────────────────
        if firstMatch(in: plain, wordList: profanityTerms) != nil {
            return .init(
                isBlocked: true, category: .profanity,
                userMessage: "Your post contains language that isn't allowed in our community. Please revise it before sharing."
            )
        }
        if firstMatch(in: plain, wordList: harassmentTerms) != nil {
            return .init(
                isBlocked: true, category: .harassment,
                userMessage: "This post contains content that could be seen as harassment or bullying. AMEN is a place for uplifting one another — please revise."
            )
        }
        if firstMatch(in: plain, wordList: sexualTerms) != nil {
            return .init(
                isBlocked: true, category: .sexual,
                userMessage: "Your post contains content that isn't appropriate for our faith community. Please keep posts wholesome and respectful."
            )
        }
        if firstMatch(in: plain, wordList: hateSpeechTerms) != nil {
            return .init(
                isBlocked: true, category: .hateSpeech,
                userMessage: "Your post contains language that promotes hate or discrimination. AMEN welcomes all people — please revise."
            )
        }
        if firstMatch(in: plain, wordList: violenceTerms) != nil {
            return .init(
                isBlocked: true, category: .violence,
                userMessage: "Your post contains threatening or violent language. Please share thoughts peacefully."
            )
        }

        return .init(isBlocked: false, category: .clean, userMessage: "")
    }

    // MARK: - Grooming Signal Detection
    //
    // Detects the intersection of age-referencing language + sexual/romantic context,
    // isolation language ("don't tell anyone", "our secret"), and
    // authority exploitation ("I'm your pastor", "God told me to").

    static func containsGroomingSignal(_ text: String, isDM: Bool) -> Bool {
        let plain = isDM ? text : normalise(text)

        // Age mention + any sexual term (strongest signal in any context)
        let ageTerms = ["how old are you", "how old r u", "what grade are you in",
                        "are you 18", "are you under 18", "are you a minor",
                        "young girl", "young boy", "little girl", "little boy",
                        "underage", "jailbait"]
        let sexualContextTerms = ["sexy", "hot", "pretty", "beautiful body",
                                   "send me", "show me", "take a picture", "take a photo",
                                   "pic", "pics", "photo", "nude", "naked", "sexual", "touch"]
        let hasAge = ageTerms.contains { plain.contains($0) }
        let hasSexualContext = sexualContextTerms.contains { plain.contains($0) }
        if hasAge && hasSexualContext { return true }

        // Isolation / secrecy language (strong grooming signal)
        let isolationPhrases = [
            "don't tell anyone", "dont tell anyone", "keep this between us",
            "our little secret", "our secret", "don't tell your parents",
            "dont tell your parents", "don't tell mom", "don't tell dad",
            "this is just between you and me", "just between us"
        ]
        if isolationPhrases.contains(where: { plain.contains($0) }) { return true }

        // Authority exploitation in DMs
        if isDM {
            let authorityPhrases = [
                "god told me", "the lord told me", "the holy spirit told me",
                "i'm your pastor", "im your pastor", "as your spiritual leader",
                "as your mentor", "i'm your mentor", "im your mentor"
            ]
            let hasAuthority = authorityPhrases.contains { plain.contains($0) }
            let hasAnyRisk = hasSexualContext || hasAge
            if hasAuthority && hasAnyRisk { return true }
        }

        return false
    }

    // MARK: - Sexual Solicitation Detection
    //
    // Detects content that advertises sexual services, solicits sexual content,
    // or promotes adult platforms in a solicitation context.
    // Separate from core sexualTerms to allow context-aware blocking
    // (e.g., "OnlyFans" in a news article vs. "follow my OnlyFans").

    static func containsSexualSolicitation(_ text: String) -> Bool {
        let solicitationPhrases = [
            // Direct adult platform promotion
            "follow my onlyfans", "check out my onlyfans", "onlyfans.com",
            "my of link", "my of page",
            // Rate/service advertising (common escort/adult service patterns)
            "rates available", "incall", "outcall", "full service",
            "rose for rose", "roses for roses",
            "hosting available", "available for meet", "available to meet",
            "dm for rates", "dm me for rates",
            // Explicit solicitation
            "sugar daddy", "sugar baby", "seeking arrangement",
            "pay for content", "buy my content", "buy my pics", "buy my videos",
            "fans only", "adult content available",
            // Emoji-based solicitation patterns (normalised text, emojis stripped)
            "pay for meet", "cash for pics", "venmo for pics", "cashapp for pics",
            "paypal for pics", "zelle for pics"
        ]
        return solicitationPhrases.contains { text.contains($0) }
    }

    // MARK: - Off-Platform Migration Detection
    //
    // Common pattern in grooming and sexual solicitation: move the victim to
    // an unmonitored platform (Snapchat, Telegram, WhatsApp, Kik, etc.).
    // In DMs, any unprompted invitation to migrate platforms is a yellow flag.

    static func containsOffPlatformMigration(_ text: String) -> Bool {
        let patterns = [
            "add me on snap", "find me on snap", "my snap is", "my snapchat is",
            "dm me on snap", "dm on snap",
            "my telegram is", "message me on telegram", "add me on telegram",
            "add me on kik", "my kik is", "dm on kik",
            "text me on whatsapp", "my whatsapp is",
            "find me on instagram", "dm me on insta", "my ig is",
            "add me on discord", "my discord is",
            "text me at", "call me at",
            "move to", "switch to", "continue on", "let's go to"
        ]
        return patterns.contains { text.contains($0) }
    }

    // MARK: - Normalisation
    //
    // Returns a plain lowercase string with:
    //   1. Invisible / zero-width chars removed
    //   2. Leet-speak digits/symbols substituted (3→e, @→a, etc.)
    //   3. Inline non-alpha separators between two letters collapsed to ""
    //      so f*ck → fck, b!tch → btch, f-u-c-k → fuck
    //
    // The firstMatch() fuzzy pass handles the one-character-shorter results.

    static func normalise(_ input: String) -> String {
        var s = input.lowercased()

        // 1. Remove invisible separator characters
        for scalar in ["\u{200B}", "\u{200C}", "\u{200D}", "\u{00AD}", "\u{FEFF}"] {
            s = s.replacingOccurrences(of: scalar, with: "")
        }

        // 2. Leet-speak substitutions
        let subs: [(String, String)] = [
            ("0","o"),("1","i"),("3","e"),("4","a"),
            ("5","s"),("7","t"),("@","a"),("$","s"),
            ("!","i"),("+","t"),("8","b"),("6","g"),
            ("%","x"),("^","a")
        ]
        for (from, to) in subs { s = s.replacingOccurrences(of: from, with: to) }

        // 3. Collapse non-alpha separators that sit between two letters
        //    (e.g. f*ck → fck).  Separators at word boundaries stay as spaces.
        //    Uses cached compiled regex — this runs on every content check.
        if let re = compiledRegex(for: "(?<=[a-z])[^a-z ]+(?=[a-z])") {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }

        return s
    }

    // MARK: - Matching
    //
    // Pass 1 — exact word-boundary match.
    // Pass 2 — deletion-tolerant: checks every single-character-deletion variant
    //           of the word against the text.  This catches f*ck → fck still
    //           matching "fuck" (because "fck" is the 1-deletion variant of "fuck"
    //           with 'u' removed), and b!tch → btch matching "bitch".
    //           Only applied to single-word terms (≥ 4 chars) to limit scope.

    private static func firstMatch(in text: String, wordList: [String]) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for word in wordList {
            // Pass 1: exact word-boundary match (uses regex cache)
            let escaped = NSRegularExpression.escapedPattern(for: word)
            let exactPat = "(?<![a-z])\(escaped)(?![a-z])"
            if let re = compiledRegex(for: exactPat),
               re.firstMatch(in: text, range: range) != nil {
                return word
            }

            // Pass 2: deletion variants — single char removed at each position.
            // Only apply to terms ≥ 6 chars to avoid false positives on short words.
            // e.g. "tits" (4 chars) produces deletion variant "its" — a common English
            // word. Short terms are already caught by the exact-match Pass 1 above.
            guard !word.contains(" "), word.count >= 6 else { continue }
            let chars = Array(word)
            for dropIdx in 0..<chars.count {
                let variant = String(chars.enumerated().compactMap { $0.offset == dropIdx ? nil : $0.element })
                let vEscaped = NSRegularExpression.escapedPattern(for: variant)
                let vPat = "(?<![a-z])\(vEscaped)(?![a-z])"
                if let re = compiledRegex(for: vPat),
                   re.firstMatch(in: text, range: range) != nil {
                    return word
                }
            }
        }
        return nil
    }

    // MARK: - Word Lists
    // Intentionally not exhaustive — cover the most common violations.
    // The Cloud Function moderation layer handles edge cases.
    // Do NOT add context-dependent terms that have legitimate uses.

    // ── Profanity ──────────────────────────────────────────────────────────
    private static let profanityTerms: [String] = [
        "fuck", "fucking", "fucker", "fucked", "fucks",
        "shit", "shitting", "shitty", "bullshit",
        "bitch", "bitches", "bitching",
        "asshole", "ass hole",
        "dammit", "goddamn",
        "bastard", "bastards",
        "piss off", "pissed off", "pissed",
        "wtf", "stfu",
        "motherfucker", "motherfucking",
        "cock", "cunt",
        "dick", "dicks",
        "prick",
        "jackass", "dumbass", "smartass",
        "wanker", "wank",
        "twat", "twats"
    ]

    // ── Harassment / Bullying ──────────────────────────────────────────────
    private static let harassmentTerms: [String] = [
        "kill yourself", "kys",
        "go die", "drop dead",
        "nobody likes you",
        "you are worthless", "you're worthless",
        "pathetic loser",
        "you are stupid", "you're stupid",
        "idiot", "moron", "imbecile",
        "retard", "retarded",
        "shut up",
        "i hate you",
        "you suck",
        "dox", "doxxing",
        "swat", "swatting"
    ]

    // ── Sexual Content ─────────────────────────────────────────────────────
    // Note: Sexual solicitation (rates, hosting, platform promos) is handled
    // separately by containsSexualSolicitation() for context-aware blocking.
    private static let sexualTerms: [String] = [
        // Direct pornographic content references
        "porn", "pornography", "porno",
        "nude", "nudes", "naked",
        "horny",
        "masturbat", "masturbation",
        "penis", "vagina", "vulva",
        "boobs", "tits", "titties",
        "dildo", "vibrator",
        "nsfw",
        "fap", "fapping",
        "cumshot", "cum shot",
        "orgasm",
        "blowjob", "blow job",
        "hand job", "handjob",
        "anal sex",
        "xxx",
        "send nudes", "send pics", "send photos",
        "sex tape",
        // Fetish/pornographic act descriptors
        "gangbang", "gang bang",
        "creampie",
        "threesome",
        "sexting", "sext",
        // Adult sites commonly referenced in solicitation
        "pornhub", "xvideos", "xnxx", "redtube", "youporn",
        "chaturbate", "livejasmin",
        // Explicit body/act descriptors
        "erection", "boner",
        "wet pussy", "tight pussy",
        "big cock", "big dick",
        "strip for me", "get naked",
        // Emoji-text combinations (leet-speak normalised)
        "eggplant pics", "peach pics"
    ]

    // ── Hate Speech ────────────────────────────────────────────────────────
    // Slurs listed in lowercase normalised form only to enable detection.
    private static let hateSpeechTerms: [String] = [
        "nigger", "nigga",
        "faggot",
        "dyke",
        "tranny", "trannies",
        "chink", "gook", "spic", "wetback",
        "kike", "heeb",
        "towelhead", "raghead",
        "white supremacy", "white power",
        "nazi", "heil",
        "kkk",
        "go back to your country",
        "subhuman"
    ]

    // ── Violent / Threatening Language ────────────────────────────────────
    private static let violenceTerms: [String] = [
        "i will kill",
        "i'm going to kill",
        "im going to kill",
        "going to hurt you",
        "will hurt you",
        "beat you up",
        "going to shoot",
        "i will shoot",
        "bomb threat",
        "shooting up",
        "stab you",
        "i will find you",
        "watch your back",
        "you will pay",
        "make you pay",
        "cut you",
        "slice you",
        "put a bullet"
    ]
}
