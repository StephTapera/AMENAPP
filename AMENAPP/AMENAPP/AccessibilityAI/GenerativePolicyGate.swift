//
//  GenerativePolicyGate.swift
//  AMENAPP
//
//  T4 — Constitutional Constraint for generative AI.
//  Hard-blocks client-side before any AI-generative Cloud Function call.
//
//  Rules are derived from AMEN's Constitutional AI policy. No rule can be
//  overridden by a user flag, feature flag, or remote config value.
//  They are compiled into the binary. Backend enforces the same rules
//  server-side; this is a defense-in-depth layer only.
//
//  Usage:
//    try GenerativePolicyGate.validate(request: .testimony(text: draft, isHumanAuthored: true))
//

import Foundation

// MARK: - Generative Request Types

enum GenerativeRequest {
    /// Text written in the Studio. `isHumanAuthored` must be true for testimonies/prayers.
    case testimony(text: String, isHumanAuthored: Bool)
    case prayer(text: String, isHumanAuthored: Bool)
    /// Sermon prep — allowed, but must not be attributed to a specific real pastor.
    case sermonPrep(text: String, attributedToRealPastor: Bool)
    /// Image generation request.
    case imageGeneration(prompt: String, includesFaces: Bool)
    /// Voiceover — must not clone an existing person's voice.
    case voiceover(targetVoiceId: String?, isCloningRealPerson: Bool)
    /// Profile photo — allowed only if explicitly disclosed as AI-generated.
    case profilePhoto(isDisclosedAsAI: Bool)
    /// Generic AI-assisted content — must carry disclosure.
    case aiAssistedContent(contentType: AIContentType, hasDisclosure: Bool)
    /// Any studio-side generation not covered above (pass-through with no restrictions).
    case general
}

// MARK: - GenerativePolicyGate

enum GenerativePolicyGate {

    // MARK: - Validation

    /// Validate a generative request against the Constitutional Constraint rules.
    /// Throws `PolicyGateError.blocked(violations:)` if any fatal rule fires.
    /// Warnings (non-fatal violations) are returned in the thrown error's `warnings` field.
    static func validate(request: GenerativeRequest) throws {
        let violations = evaluate(request: request)
        let fatal = violations.filter { $0.isFatal }
        if !fatal.isEmpty {
            throw PolicyGateError.blocked(violations: fatal)
        }
    }

    /// Non-throwing variant — returns all violations (fatal + warning).
    static func evaluate(request: GenerativeRequest) -> [GenerativePolicyViolation] {
        switch request {
        case .testimony(_, let isHumanAuthored):
            return isHumanAuthored ? [] : [
                GenerativePolicyViolation(
                    rule: .noAITestimonyPosingAsHuman,
                    reason: "Testimony must be human-authored or explicitly disclosed as AI-generated.",
                    isFatal: true
                )
            ]

        case .prayer(_, let isHumanAuthored):
            return isHumanAuthored ? [] : [
                GenerativePolicyViolation(
                    rule: .noAIPrayerPosingAsHuman,
                    reason: "Prayer must be human-authored or explicitly disclosed as AI-generated.",
                    isFatal: true
                )
            ]

        case .sermonPrep(_, let attributedToRealPastor):
            return attributedToRealPastor ? [
                GenerativePolicyViolation(
                    rule: .noDeepfakeSermon,
                    reason: "AI-generated sermon content cannot be attributed to a specific real pastor.",
                    isFatal: true
                )
            ] : []

        case .imageGeneration(_, let includesFaces):
            return includesFaces ? [
                GenerativePolicyViolation(
                    rule: .noAIFaceGeneration,
                    reason: "AI-generated images containing human faces are not permitted.",
                    isFatal: true
                )
            ] : []

        case .voiceover(_, let isCloningRealPerson):
            return isCloningRealPerson ? [
                GenerativePolicyViolation(
                    rule: .noVoiceCloning,
                    reason: "Cloning the voice of a real person is not permitted.",
                    isFatal: true
                )
            ] : []

        case .profilePhoto(let isDisclosedAsAI):
            return isDisclosedAsAI ? [] : [
                GenerativePolicyViolation(
                    rule: .noDefaultAIProfilePhoto,
                    reason: "AI-generated profile photos must carry an explicit AI disclosure.",
                    isFatal: true
                )
            ]

        case .aiAssistedContent(_, let hasDisclosure):
            return hasDisclosure ? [] : [
                GenerativePolicyViolation(
                    rule: .noUndisclosedAIContent,
                    reason: "AI-generated or AI-assisted content must include an AI disclosure before sharing.",
                    isFatal: false   // Warning — display a disclosure prompt, don't hard block.
                )
            ]

        case .general:
            return []
        }
    }
}

// MARK: - PolicyGateError

enum PolicyGateError: LocalizedError {
    case blocked(violations: [GenerativePolicyViolation])

    var errorDescription: String? {
        switch self {
        case .blocked(let violations):
            return violations.first?.reason ?? "This content cannot be generated due to AMEN's AI policy."
        }
    }

    var violations: [GenerativePolicyViolation] {
        switch self {
        case .blocked(let v): return v
        }
    }
}
