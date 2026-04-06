//
//  SupportPromptState.swift
//  AMENAPP
//
//  Central suppression, cooldown, and fatigue state.
//  Stored at users/{userId}/support_prompt_state/current.
//

import Foundation

struct SupportPromptState: Codable, Sendable {
    var lastPromptShownAt: Date?
    var lastPromptType: SupportPromptType?
    var dismissedPromptTypes: Set<SupportPromptType>
    var promptFatigueScore: Double              // 0.0–1.0
    var consecutiveDismissals: Int
    var cooldownUntil: Date?
    var perPromptCooldowns: [String: Date]      // SupportPromptType.rawValue → expiry
    var totalPromptsShownLast7Days: Int
    var updatedAt: Date?

    var isInCooldown: Bool {
        guard let until = cooldownUntil else { return false }
        return Date() < until
    }

    func cooldownExpiry(for type: SupportPromptType) -> Date? {
        perPromptCooldowns[type.rawValue]
    }

    func isPromptInCooldown(_ type: SupportPromptType) -> Bool {
        guard let exp = cooldownExpiry(for: type) else { return false }
        return Date() < exp
    }

    static var empty: SupportPromptState {
        SupportPromptState(
            lastPromptShownAt: nil,
            lastPromptType: nil,
            dismissedPromptTypes: [],
            promptFatigueScore: 0.0,
            consecutiveDismissals: 0,
            cooldownUntil: nil,
            perPromptCooldowns: [:],
            totalPromptsShownLast7Days: 0,
            updatedAt: nil
        )
    }
}
