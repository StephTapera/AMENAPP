// ContextBeforeShareService.swift
// AMENAPP — Trust OS
//
// Manages share context and relationship-tier selection before a post is published.
// Creates ContextPills, computes least-surprise defaults, and surfaces non-blocking
// consent prompts when a user chooses a broader audience than the safe default.

import Foundation
import SwiftUI

@MainActor
final class ContextBeforeShareService: ObservableObject {
    static let shared = ContextBeforeShareService()

    @Published var selectedContext: ShareContext? = nil
    @Published var selectedTier: RelationshipTier? = nil

    private init() {}

    // MARK: - Context Selection

    /// Creates a ContextPill for the given context, records it as the current selection,
    /// and returns the pill so the caller can attach it to post data.
    @discardableResult
    func selectContext(_ context: ShareContext) -> ContextPill {
        selectedContext = context
        // Reset tier to the least-surprise default for the new context.
        selectedTier = leastSurpriseTier(for: context)
        return ContextPill(context: context)
    }

    // MARK: - Default Tier

    /// Returns the least-surprising (safest) RelationshipTier for the given context.
    /// Delegates to the ShareContext.defaultTier contract, which is the single source of truth.
    func leastSurpriseTier(for context: ShareContext) -> RelationshipTier {
        context.defaultTier
    }

    // MARK: - Consent Prompt

    /// Returns a non-blocking confirmation string when the context+tier combination warrants
    /// user attention (e.g., a prayer request set to Public). Returns nil when no prompt needed.
    func consentPrompt(for context: ShareContext, tier: RelationshipTier) -> String? {
        let defaultTier = context.defaultTier

        // Only prompt when the chosen tier is broader than the safe default.
        guard tier.audienceBreadth > defaultTier.audienceBreadth else { return nil }

        switch context {
        case .prayer:
            if tier == .public {
                return "Everyone — including people outside your church — will see this prayer request. Still share publicly?"
            } else if tier == .community {
                return "Your prayer request will be visible to the entire community, not just your church. Still continue?"
            }

        case .personal:
            if tier == .public {
                return "This personal post will be visible to everyone on AMEN. Still share publicly?"
            } else if tier == .community {
                return "This personal post will be visible to the whole community. Still continue?"
            }

        case .discussion:
            if tier == .public {
                return "This discussion will be public and visible beyond your community. Still share publicly?"
            }

        case .encouragement:
            if tier == .public {
                return "Your encouragement post will be visible to everyone on AMEN. Still share publicly?"
            }

        case .learning:
            // Learning content is community-scoped by default; public is fine with a light note.
            if tier == .public {
                return "This learning post will be public. Still share publicly?"
            }

        case .news:
            // News defaults to public; no broader tier exists — no prompt needed.
            break
        }

        // Generic fallback for any other broader-than-default combination.
        return "This will be visible to a broader audience than the default for \(context.displayName) posts. Still continue?"
    }
}
