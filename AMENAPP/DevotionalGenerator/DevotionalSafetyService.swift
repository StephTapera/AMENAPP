//
//  DevotionalSafetyService.swift
//  AMENAPP
//
//  Content guardrails for generated devotionals.
//  Applies keyword-based and structural safety checks, then annotates
//  the DevotionalResponse with a guardrail notice when needed.
//  This runs locally (no network call) so it never delays generation.
//

import Foundation

@MainActor
final class DevotionalSafetyService {
    static let shared = DevotionalSafetyService()
    private init() {}

    // MARK: - Blocked Terms by Safety Mode

    private let strictBlockedTerms: [String] = [
        // Graphic violence
        "murder", "kill yourself", "suicide", "self-harm", "violence",
        // Sexually explicit
        "pornography", "explicit", "sexual",
        // Occult / spiritually harmful
        "witchcraft", "séance", "ouija", "satanic", "666",
        // Dark themes (strict mode blocks these)
        "hell", "damnation", "wrath of god", "eternal punishment",
    ]

    private let standardBlockedTerms: [String] = [
        // Content that is never appropriate regardless of mode
        "kill yourself", "suicide instructions", "self-harm instructions",
        "pornography", "satanic ritual",
    ]

    // MARK: - Public API

    /// Applies guardrails to a generated devotional and returns an annotated copy.
    func applyGuardrails(
        to devotional: DevotionalResponse,
        mode: DevotionalSafetyMode
    ) -> DevotionalResponse {
        let issues = detectIssues(in: devotional, mode: mode)
        guard !issues.isEmpty else { return devotional }

        // Build a notice from detected issues
        let notice = buildNotice(for: issues, mode: mode)

        // Return a copy with the notice attached
        return DevotionalResponse(
            requestId: devotional.requestId,
            userId: devotional.userId,
            title: devotional.title,
            openingVerse: devotional.openingVerse,
            additionalScriptures: devotional.additionalScriptures,
            reflection: devotional.reflection,
            prayer: devotional.prayer,
            practice: devotional.practice,
            community: devotional.community,
            guardrailNotice: notice,
            tone: devotional.tone,
            topicTags: devotional.topicTags
        )
    }

    /// Returns true if the topic/context is safe to send to the AI.
    func isTopicSafe(_ topic: String, mode: DevotionalSafetyMode) -> Bool {
        detectTopicIssues(topic: topic, mode: mode).isEmpty
    }

    // MARK: - Detection

    private func detectIssues(
        in devotional: DevotionalResponse,
        mode: DevotionalSafetyMode
    ) -> [SafetyIssue] {
        let fullText = [
            devotional.reflection.body,
            devotional.prayer.body,
            devotional.practice.steps.joined(separator: " "),
            devotional.community?.prompts.joined(separator: " ") ?? "",
        ].joined(separator: " ").lowercased()

        let blockedTerms = blockedTerms(for: mode)
        let foundTerms = blockedTerms.filter { fullText.contains($0) }

        var issues: [SafetyIssue] = []
        for term in foundTerms {
            issues.append(SafetyIssue(term: term, location: "generated content"))
        }

        // Structural: check that prayer doesn't contain off-topic material
        let prayerLower = devotional.prayer.body.lowercased()
        if prayerLower.contains("http://") || prayerLower.contains("https://") {
            issues.append(SafetyIssue(term: "external link", location: "prayer section"))
        }

        return issues
    }

    private func detectTopicIssues(topic: String, mode: DevotionalSafetyMode) -> [SafetyIssue] {
        let lower = topic.lowercased()
        let blockedTerms = blockedTerms(for: mode)
        return blockedTerms
            .filter { lower.contains($0) }
            .map { SafetyIssue(term: $0, location: "topic") }
    }

    private func blockedTerms(for mode: DevotionalSafetyMode) -> [String] {
        switch mode {
        case .strict:   return strictBlockedTerms + standardBlockedTerms
        case .standard: return standardBlockedTerms
        case .open:     return standardBlockedTerms // Only hard blocks; allow lament/dark themes
        }
    }

    // MARK: - Notice Building

    private func buildNotice(
        for issues: [SafetyIssue],
        mode: DevotionalSafetyMode
    ) -> DevotionalGuardrailNotice {
        if mode == .strict {
            return DevotionalGuardrailNotice(
                message: "Some content was filtered to keep this devotional family-friendly.",
                severity: .info
            )
        }

        let hasHardBlock = issues.contains { standardBlockedTerms.contains($0.term) }
        if hasHardBlock {
            return DevotionalGuardrailNotice(
                message: "This devotional has been reviewed for safety. Some sections may have been adjusted.",
                severity: .caution
            )
        }

        return DevotionalGuardrailNotice(
            message: "Note: this devotional engages with challenging themes. Consider your spiritual readiness.",
            severity: .info
        )
    }

    // MARK: - Internal Model

    private struct SafetyIssue {
        let term: String
        let location: String
    }
}
