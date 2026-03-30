//
//  ThinkFirstGuardrailsService.swift
//  AMENAPP
//
//  "Think First" guardrails for posting, commenting, reacting
//  Human-first: gentle prompts, not censorship
//  Only hard-block clear policy violations
//

import Foundation
import Combine

@MainActor
class ThinkFirstGuardrailsService: ObservableObject {
    static let shared = ThinkFirstGuardrailsService()
    
    @Published var isChecking = false
    
    private init() {}
    
    // MARK: - Content Check Result
    
    struct ContentCheckResult {
        let canProceed: Bool
        let action: GuardrailAction
        let violations: [Violation]
        let suggestions: [String]
        let redactions: [Redaction]
        
        enum GuardrailAction {
            case allow              // No issues
            case softPrompt         // Gentle nudge
            case requireEdit        // Must revise
            case block              // Hard policy violation
        }
        
        struct Violation {
            let type: ViolationType
            let severity: Severity
            let message: String
            
            enum ViolationType {
                case pii
                case hate
                case harassment
                case threats
                case sexualMinors
                case selfHarm
                case violence
                case scam
                case spam
                case heated  // Not a violation, just heated language
            }
            
            enum Severity {
                case info       // Just FYI
                case warning    // Consider revising
                case error      // Must fix
                case critical   // Hard block
            }
        }
        
        struct Redaction {
            let original: String
            let replacement: String
            let type: String  // "phone", "email", "address", etc.
        }
    }
    
    // MARK: - Pre-Flight Check
    
    /// Check content before posting/commenting
    func checkContent(_ text: String, context: ContentContext) async -> ContentCheckResult {
        isChecking = true
        defer { isChecking = false }
        
        var violations: [ContentCheckResult.Violation] = []
        var suggestions: [String] = []
        var redactions: [ContentCheckResult.Redaction] = []
        
        // 1. PII Detection
        let piiResults = detectPII(in: text)
        if !piiResults.isEmpty {
            violations.append(ContentCheckResult.Violation(
                type: .pii,
                severity: .warning,
                message: "Personal information detected. Consider removing for privacy."
            ))
            redactions.append(contentsOf: piiResults)
            suggestions.append("Tap to automatically remove personal information")
        }
        
        // 2. Hate Speech Detection
        if containsHateSpeech(text) {
            violations.append(ContentCheckResult.Violation(
                type: .hate,
                severity: .critical,
                message: "This content contains hate speech and cannot be posted."
            ))
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: violations,
                suggestions: [],
                redactions: []
            )
        }
        
        // 3. Harassment Detection
        if containsHarassment(text) {
            violations.append(ContentCheckResult.Violation(
                type: .harassment,
                severity: .critical,
                message: "This content appears to harass or attack someone."
            ))
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: violations,
                suggestions: ["Consider how this might affect the person you're addressing"],
                redactions: []
            )
        }
        
        // 4. Threats Detection
        if containsThreats(text) {
            violations.append(ContentCheckResult.Violation(
                type: .threats,
                severity: .critical,
                message: "Threats of violence are not allowed."
            ))
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: violations,
                suggestions: [],
                redactions: []
            )
        }
        
        // 5. Sexual Content + Minors
        if containsSexualContentMinors(text) {
            violations.append(ContentCheckResult.Violation(
                type: .sexualMinors,
                severity: .critical,
                message: "This content violates our policy on minors."
            ))
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: violations,
                suggestions: [],
                redactions: []
            )
        }
        
        // 6. Self-Harm Detection
        if containsSelfHarm(text) {
            violations.append(ContentCheckResult.Violation(
                type: .selfHarm,
                severity: .critical,
                message: "We're concerned about this content. Please reach out for help."
            ))
            suggestions.append("National Suicide Prevention Lifeline: 988")
            suggestions.append("Crisis Text Line: Text HOME to 741741")
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: violations,
                suggestions: suggestions,
                redactions: []
            )
        }
        
        // 7. Sexual Solicitation (rates, hosting, adult platform promotion)
        if containsSexualSolicitation(text) {
            violations.append(ContentCheckResult.Violation(
                type: .sexualMinors,   // re-uses existing violation type; policy code = SEXUAL_HARASS
                severity: .critical,
                message: "Sexual solicitation isn't allowed on AMEN. This content cannot be posted."
            ))
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: violations,
                suggestions: [],
                redactions: []
            )
        }

        // 8. Off-Platform Migration in DMs
        if context == .message && containsOffPlatformMigration(text) {
            violations.append(ContentCheckResult.Violation(
                type: .scam,
                severity: .error,
                message: "For your safety, AMEN asks that you keep conversations here. Moving to other apps removes safety protections."
            ))
            return ContentCheckResult(
                canProceed: false,
                action: .requireEdit,
                violations: violations,
                suggestions: ["Keep the conversation within AMEN for safety"],
                redactions: []
            )
        }

        // 9. Scam Detection
        if containsScam(text) {
            violations.append(ContentCheckResult.Violation(
                type: .scam,
                severity: .critical,
                message: "This appears to be a scam or fraudulent offer."
            ))
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: violations,
                suggestions: [],
                redactions: []
            )
        }
        
        // 8. Spam Detection
        let spamScore = calculateSpamScore(text)
        if spamScore > 0.7 {
            violations.append(ContentCheckResult.Violation(
                type: .spam,
                severity: .error,
                message: "This looks like spam. Please post authentic content."
            ))
            suggestions.append("Use normal capitalization")
            suggestions.append("Avoid excessive repeated characters")
            return ContentCheckResult(
                canProceed: false,
                action: .requireEdit,
                violations: violations,
                suggestions: suggestions,
                redactions: []
            )
        }
        
        // 9. Heated Language (Soft Prompt - Politics/Hot Topics)
        if context == .politicalTopic && isHeatedLanguage(text) {
            violations.append(ContentCheckResult.Violation(
                type: .heated,
                severity: .info,
                message: "This seems heated. Want to rephrase?"
            ))
            suggestions.append("Consider a more measured tone")
            suggestions.append("Focus on ideas, not attacks")
            
            // Soft prompt only - can still proceed
            return ContentCheckResult(
                canProceed: true,
                action: .softPrompt,
                violations: violations,
                suggestions: suggestions,
                redactions: redactions
            )
        }
        
        // All clear or minor issues only
        if !violations.isEmpty || !redactions.isEmpty {
            return ContentCheckResult(
                canProceed: true,
                action: .softPrompt,
                violations: violations,
                suggestions: suggestions,
                redactions: redactions
            )
        }
        
        return ContentCheckResult(
            canProceed: true,
            action: .allow,
            violations: [],
            suggestions: [],
            redactions: []
        )
    }
    
    // MARK: - PII Detection
    
    private func detectPII(in text: String) -> [ContentCheckResult.Redaction] {
        var redactions: [ContentCheckResult.Redaction] = []
        
        // Phone numbers
        let phonePattern = "\\b\\d{3}[-.]?\\d{3}[-.]?\\d{4}\\b"
        if let regex = try? NSRegularExpression(pattern: phonePattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    redactions.append(ContentCheckResult.Redaction(
                        original: String(text[range]),
                        replacement: "[phone number removed]",
                        type: "phone"
                    ))
                }
            }
        }
        
        // Email addresses
        let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    redactions.append(ContentCheckResult.Redaction(
                        original: String(text[range]),
                        replacement: "[email removed]",
                        type: "email"
                    ))
                }
            }
        }
        
        // SSN (simple pattern)
        let ssnPattern = "\\b\\d{3}-\\d{2}-\\d{4}\\b"
        if let regex = try? NSRegularExpression(pattern: ssnPattern) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    redactions.append(ContentCheckResult.Redaction(
                        original: String(text[range]),
                        replacement: "[removed for privacy]",
                        type: "ssn"
                    ))
                }
            }
        }
        
        return redactions
    }
    
    // MARK: - Content Detection (Pattern-Based)
    
    // MARK: - Text Normalization (matches server-side normalizeText)

    /// Normalize text to defeat common evasion tactics (leet-speak, punctuation splitting,
    /// repeated characters) before keyword matching.
    private func normalizeText(_ text: String) -> String {
        var s = text.lowercased()
        // Leet-speak substitutions
        s = s.replacingOccurrences(of: "0", with: "o")
        s = s.replacingOccurrences(of: "1", with: "i")
        s = s.replacingOccurrences(of: "3", with: "e")
        s = s.replacingOccurrences(of: "4", with: "a")
        s = s.replacingOccurrences(of: "5", with: "s")
        s = s.replacingOccurrences(of: "6", with: "g")
        s = s.replacingOccurrences(of: "7", with: "t")
        s = s.replacingOccurrences(of: "8", with: "b")
        s = s.replacingOccurrences(of: "9", with: "g")
        s = s.replacingOccurrences(of: "@", with: "a")
        s = s.replacingOccurrences(of: "$", with: "s")
        s = s.replacingOccurrences(of: "!", with: "i")
        s = s.replacingOccurrences(of: "+", with: "t")
        s = s.replacingOccurrences(of: "|", with: "i")
        // Strip non-alpha non-space characters
        s = s.replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
        // Collapse runs of 3+ repeated characters to 2 (e.g. "fuuuck" → "fuuck")
        s = s.replacingOccurrences(of: "(.)\\1{2,}", with: "$1$1", options: .regularExpression)
        // Collapse whitespace
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return s
    }

    private func containsHateSpeech(_ text: String) -> Bool {
        let normalized = normalizeText(text)
        // Slurs and identity-based hate — drawn from server moderationLexicon.hate
        let hateTerms = [
            "nigger", "nigga",
            "wetback", "spic", "beaner",
            "chink", "gook",
            "kike",
            "raghead", "towelhead",
            "faggot", "fag",
            "dyke",
            "tranny",
            "retard",
            "go back to your country",
            "subhuman",
            "white supremacy",
            "heil",
            "kkk",
            "nazi"
        ]
        if hateTerms.contains(where: { normalized.contains($0) }) { return true }

        // Regex patterns for contextual hate
        let regexPatterns = [
            "\\bhate\\s+(blacks|whites|jews|muslims|gays|christians)\\b",
            "\\bburn\\s+in\\s+hell\\b",
            "\\bkill\\s+all\\b",
            "\\bdeserve\\s+to\\s+die\\b"
        ]
        for pattern in regexPatterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil { return true }
        }

        return false
    }

    private func containsHarassment(_ text: String) -> Bool {
        let normalized = normalizeText(text)
        // Matches server moderationLexicon.harassment
        let patterns = [
            "kill yourself", "kys", "drop dead", "you should die",
            "i hope you die", "nobody wants you", "go hang yourself",
            "attack you", "destroy you", "ruin your life",
            "you're worthless", "nobody likes you",
            "stupid", "idiot", "dumbass", "moron", "loser",
            "trash", "ugly", "worthless", "freak", "weirdo"
        ]
        return patterns.contains { normalized.contains($0) }
    }

    private func containsThreats(_ text: String) -> Bool {
        let normalized = normalizeText(text)
        // Matches server moderationLexicon.threats
        let patterns = [
            "i will kill you", "i will kill", "im going to kill",
            "i will hurt you", "ill find you",
            "watch your back", "shoot you", "stab you",
            "beat your ass", "rape you", "put a bullet",
            "i know where you live", "pull up on you",
            "i'll kill you", "you're dead", "find you and"
        ]
        return patterns.contains { normalized.contains($0) }
    }
    
    private func containsSexualContentMinors(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Hard signals that always flag regardless of other terms
        let hardGroomingPhrases = [
            "our little secret", "keep this between us", "don't tell your parents",
            "dont tell your parents", "don't tell mom", "don't tell dad",
            "our secret", "just between us", "no one has to know",
            "i can teach you", "let me show you", "meet me alone",
            "come to my house", "come over alone",
            "you're so mature for your age", "you're mature for your age",
            "you act older than you are", "you seem older",
            "jailbait", "underage",
            "how old are you", "how old r u", "what grade are you"
        ]
        if hardGroomingPhrases.contains(where: { lowercased.contains($0) }) {
            return true
        }

        // Age mention + sexual context (existing logic, expanded)
        let minorTerms = [
            "child", "kid", "minor", "teenager", "teen", "student",
            "preteen", "pre-teen", "tween", "little girl", "little boy",
            "young girl", "young boy", "school girl", "schoolgirl", "school boy"
        ]
        let sexualTerms = [
            "sexual", "nude", "explicit", "sexy", "naked", "horny",
            "send pics", "send photos", "take a picture", "take a photo",
            "show me", "i want to see", "pretty", "hot girl", "hot boy",
            "meet up", "meet in person", "come over"
        ]

        let hasMinor = minorTerms.contains { lowercased.contains($0) }
        let hasSexual = sexualTerms.contains { lowercased.contains($0) }

        return hasMinor && hasSexual
    }

    private func containsSexualSolicitation(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        // Delegate to LocalContentGuard's context-aware detection
        return LocalContentGuard.containsSexualSolicitation(lowercased)
    }

    private func containsOffPlatformMigration(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return LocalContentGuard.containsOffPlatformMigration(lowercased)
    }
    
    private func containsSelfHarm(_ text: String) -> Bool {
        let normalized = normalizeText(text)
        // Matches server moderationLexicon.selfHarm
        let patterns = [
            "kill myself", "end my life", "end it all",
            "suicide", "suicidal", "cut myself", "self harm",
            "want to die", "no reason to live", "i cant go on",
            "take my own life", "better off dead", "not worth living",
            "overdose on purpose", "commit suicide"
        ]
        return patterns.contains { normalized.contains($0) }
    }
    
    private func containsScam(_ text: String) -> Bool {
        let normalized = normalizeText(text)
        // Matches server moderationLexicon.fraud
        let patterns = [
            "click here to claim", "free money", "you've won", "send gift cards",
            "verify your account here", "send otp", "send the code",
            "investment guaranteed", "flip your money", "claim your prize",
            "wire me", "cash app only", "i am from support",
            "your account will be suspended", "click here to verify", "send first"
        ]
        return patterns.contains { normalized.contains($0) }
    }
    
    private func calculateSpamScore(_ text: String) -> Double {
        var score: Double = 0.0
        
        // Excessive caps
        let uppercaseCount = text.filter { $0.isUppercase }.count
        let uppercaseRatio = Double(uppercaseCount) / Double(max(text.count, 1))
        if uppercaseRatio > 0.6 && text.count > 20 {
            score += 0.4
        }
        
        // Repeated characters
        let repeatedPattern = "(.)\\1{5,}"
        if text.range(of: repeatedPattern, options: .regularExpression) != nil {
            score += 0.3
        }
        
        // Excessive emojis
        let emojiCount = text.unicodeScalars.filter { $0.properties.isEmoji }.count
        if Double(emojiCount) / Double(max(text.count, 1)) > 0.3 {
            score += 0.2
        }
        
        return min(1.0, score)
    }
    
    private func isHeatedLanguage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let heatedTerms = [
            "idiots",
            "morons",
            "stupid people",
            "wake up",
            "sheeple",
            "brainwashed",
            "completely wrong"
        ]
        
        let heatedCount = heatedTerms.filter { lowercased.contains($0) }.count
        return heatedCount >= 2  // Multiple heated terms
    }
    
    // MARK: - Apply Redactions
    
    func applyRedactions(_ text: String, redactions: [ContentCheckResult.Redaction]) -> String {
        var result = text
        
        for redaction in redactions {
            result = result.replacingOccurrences(of: redaction.original, with: redaction.replacement)
        }
        
        return result
    }
}

// MARK: - Content Context

enum ContentContext {
    case normalPost
    case politicalTopic
    case comment
    case commentReply   // Used by SmartReplySuggestionService for Dynamic Island chip moderation
    case reaction
    case message
}

// MARK: - Synchronous guardrail check (for pre-moderated AI suggestions)

extension ThinkFirstGuardrailsService {
    /// Lightweight synchronous check used to moderate AI-generated reply suggestions.
    /// Runs only pattern-based detection (no async network calls), suitable for
    /// rapid gating of short suggestion strings (≤60 chars).
    /// Returns a `ContentCheckResult` with `.allow` or `.block` action.
    func check(text: String, context: ContentContext) -> ContentCheckResult {
        let lower = text.lowercased()

        // Hard-block any suggestion containing hate/harassment/violence/self-harm keywords
        // (These are AI-generated strings; policy violations would be extraordinary but must be gated.)
        let hardBlockPatterns: [String] = [
            "kill", "die", "hurt", "hate you", "worthless", "shut up",
            "go to hell", "idiot", "stupid", "moron"
        ]
        for pattern in hardBlockPatterns where lower.contains(pattern) {
            return ContentCheckResult(
                canProceed: false,
                action: .block,
                violations: [ContentCheckResult.Violation(
                    type: .harassment,
                    severity: .critical,
                    message: "Suggestion blocked by safety guardrail."
                )],
                suggestions: [],
                redactions: []
            )
        }

        return ContentCheckResult(
            canProceed: true,
            action: .allow,
            violations: [],
            suggestions: [],
            redactions: []
        )
    }
}
