// PromptPolicyEngine.swift
// AMENAPP
//
// Spiritual integrity + safety guardrails for every AI prompt.
// Evaluates requests BEFORE they reach any model provider.
// Versioned policies make rule changes auditable and rollback-safe.
//
// Responsibilities:
//   - Block or transform prompts that violate policy
//   - Enforce spiritual integrity (no blasphemy, heresy framing, manipulation)
//   - Detect prompt injection / jailbreak attempts
//   - Inject appropriate system context per surface
//   - Rate limiting per user per surface
//   - Policy versioning for audit trails

import Foundation
import NaturalLanguage

// MARK: - Policy Result

struct PolicyResult {
    let shouldBlock: Bool
    let blockReason: String?
    let transformedInput: String?   // sanitized version if transformed (not blocked)
    let injectedContext: [String]   // additional context to inject into prompt
    let riskScore: Double           // 0-1.0
    let appliedPolicies: [String]   // which policy IDs triggered
    let policyVersion: String
}

// MARK: - Policy Rule

struct PolicyRule: Identifiable {
    let id: String
    let name: String
    let description: String
    let version: String
    let action: PolicyAction
    let evaluate: (BereanAIRequest) -> Double  // returns risk score 0-1.0
}

enum PolicyAction {
    case block(reason: String)
    case transform((String) -> String)
    case flag(reason: String)
    case injectContext(String)
    case rateLimit(maxPerHour: Int)
    case allow
}

// MARK: - Rate Limit Tracker

private struct RateLimitState {
    var requestsThisHour: Int = 0
    var windowStart: Date = Date()

    mutating func record() {
        let now = Date()
        if now.timeIntervalSince(windowStart) > 3600 {
            requestsThisHour = 1
            windowStart = now
        } else {
            requestsThisHour += 1
        }
    }

    func isOverLimit(_ max: Int) -> Bool {
        if Date().timeIntervalSince(windowStart) > 3600 { return false }
        return requestsThisHour >= max
    }
}

// MARK: - PromptPolicyEngine

@MainActor
final class PromptPolicyEngine {

    static let shared = PromptPolicyEngine()

    private let currentPolicyVersion = "2.1.0"
    private var rateLimitMap: [String: RateLimitState] = [:]  // userId:surface → state
    private let maxRateLimitEntries = 5000

    // MARK: Policy Registry

    private lazy var rules: [PolicyRule] = buildRules()

    private init() {}

    // MARK: - Primary Evaluation

    func evaluate(_ request: BereanAIRequest) async -> PolicyResult {
        var riskScore: Double = 0
        var appliedPolicies: [String] = []
        var injectedContext: [String] = []
        var transformedInput: String? = nil

        for rule in rules {
            let score = rule.evaluate(request)
            if score <= 0 { continue }

            riskScore = max(riskScore, score)
            appliedPolicies.append(rule.id)

            switch rule.action {
            case .block(let reason):
                if score >= 0.7 {
                    return PolicyResult(
                        shouldBlock: true,
                        blockReason: reason,
                        transformedInput: nil,
                        injectedContext: [],
                        riskScore: score,
                        appliedPolicies: appliedPolicies,
                        policyVersion: currentPolicyVersion
                    )
                }

            case .transform(let transformer):
                if score >= 0.5 {
                    transformedInput = transformer(request.userInput)
                }

            case .injectContext(let ctx):
                injectedContext.append(ctx)

            case .rateLimit(let max):
                let key = "\(request.userId ?? "anon"):\(request.surface.rawValue)"
                if rateLimitMap[key]?.isOverLimit(max) == true {
                    return PolicyResult(
                        shouldBlock: true,
                        blockReason: "Rate limit reached. Please wait before sending more requests.",
                        transformedInput: nil,
                        injectedContext: [],
                        riskScore: 1.0,
                        appliedPolicies: [rule.id],
                        policyVersion: currentPolicyVersion
                    )
                }

            case .flag, .allow:
                break
            }
        }

        // Record rate limit usage
        if let userId = request.userId {
            let key = "\(userId):\(request.surface.rawValue)"
            if rateLimitMap[key] == nil { rateLimitMap[key] = RateLimitState() }
            rateLimitMap[key]?.record()
            trimRateLimitMap()
        }

        return PolicyResult(
            shouldBlock: false,
            blockReason: nil,
            transformedInput: transformedInput,
            injectedContext: injectedContext,
            riskScore: riskScore,
            appliedPolicies: appliedPolicies,
            policyVersion: currentPolicyVersion
        )
    }

    // MARK: - Policy Rules

    private func buildRules() -> [PolicyRule] {
        [
            // ── Prompt Injection / Jailbreak Detection ────────────────────
            PolicyRule(
                id: "P001",
                name: "Prompt Injection Guard",
                description: "Detects attempts to override system instructions",
                version: "1.0",
                action: .block(reason: "This type of input is not supported."),
                evaluate: { req in
                    let lower = req.userInput.lowercased()
                    let injectionPatterns = [
                        "ignore previous instructions",
                        "ignore all instructions",
                        "disregard your instructions",
                        "forget your guidelines",
                        "you are now",
                        "act as if you",
                        "pretend you are",
                        "simulate being",
                        "bypass your",
                        "jailbreak",
                        "dan mode",
                        "developer mode",
                        "do anything now"
                    ]
                    return injectionPatterns.contains(where: { lower.contains($0) }) ? 0.95 : 0
                }
            ),

            // ── Spiritual Manipulation Guard ──────────────────────────────
            PolicyRule(
                id: "P002",
                name: "Spiritual Manipulation Guard",
                description: "Blocks requests designed to generate manipulative spiritual content",
                version: "1.0",
                action: .block(reason: "This request asks for content that could spiritually harm others."),
                evaluate: { req in
                    let lower = req.userInput.lowercased()
                    let patterns = [
                        "convince people to give money",
                        "manipulate using scripture",
                        "make them feel guilty",
                        "false prophecy",
                        "write a cult",
                        "write a false teaching",
                        "prosperity gospel manipulation",
                        "exploit their faith"
                    ]
                    return patterns.contains(where: { lower.contains($0) }) ? 0.90 : 0
                }
            ),

            // ── Explicit Content Block ────────────────────────────────────
            PolicyRule(
                id: "P003",
                name: "Explicit Content Block",
                description: "Prevents generation of sexually explicit or violent content",
                version: "1.0",
                action: .block(reason: "This type of content cannot be generated here."),
                evaluate: { req in
                    let lower = req.userInput.lowercased()
                    let explicit = ["write explicit", "sexual content", "nude", "erotica", "graphic violence", "torture instructions"]
                    return explicit.contains(where: { lower.contains($0) }) ? 0.95 : 0
                }
            ),

            // ── Personal Information Guard ─────────────────────────────────
            PolicyRule(
                id: "P004",
                name: "PII Input Guard",
                description: "Detects and sanitizes PII in prompts",
                version: "1.0",
                action: .transform { input in
                    // Strip SSN-like patterns
                    var cleaned = input
                    let ssnPattern = "\\b\\d{3}-\\d{2}-\\d{4}\\b"
                    if let regex = try? NSRegularExpression(pattern: ssnPattern) {
                        cleaned = regex.stringByReplacingMatches(
                            in: cleaned,
                            range: NSRange(cleaned.startIndex..., in: cleaned),
                            withTemplate: "[REDACTED]"
                        )
                    }
                    return cleaned
                },
                evaluate: { req in
                    let patterns = ["my ssn is", "my social security", "my credit card", "my bank account number"]
                    let lower = req.userInput.lowercased()
                    return patterns.contains(where: { lower.contains($0) }) ? 0.6 : 0
                }
            ),

            // ── Crisis Passthrough ────────────────────────────────────────
            PolicyRule(
                id: "P005",
                name: "Crisis Context Injection",
                description: "Injects crisis-aware context when distress signals detected",
                version: "1.0",
                action: .injectContext("If the user appears to be in crisis, respond with compassion and surface appropriate resources. Never make light of emotional pain."),
                evaluate: { req in
                    let lower = req.userInput.lowercased()
                    let crisisSignals = ["want to die", "end my life", "can't go on", "no reason to live",
                                         "hurt myself", "hopeless", "suicidal", "give up on life"]
                    return crisisSignals.contains(where: { lower.contains($0) }) ? 0.85 : 0
                }
            ),

            // ── Theological Humility Injection ────────────────────────────
            PolicyRule(
                id: "P006",
                name: "Theological Humility Context",
                description: "Injects humility reminder for doctrinally debated topics",
                version: "1.0",
                action: .injectContext("This topic involves theological debate. Present the main perspectives with humility. Do not assert one view as definitively correct. Cite scripture where possible."),
                evaluate: { req in
                    let debatedTopics = ["predestination", "calvinism", "arminianism", "baptism mode",
                                          "rapture", "cessationism", "tongues", "end times", "eschatology",
                                          "once saved always saved", "women in ministry"]
                    let lower = req.userInput.lowercased()
                    return debatedTopics.contains(where: { lower.contains($0) }) ? 0.7 : 0
                }
            ),

            // ── Rate Limiting: Berean Chat ────────────────────────────────
            PolicyRule(
                id: "P007",
                name: "Berean Chat Rate Limit",
                description: "Prevents excessive Berean chat usage",
                version: "1.0",
                action: .rateLimit(maxPerHour: 60),
                evaluate: { req in req.surface == .bereanChat ? 0.5 : 0 }
            ),

            // ── Rate Limiting: Safety-Critical Surfaces ───────────────────
            PolicyRule(
                id: "P008",
                name: "Safety Surface Rate Limit",
                description: "Higher limits for safety-critical surfaces",
                version: "1.0",
                action: .rateLimit(maxPerHour: 200),
                evaluate: { req in
                    (req.surface == .prayerRequest || req.surface == .dm) ? 0.3 : 0
                }
            ),

            // ── Scripture Citation Injection ──────────────────────────────
            PolicyRule(
                id: "P009",
                name: "Scripture Citation Requirement",
                description: "Reminds AI to cite scripture for theological claims",
                version: "1.0",
                action: .injectContext("When making theological claims, always cite specific Bible verses. Use the format [Book Chapter:Verse] inline."),
                evaluate: { req in
                    req.category == .scriptureGrounding || req.category == .assistantResponse ? 0.5 : 0
                }
            ),

            // ── DM Privacy Guard ─────────────────────────────────────────
            PolicyRule(
                id: "P010",
                name: "DM Privacy Minimum Processing",
                description: "Ensures DM content is processed minimally and privately",
                version: "1.0",
                action: .injectContext("This is a private message. Process only for safety assessment. Do not store, reference, or summarize content beyond what is needed for the safety decision."),
                evaluate: { req in req.surface == .dm ? 1.0 : 0 }
            ),

            // ── Hate Speech / Extremism Block ─────────────────────────────
            PolicyRule(
                id: "P011",
                name: "Hate Speech Block",
                description: "Blocks requests to generate hate speech or extremist content",
                version: "1.0",
                action: .block(reason: "This content is not allowed on AMEN."),
                evaluate: { req in
                    let patterns = ["write hate speech", "attack [group]", "write extremist", "radicalize"]
                    let lower = req.userInput.lowercased()
                    return patterns.contains(where: { lower.contains($0) }) ? 0.95 : 0
                }
            ),

            // ── Minor Safety ─────────────────────────────────────────────
            PolicyRule(
                id: "P012",
                name: "Minor Safety Context",
                description: "Extra protection for younger users",
                version: "1.0",
                action: .injectContext("Respond with age-appropriate language and guidance. Prioritize safety and well-being."),
                evaluate: { req in
                    req.context["user_age_group"] == "minor" ? 0.9 : 0
                }
            ),
        ]
    }

    private func trimRateLimitMap() {
        if rateLimitMap.count > maxRateLimitEntries {
            // Evict oldest windows
            let sorted = rateLimitMap.sorted { $0.value.windowStart < $1.value.windowStart }
            let toRemove = sorted.prefix(rateLimitMap.count - maxRateLimitEntries)
            toRemove.forEach { rateLimitMap.removeValue(forKey: $0.key) }
        }
    }
}
