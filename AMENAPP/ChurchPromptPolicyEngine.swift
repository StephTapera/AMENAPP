// ChurchPromptPolicyEngine.swift
// Anti-spam rules engine — decides when a prompt may appear
// AMENAPP

import Foundation

// MARK: - ChurchPromptPolicyEngine

struct ChurchPromptPolicyEngine {

    // MARK: - Public Entry Point

    /// Evaluates all anti-spam rules and returns a decision on whether to show a prompt.
    /// All rules are checked in order; the first failing rule short-circuits evaluation.
    static func shouldShowPrompt(
        _ type: ChurchAssistPromptType,
        assistState: ChurchAssistState
    ) -> ChurchPromptDecision {

        // Rule 1: Church Assist must be enabled globally
        guard assistState.enabled else {
            dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Church assist disabled")
            return ChurchPromptDecision(shouldShow: false, suppressReason: "Church assist disabled", prompt: type)
        }

        // Rule 2: Prompt requiring location — user must have granted location prompts
        if type.requiresLocation && !assistState.allowLocationPrompts {
            dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Location prompts not allowed")
            return ChurchPromptDecision(shouldShow: false, suppressReason: "Location prompts not allowed", prompt: type)
        }

        // Rule 3: Cooldown — if dismissed within the last 24 hours, suppress
        if assistState.dismissedPromptTypes.contains(type.rawValue) {
            if let lastPrompt = assistState.lastPromptAt {
                let hoursSinceDismissal = Date().timeIntervalSince(lastPrompt) / 3600
                if hoursSinceDismissal < 24 {
                    dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Recently dismissed (\(Int(hoursSinceDismissal))h ago)")
                    return ChurchPromptDecision(shouldShow: false, suppressReason: "Recently dismissed", prompt: type)
                }
            } else {
                // Dismissed but no timestamp — be conservative and suppress
                dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Dismissed (no timestamp)")
                return ChurchPromptDecision(shouldShow: false, suppressReason: "Recently dismissed", prompt: type)
            }
        }

        // Rule 4: Post-visit prompts require permission
        if type.isPostVisit && !assistState.allowPostVisitPrompts {
            dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Post-visit prompts not allowed")
            return ChurchPromptDecision(shouldShow: false, suppressReason: "Post-visit prompts disabled", prompt: type)
        }

        // Rule 5: Service mode prompts require permission
        if type.isServiceMode && !assistState.allowServiceMode {
            dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Service mode not allowed")
            return ChurchPromptDecision(shouldShow: false, suppressReason: "Service mode disabled", prompt: type)
        }

        // Rule 6: Daily prompt cap — max 2 church prompts per day
        let todayCount = dailyPromptCount(lastPromptAt: assistState.lastPromptAt)
        if todayCount >= 2 {
            dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Daily limit reached (\(todayCount))")
            return ChurchPromptDecision(shouldShow: false, suppressReason: "Daily limit reached", prompt: type)
        }

        // Rule 7: Arrived prompts — only valid once per session (not if already past .arrived)
        if type == .arrivedNeedsNotes || type == .arrivedChecklist {
            if let currentState = assistState.currentVisitState {
                let pastArrived: [ChurchVisitState] = [.inService, .postVisit, .revisitSuggested]
                if pastArrived.contains(currentState) {
                    dlog("[ChurchPromptPolicy] Suppressed '\(type.rawValue)' — Visit state already past arrived")
                    return ChurchPromptDecision(
                        shouldShow: false,
                        suppressReason: "Arrived prompt already shown this session",
                        prompt: type
                    )
                }
            }
        }

        dlog("[ChurchPromptPolicy] Approved '\(type.rawValue)'")
        return ChurchPromptDecision(shouldShow: true, suppressReason: nil, prompt: type)
    }

    // MARK: - Daily Prompt Count

    /// Returns the estimated number of church prompts shown today.
    /// Simplified implementation — production should count from Firestore.
    static func dailyPromptCount(lastPromptAt: Date?) -> Int {
        guard let lastPrompt = lastPromptAt else { return 0 }
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(lastPrompt)
        return isToday ? 1 : 0
    }
}
