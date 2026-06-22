//
//  SupportPromptOrchestrating.swift
//  AMENAPP
//

import Foundation

protocol SupportPromptOrchestrating: AnyObject, Sendable {
    /// Returns the most appropriate prompt type for this surface, or nil if none warranted.
    func eligiblePrompt(
        for profile: SupportProfile,
        surface: SupportSurface,
        promptState: SupportPromptState,
        recoveryState: SupportRecoveryState
    ) async -> SupportPromptType?

    /// Record that a prompt was shown and update cooldown state.
    func recordShown(promptType: SupportPromptType, userId: String) async throws

    /// Record that a prompt was dismissed.
    func recordDismissed(promptType: SupportPromptType, userId: String) async throws

    /// Record that the user engaged with a prompt.
    func recordEngaged(promptType: SupportPromptType, userId: String) async throws
}
