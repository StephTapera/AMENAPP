// BereanIntentSwitchService.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 2)
//
// Local heuristic classifier that proposes (BereanMode × BereanDepth) for a given
// input text. No network call. The LLM-backed version is deferred to a later wave.
//
// Flag guard: when bereanIntentSwitchEnabled is false, returns a default .ask/.study
// pass-through proposal with autoSelected: false.

import Foundation

@MainActor
final class BereanIntentSwitchService {

    static let shared = BereanIntentSwitchService()
    private init() {}

    // MARK: - Propose

    /// Proposes a (mode × depth) pair for a given input text and thread context.
    /// Performs only local pattern matching — no network call.
    func propose(for text: String, threadId: String) -> IntentProposal {
        guard AMENFeatureFlags.shared.bereanIntentSwitchEnabled else {
            return defaultProposal(threadId: threadId)
        }

        let lower = text.lowercased()

        // Distress / prayer patterns — GUARDIAN: emit distress signal log
        if containsAny(lower, patterns: ["struggling", "anxious", "afraid", "hurting", "feeling"]) {
            dlog("[BereanIntentSwitch][GUARDIAN] Distress signal detected in thread \(threadId)")
            return IntentProposal(
                mode: .reflect,
                depth: .quick,
                confidence: 0.9,
                rationale: "Reflecting with you",
                autoSelected: true
            )
        }

        if containsAny(lower, patterns: ["pray", "prayer request", "intercede"]) {
            return IntentProposal(
                mode: .reflect,
                depth: .quick,
                confidence: 0.9,
                rationale: "Prayer mode",
                autoSelected: true
            )
        }

        // Sermon / build patterns
        if containsAny(lower, patterns: ["sermon", "prepare", "outline", "preach", "study guide for"]) {
            return IntentProposal(
                mode: .build,
                depth: .study,
                confidence: 0.9,
                rationale: "Building a study",
                autoSelected: true
            )
        }

        // Discern / apologetics patterns
        if containsAny(lower, patterns: [
            "examine", "analyze", "compare", "case for",
            "apologetics", "infant baptism", "original language"
        ]) {
            return IntentProposal(
                mode: .discern,
                depth: .deep,
                confidence: 0.9,
                rationale: "Examining deeply",
                autoSelected: true
            )
        }

        // Explain / ask patterns
        if containsExplainPattern(lower) {
            return IntentProposal(
                mode: .ask,
                depth: .study,
                confidence: 0.9,
                rationale: "Studying this passage",
                autoSelected: true
            )
        }

        // Default pass-through
        return defaultProposal(threadId: threadId)
    }

    // MARK: - Apply Override

    /// Merges a user override with an existing proposal.
    func applyOverride(_ override: IntentOverride, to proposal: IntentProposal) -> IntentProposal {
        IntentProposal(
            mode: override.mode ?? proposal.mode,
            depth: override.depth ?? proposal.depth,
            confidence: proposal.confidence,
            rationale: proposal.rationale,
            autoSelected: false
        )
    }

    // MARK: - Private Helpers

    private func defaultProposal(threadId: String) -> IntentProposal {
        IntentProposal(
            mode: .ask,
            depth: .study,
            confidence: 0.5,
            rationale: "Studying",
            autoSelected: false
        )
    }

    private func containsAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    /// Matches "what does X mean", "explain", "what is" style queries.
    private func containsExplainPattern(_ text: String) -> Bool {
        let patterns = ["what does", "explain", "what is", "meaning of", "means"]
        return containsAny(text, patterns: patterns)
    }
}
