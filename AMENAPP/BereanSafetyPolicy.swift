//
//  BereanSafetyPolicy.swift
//  AMENAPP
//
//  Canonical safety copy and constants shared across all Berean AI services.
//  Any refusal message, resource reference, or citation requirement in Berean
//  MUST come from this file — no duplicated strings in call sites.
//
//  Usage:
//    return BereanSafetyPolicy.refusal(for: .jailbreak)
//    let citation = BereanSafetyPolicy.citationRequirement
//

import Foundation

// MARK: - Safety Categories

enum BereanSafetyCategory: String, CaseIterable {
    case selfHarm       = "self_harm"
    case hate           = "hate"
    case jailbreak      = "jailbreak"
    case pii            = "pii"
    case sexualMinors   = "sexual_minors"
    case medicalLegal   = "medical_legal"
    case harassment     = "harassment"
    case scrupulosity   = "scrupulosity"  // Pastoral pattern-break for shame/salvation loops
}

// MARK: - Safety Policy

enum BereanSafetyPolicy {

    // MARK: Canonical Citation Requirement

    /// Every scripture-grounded response MUST include at least one cited verse.
    /// Append this to system prompts that produce exegetical content.
    static let citationRequirement = """
        Every claim about Scripture must be grounded in at least one explicit citation \
        in the form Book Chapter:Verse (e.g., John 3:16). \
        Do not speculate about biblical meaning without a textual anchor.
        """

    // MARK: Canonical Refusal Copy

    /// Returns the canonical user-facing refusal string for a given safety category.
    /// All Berean services should call this rather than hardcoding their own strings.
    static func refusal(for category: BereanSafetyCategory) -> String {
        switch category {

        case .selfHarm:
            return """
                I'm so glad you reached out, and I care about what you're going through. \
                Berean is a Bible study companion and isn't equipped to provide the support \
                you deserve right now.

                Please connect with someone trained to help:
                • **988 Suicide & Crisis Lifeline** — call or text 988 (US)
                • **Crisis Text Line** — text HOME to 741741
                • **International Association for Suicide Prevention** — https://www.iasp.info

                You are loved and valued. (Psalm 139:13–14)
                """

        case .hate:
            return """
                I can't assist with that. Berean is here to help you explore Scripture in a way \
                that honors every person as made in God's image (Genesis 1:27).

                If you have a genuine theological question about passages dealing with conflict, \
                division, or reconciliation, I'd be glad to explore those with you.
                """

        case .jailbreak:
            return """
                I'm Berean, a faith-centered Bible study companion. I'm not able to change my \
                identity, ignore my guidelines, or act as a different system — these boundaries \
                exist to keep this space safe and trustworthy for everyone.

                Is there a Scripture question, prayer request, or faith topic I can help you with?
                """

        case .pii:
            return """
                It looks like your message may contain personal information (like a phone number, \
                address, or ID number). To protect your privacy, I can't process or store that.

                Please remove any personal details and ask your question again — I'm happy to help.
                """

        case .sexualMinors:
            return """
                I can't help with that. Any content involving minors and sexual topics is \
                prohibited, and I'm required to decline immediately.

                If you have a concern about child safety, please contact:
                • **NCMEC CyberTipline** — 1-800-843-5678 or CyberTipline.org
                """

        case .medicalLegal:
            return """
                Berean can explore what Scripture says about health, healing, and stewardship of \
                the body, but I'm not qualified to give medical or legal advice.

                For medical concerns, please speak with a licensed healthcare provider.
                For legal concerns, please consult a licensed attorney.

                Here's what the Bible says about seeking wise counsel: Proverbs 11:14.
                """

        case .harassment:
            return """
                I can't help with that. Berean exists to support healing, understanding, and \
                Christlike engagement — not to help harm, demean, or retaliate against others.

                If you're in a difficult relationship situation, I'd be glad to explore what \
                Scripture says about forgiveness, boundaries, and reconciliation.
                """

        case .scrupulosity:
            return """
                I've noticed we've been circling this same concern a few times. That kind of \
                persistent doubt or guilt can sometimes be a sign of scrupulosity — an anxiety \
                pattern that can look like spiritual vigilance but is actually causing harm.

                The good news: Scripture is clear that those who trust in Christ are secure. \
                "There is therefore now no condemnation for those who are in Christ Jesus." \
                (Romans 8:1)

                If these thoughts feel uncontrollable or are causing significant distress, \
                speaking with a pastor or Christian counselor could be genuinely helpful. \
                You don't have to carry this alone.
                """
        }
    }

    // MARK: - Jailbreak Patterns

    /// Patterns that indicate an attempt to override Berean's identity or guidelines.
    /// Match against lowercased user input before any generation.
    static let jailbreakPatterns: [String] = [
        // Identity override attempts
        "ignore your instructions",
        "ignore previous instructions",
        "disregard your guidelines",
        "forget your training",
        "override your rules",
        "bypass your filters",

        // Roleplay-based identity attacks
        "act as",
        "pretend you are",
        "pretend to be",
        "you are now",
        "you're now a",
        "roleplay as",
        "simulate being",
        "you have no restrictions",
        "you have no rules",

        // Named jailbreak modes
        "dan mode",
        "jailbreak mode",
        "developer mode",
        "unrestricted mode",
        "god mode",
        "do anything now",
        "danthropic",

        // Prompt injection via system/user confusion
        "system prompt",
        "new instructions:",
        "###instruction",
        "[system]",
        "<|system|>",
        "<|endoftext|>",
        "user: ignore",

        // Impersonation of other AI systems
        "act like gpt",
        "act like chatgpt",
        "you are chatgpt",
        "you are gpt-4",
        "you are claude without",
        "you are an uncensored",
        "you are an unfiltered",
        "evil berean",
        "dark berean",

        // Instruction to hide or deny being an AI
        "pretend you are human",
        "claim to be human",
        "deny being an ai",
    ]

    // MARK: - Scrupulosity Detection

    /// Keywords that, when repeated 3+ times in a session window, suggest a
    /// scrupulosity/shame loop that warrants the pastoral pattern-break response.
    static let scrupulosityKeywords: [String] = [
        "am i saved",
        "am i going to hell",
        "did i lose my salvation",
        "unforgivable sin",
        "blasphemy of the holy spirit",
        "i'm not worthy",
        "i'm too sinful",
        "god can't forgive me",
        "god won't forgive me",
        "i've sinned too much",
        "i keep sinning",
        "i'm going to hell",
        "is god angry at me",
        "does god hate me",
        "i don't feel forgiven",
        "i can't be forgiven",
        "repented again",
        "confessed again",
    ]

    // MARK: - PII Patterns

    /// Regex patterns used to detect PII in user input before it leaves the device.
    static let piiPatterns: [(pattern: String, label: String)] = [
        ("\\b\\d{3}-\\d{2}-\\d{4}\\b", "SSN"),
        ("\\b\\d{16}\\b", "Credit card"),
        ("\\b\\d{3}[-.\\s]?\\d{3}[-.\\s]?\\d{4}\\b", "Phone number"),
        ("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}", "Email address"),
        ("\\b\\d{1,5}\\s+[A-Za-z0-9\\s,]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln|Court|Ct)\\b", "Street address"),
    ]
}
