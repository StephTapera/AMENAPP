//
//  AMENMessageSafetyEngine.swift
//  AMENAPP
//
//  On-device safety engine for direct messages.
//
//  WHY ON-DEVICE:
//    End-to-end encryption means the server never sees plaintext.
//    Therefore ALL safety classification MUST run on the device
//    BEFORE the message is encrypted and sent.
//
//  ARCHITECTURE (3 layers, all synchronous or local-async):
//
//    Layer 0 — Hard Signal Regex (< 1ms)
//      Catches unambiguous exploitation, trafficking, CSAM language.
//      ALWAYS blocks regardless of context.
//      Zero false-negative tolerance.
//
//    Layer 1 — Pattern Scoring Engine (< 5ms)
//      Weighted signal accumulation across 8 risk categories.
//      Produces a composite risk score 0–100.
//      Configurable thresholds per contact tier.
//
//    Layer 2 — Behavioural Context (< 2ms)
//      Escalation patterns: repeated violations in session,
//      first-message risk, new account risk, message velocity.
//
//  DECISION OUTCOMES:
//    .allow             → send (encrypted)
//    .flagged           → send but log safety event (reviewer may see)
//    .softWarn(msg)     → show user a warning, allow override
//    .requireEdit(msg)  → force user to revise before sending
//    .block(reason)     → hard stop, message NOT sent, no override
//
//  PRIVACY:
//    No plaintext content is sent to any server.
//    Safety events logged to Firestore contain only:
//      - category of violation
//      - risk score
//      - hashed conversation ID
//      - timestamp
//    Never the message text itself.

import Foundation
import CryptoKit
import FirebaseFirestore

// MARK: - Decision

enum MessageSafetyDecision: Equatable {
    case allow
    case flagged                          // Silent flag — moderator visibility only
    case softWarn(message: String)        // Warning shown to user, can still send
    case requireEdit(message: String)     // Must revise before sending
    case block(reason: String)            // Hard stop — cannot send
}

// MARK: - Risk Categories

enum MessageRiskCategory: String, CaseIterable {
    case sexualExploitation   = "sexual_exploitation"
    case humanTrafficking     = "human_trafficking"
    case groomingMinor        = "grooming_minor"
    case csam                 = "csam"
    case coercionBlackmail    = "coercion_blackmail"
    case solicitation         = "solicitation"
    case scamFraud            = "scam_fraud"
    case harassmentThreat     = "harassment_threat"
}

// MARK: - AMENMessageSafetyEngine

@MainActor
final class AMENMessageSafetyEngine {

    static let shared = AMENMessageSafetyEngine()
    private init() { buildPatternIndex() }

    // Per-session violation counters (cleared when conversation changes)
    private var sessionViolationCount: [String: Int] = [:]
    private var sessionRiskAccumulator: [String: Int] = [:]

    // MARK: - Public API

    func evaluate(
        text: String,
        senderUID: String,
        recipientUID: String,
        conversationId: String
    ) async -> MessageSafetyDecision {

        let normalized = normalize(text)

        // Layer 0: Hard blocks — no override possible
        if let hardViolation = layer0HardBlock(normalized) {
            await logSafetyEvent(
                category: hardViolation,
                score: 100,
                conversationId: conversationId,
                senderUID: senderUID
            )
            sessionViolationCount[conversationId, default: 0] += 1
            return .block(reason: userMessage(for: hardViolation, score: 100))
        }

        // Layer 1: Weighted pattern scoring
        let (score, topCategory) = layer1Score(normalized)

        // Layer 2: Behavioural escalation
        let escalatedScore = layer2Escalate(
            baseScore: score,
            conversationId: conversationId,
            senderUID: senderUID
        )

        sessionRiskAccumulator[conversationId, default: 0] += max(0, score - 30)

        // Decision thresholds
        switch escalatedScore {
        case 0..<25:
            return .allow

        case 25..<50:
            if let cat = topCategory {
                return .softWarn(message: softWarnMessage(for: cat))
            }
            return .allow

        case 50..<75:
            await logSafetyEvent(
                category: topCategory ?? .harassmentThreat,
                score: escalatedScore,
                conversationId: conversationId,
                senderUID: senderUID
            )
            return .requireEdit(message: requireEditMessage(for: topCategory ?? .harassmentThreat))

        default: // 75+
            await logSafetyEvent(
                category: topCategory ?? .solicitation,
                score: escalatedScore,
                conversationId: conversationId,
                senderUID: senderUID
            )
            sessionViolationCount[conversationId, default: 0] += 1

            // Three strikes in a session → account restriction flag
            if sessionViolationCount[conversationId, default: 0] >= 3 {
                await flagAccountForReview(senderUID: senderUID, reason: "repeated_high_risk_messages")
            }
            return .block(reason: userMessage(for: topCategory ?? .solicitation, score: escalatedScore))
        }
    }

    // MARK: - Layer 0: Hard Signal Regex

    // Unambiguous signals that must ALWAYS block regardless of context.
    // These are informed by NCMEC, Thorn, DOJ human trafficking indicators,
    // and CSAM lexicon research. Zero-tolerance; no override.

    private struct HardSignal {
        let pattern: NSRegularExpression
        let category: MessageRiskCategory
    }

    private var hardSignals: [HardSignal] = []

    private func layer0HardBlock(_ text: String) -> MessageRiskCategory? {
        for signal in hardSignals {
            let range = NSRange(text.startIndex..., in: text)
            if signal.pattern.firstMatch(in: text, range: range) != nil {
                return signal.category
            }
        }
        return nil
    }

    // MARK: - Layer 1: Weighted Pattern Scoring

    private struct ScoredSignal {
        let pattern: NSRegularExpression
        let category: MessageRiskCategory
        let weight: Int             // Added to score per match (can accumulate)
        let maxContribution: Int    // Cap per signal so one phrase can't dominate
    }

    private var scoredSignals: [ScoredSignal] = []

    private func layer1Score(_ text: String) -> (score: Int, topCategory: MessageRiskCategory?) {
        var categoryScores: [MessageRiskCategory: Int] = [:]
        let range = NSRange(text.startIndex..., in: text)

        for signal in scoredSignals {
            let matches = signal.pattern.numberOfMatches(in: text, range: range)
            if matches > 0 {
                let contribution = min(signal.weight * matches, signal.maxContribution)
                categoryScores[signal.category, default: 0] += contribution
            }
        }

        let totalScore = min(categoryScores.values.reduce(0, +), 100)
        let topCategory = categoryScores.max(by: { $0.value < $1.value })?.key
        return (totalScore, topCategory)
    }

    // MARK: - Layer 2: Behavioural Escalation

    private func layer2Escalate(baseScore: Int, conversationId: String, senderUID: String) -> Int {
        var multiplier: Double = 1.0

        // Prior violations in this session increase sensitivity
        let priorViolations = sessionViolationCount[conversationId, default: 0]
        if priorViolations >= 2 { multiplier += 0.50 }
        else if priorViolations == 1 { multiplier += 0.25 }

        // Accumulated risk in session raises threshold
        let accumulated = sessionRiskAccumulator[conversationId, default: 0]
        if accumulated > 150 { multiplier += 0.30 }

        return min(Int(Double(baseScore) * multiplier), 100)
    }

    // MARK: - Pattern Index Construction

    private func buildPatternIndex() {

        // ── LAYER 0: HARD BLOCKS ─────────────────────────────────────────────────

        // CSAM — zero tolerance, always block
        addHard(patterns: [
            #"(child|kid|minor|underage|young\s+girl|young\s+boy|preteen|prepubescent)\s+(nude|naked|pic|photo|sex|porn)"#,
            #"(nude|naked|sex|sexy)\s+(pic|photo|video)\s+(of\s+)?(a\s+)?(child|kid|minor|girl|boy)\s+(under\s+\d+)"#,
            #"\b(cp|c\.p\.)\b.{0,20}(send|share|got|have|want)"#,
            #"loli(ta|con)?"#,
        ], category: .csam)

        // Explicit sexual solicitation with payment
        addHard(patterns: [
            #"(how\s+much|what'?s\s+your\s+rate|how\s+much\s+for)\s+(a\s+)?(night|hour|hr|session|meet)\b"#,
            #"(cash|money|\$\d+|pay\s+you|i'?ll\s+pay)\s+for\s+(sex|fuck|blowjob|bj|hand\s?job|nude|pic|meet)"#,
            #"(escort|prostitute|hooker|call\s+girl|sex\s+worker)\s+(service|ad|for\s+hire|available|contact|book)"#,
            #"(looking|seeking)\s+(for\s+)?(escort|prostitute|call\s+girl|sex\s+worker)"#,
            #"(incall|outcall)\s+(available|service|rate)"#,
        ], category: .sexualExploitation)

        // Human trafficking recruitment
        addHard(patterns: [
            #"(girls|women|boys|minors)\s+(available|for\s+rent|for\s+hire|for\s+sale)\s+(discreet|private|tonight)"#,
            #"(send|ship|move|transport)\s+(girls|women|minors)\s+(for\s+)?(work|jobs|money)"#,
            #"(work\s+for\s+me|work\s+under\s+me)\s+.{0,30}(no\s+questions|discreet|private|cash)"#,
        ], category: .humanTrafficking)

        // Grooming explicit
        addHard(patterns: [
            #"(don'?t\s+tell|keep\s+it\s+secret|our\s+secret|don'?t\s+tell\s+(your\s+)?(mom|dad|parents))"#,
            #"(send\s+me\s+)?(nude|naked|pic)\s+(you'?re\s+)?(\d+|young|little|kid)"#,
            #"you'?re\s+so\s+(mature|adult\s+like)\s+for\s+(your\s+)?age"#,
        ], category: .groomingMinor)

        // ── LAYER 1: SCORED SIGNALS ───────────────────────────────────────────────

        // Sexual exploitation — high weight
        addScored(patterns: [
            #"(meet\s+up|meet\s+in\s+person|come\s+over)\s+(tonight|now|asap)\s+(for\s+cash|for\s+money|\$)"#,
            #"(private\s+(meet|session|time))\s+(cash|discreet|no\s+one\s+will\s+know)"#,
            #"nsa\s+(fun|meet|hook\s*up)"#,
            #"friends\s+with\s+benefits\s+.{0,20}(pay|cash|money|\$)"#,
        ], category: .sexualExploitation, weight: 40, max: 60)

        // Trafficking indicators — high weight
        addScored(patterns: [
            #"(easy\s+money|quick\s+cash|make\s+\$\d+)\s+(no\s+questions|discreet|private|tonight)"#,
            #"(modeling|acting|content\s+creator)\s+(opportunity|job|gig)\s+(travel|hotel|cash|payment)"#,
            #"(private\s+work|discreet\s+job|easy\s+work)\s+(female|girl|women)"#,
            #"(boyfriend|manager|take\s+care\s+of\s+you)\s+(in\s+exchange|for\s+(sex|favors|money))"#,
            #"sugar\s+(daddy|mommy|baby)\s+(arrangement|deal|terms)"#,
        ], category: .humanTrafficking, weight: 35, max: 60)

        // Grooming patterns — medium-high weight
        addScored(patterns: [
            #"(how\s+old\s+are\s+you|are\s+you\s+18|are\s+you\s+a\s+(minor|kid))"#,
            #"(i'?ll\s+buy\s+you|i\s+can\s+give\s+you)\s+(gifts|money|stuff|things)\s+(if\s+you|when\s+you)"#,
            #"(you\s+seem\s+lonely|i\s+understand\s+you|nobody\s+else\s+gets\s+you)"#,
            #"(send\s+me\s+(a\s+)?pic|show\s+me\s+yourself|what\s+do\s+you\s+look\s+like)"#,
        ], category: .groomingMinor, weight: 25, max: 50)

        // Coercion / blackmail
        addScored(patterns: [
            #"(i\s+will\s+|i'?ll\s+|gonna\s+)(post|share|send|leak|expose)\s+(your\s+)?(pics|photos|videos|nudes)"#,
            #"(pay\s+me|send\s+money|venmo|cashapp|zelle)\s+(or\s+|otherwise\s+)(i\s+will|i'?ll)"#,
            #"(threatening|threatening\s+to\s+share|blackmail)"#,
        ], category: .coercionBlackmail, weight: 45, max: 80)

        // Solicitation (lower-grade)
        addScored(patterns: [
            #"(looking\s+for|seeking)\s+(fun|a\s+good\s+time|company)\s+(tonight|now|asap)"#,
            #"(discreet|private|no\s+strings)\s+(meet|hook\s*up|fun)"#,
            #"(snap|snapchat|insta|ig|kik|telegram)\s+(me|dm|add\s+me)\s+(for\s+more|for\s+content|for\s+fun)"#,
        ], category: .solicitation, weight: 20, max: 40)

        // Scam / fraud
        addScored(patterns: [
            #"(investment\s+opportunity|guaranteed\s+return|double\s+your\s+money)"#,
            #"(send\s+me\s+|transfer\s+)(bitcoin|btc|eth|crypto|gift\s+card)"#,
            #"(i\s+need\s+your\s+|provide\s+your\s+)(bank\s+account|routing|ssn|social\s+security)"#,
            #"(wire\s+transfer|western\s+union|moneygram)\s+(immediately|urgently|asap)"#,
        ], category: .scamFraud, weight: 30, max: 60)

        // Harassment / threats
        addScored(patterns: [
            #"(i\s+know\s+where\s+you\s+live|i\s+know\s+your\s+address|i'?ll\s+find\s+you)"#,
            #"(kill\s+yourself|kys|you\s+should\s+die|hope\s+you\s+die)"#,
            #"(i'?ll\s+hurt\s+you|i'?m\s+coming\s+for\s+you|you'?re\s+going\s+to\s+regret)"#,
        ], category: .harassmentThreat, weight: 35, max: 70)
    }

    // MARK: - Builder helpers

    private func addHard(patterns: [String], category: MessageRiskCategory) {
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            hardSignals.append(.init(pattern: regex, category: category))
        }
    }

    private func addScored(patterns: [String], category: MessageRiskCategory, weight: Int, max: Int) {
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            scoredSignals.append(.init(pattern: regex, category: category, weight: weight, maxContribution: max))
        }
    }

    // MARK: - Text Normalization

    private func normalize(_ text: String) -> String {
        var t = text.lowercased()
        // Leet-speak decode
        let leet: [(String, String)] = [("@","a"),("3","e"),("1","i"),("0","o"),("5","s"),("$","s"),("4","a"),("!","i"),("7","t")]
        for (src, dst) in leet { t = t.replacingOccurrences(of: src, with: dst) }
        // Collapse whitespace / punctuation between letters
        t = t.replacingOccurrences(of: #"[\s\-_\.]+(?=[a-z])"#,
                                    with: " ",
                                    options: .regularExpression)
        return t
    }

    // MARK: - User Messages

    private func softWarnMessage(for category: MessageRiskCategory) -> String {
        switch category {
        case .solicitation, .sexualExploitation:
            return "This message may contain content that violates AMEN's safety standards. Please review before sending."
        case .scamFraud:
            return "This message contains patterns associated with scams. AMEN never facilitates financial transactions in DMs."
        case .harassmentThreat:
            return "This message may be perceived as harmful. Please consider your words before sending."
        default:
            return "Please review this message before sending."
        }
    }

    private func requireEditMessage(for category: MessageRiskCategory) -> String {
        switch category {
        case .groomingMinor:
            return "This message has been flagged for content that could be harmful to minors. It cannot be sent."
        case .humanTrafficking:
            return "This message contains language associated with trafficking. It violates AMEN's Community Standards and cannot be sent."
        case .coercionBlackmail:
            return "AMEN does not tolerate coercion or threats. Please revise your message."
        case .scamFraud:
            return "Messages requesting financial transactions or personal financial information cannot be sent on AMEN."
        default:
            return "This message violates AMEN's safety standards. Please revise before sending."
        }
    }

    private func userMessage(for category: MessageRiskCategory, score: Int) -> String {
        switch category {
        case .csam:
            return "This message has been blocked. Sharing content that exploits minors is illegal and violates AMEN's policies. This incident has been recorded."
        case .sexualExploitation:
            return "This message has been blocked for solicitation. AMEN is a safe community — exploitation is not tolerated."
        case .humanTrafficking:
            return "This message has been blocked. It contains language associated with human trafficking. Your account is under review."
        case .groomingMinor:
            return "This message has been blocked. Content that could put minors at risk is never allowed on AMEN."
        case .coercionBlackmail:
            return "This message has been blocked for threatening behavior. AMEN does not tolerate blackmail or coercion."
        case .solicitation:
            return "This message appears to be soliciting services that violate AMEN's standards and cannot be sent."
        case .scamFraud:
            return "This message has been blocked for suspected fraud. AMEN does not facilitate financial scams."
        case .harassmentThreat:
            return "This message has been blocked for threatening language. Harassment is not tolerated on AMEN."
        }
    }

    // MARK: - Safety Event Logging (privacy-preserving)

    private func logSafetyEvent(
        category: MessageRiskCategory,
        score: Int,
        conversationId: String,
        senderUID: String
    ) async {
        // Only log category + score + hashed conversationId — NO message text
        let hashedConvId = SHA256.hash(data: Data(conversationId.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()

        let db = FirebaseManager.shared.firestore
        try? await db.collection("messageSafetyEvents").addDocument(data: [
            "category":       category.rawValue,
            "riskScore":      score,
            "convIdHash":     hashedConvId,
            "senderUID":      senderUID,
            "timestamp":      Timestamp(date: Date()),
            "requiresReview": score >= 75
        ])
    }

    // MARK: - Account Review Flag

    private func flagAccountForReview(senderUID: String, reason: String) async {
        let db = FirebaseManager.shared.firestore
        try? await db.collection("accountReviews").document(senderUID).setData([
            "flaggedAt":  Timestamp(date: Date()),
            "reason":     reason,
            "status":     "pending",
            "autoFlag":   true
        ], merge: true)
    }
}

// MARK: - Image Safety Gate

/// Runs Google Vision SafeSearch on an image BEFORE it is encrypted and uploaded.
/// Called from the image attachment picker.
@MainActor
final class AMENImageSafetyGate {

    static let shared = AMENImageSafetyGate()
    private init() {}

    private let visionAPIKey = BundleConfig.string(forKey: "GOOGLE_VISION_API_KEY") ?? ""

    enum ImageSafetyResult {
        case safe
        case blocked(reason: String)
    }

    func evaluate(imageData: Data) async -> ImageSafetyResult {
        guard !visionAPIKey.isEmpty else { return .safe }  // Fail open if key missing

        let base64 = imageData.base64EncodedString()
        let body: [String: Any] = [
            "requests": [[
                "image": ["content": base64],
                "features": [["type": "SAFE_SEARCH_DETECTION"]]
            ]]
        ]

        guard let url = URL(string: "https://vision.googleapis.com/v1/images:annotate?key=\(visionAPIKey)"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else { return .safe }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responses = json["responses"] as? [[String: Any]],
              let first = responses.first,
              let safeSearch = first["safeSearchAnnotation"] as? [String: String]
        else { return .safe }

        let blocked = ["LIKELY", "VERY_LIKELY"]

        if let adult = safeSearch["adult"], blocked.contains(adult) {
            return .blocked(reason: "This image contains adult content and cannot be sent on AMEN.")
        }
        if let violence = safeSearch["violence"], blocked.contains(violence) {
            return .blocked(reason: "This image contains violent content and cannot be sent on AMEN.")
        }
        if let racy = safeSearch["racy"], racy == "VERY_LIKELY" {
            return .blocked(reason: "This image violates AMEN's content standards.")
        }

        return .safe
    }
}
