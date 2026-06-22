// ContentPermissionEngine.swift
// AMENAPP — ContentOS
//
// Pure-function permission evaluator. No state, no side effects.
// All ContentOS permission decisions go through here.
// Mirrors the design of AmenCovenantPermissions.

import Foundation

enum ContentPermissionEngine {

    // MARK: - Primary Gate

    @MainActor
    static func evaluate(
        action: ContentAction,
        card: ContentCard,
        requestorIsCreator: Bool,
        requestorIsSpaceAdmin: Bool,
        requestorIsChurchAdmin: Bool,
        requestorIsTrustedMember: Bool,
        targetSurface: ContentSurface
    ) -> ContentPermissionOutcome {
        guard AMENFeatureFlags.shared.contentOSEnabled else {
            return .denied(reason: "Content sharing is not available right now.")
        }

        // Safety vetoes override everything — they are not negotiable
        if let veto = safetyVeto(action: action, card: card, targetSurface: targetSurface) {
            return veto
        }

        // Creators always have full rights over their own content
        if requestorIsCreator { return .allowedInstantly }

        return audienceGate(
            action: action,
            card: card,
            requestorIsSpaceAdmin: requestorIsSpaceAdmin,
            requestorIsChurchAdmin: requestorIsChurchAdmin,
            requestorIsTrustedMember: requestorIsTrustedMember,
            targetSurface: targetSurface
        )
    }

    // MARK: - Safety Vetoes (absolute — no override path)

    private static func safetyVeto(
        action: ContentAction,
        card: ContentCard,
        targetSurface: ContentSurface
    ) -> ContentPermissionOutcome? {
        // DMs cannot be posted to public feed
        if card.isDM && targetSurface == .feed {
            return .denied(reason: "Direct messages cannot be posted to a public feed.")
        }

        // Anonymous posts cannot be deanonymized or forwarded with attribution
        if card.isAnonymous && action == .quoteInPost {
            return .denied(reason: "Anonymous content cannot be quoted with attribution.")
        }
        if card.isAnonymous && (action == .forwardDM || action == .forwardGroup || action == .shareExternal) {
            return .denied(reason: "Anonymous content cannot be forwarded outside its original space.")
        }

        // Church-internal notes cannot leave approved roles to public areas
        if card.isChurchInternal && (targetSurface == .feed || targetSurface == .objectHub) {
            return .denied(reason: "Church internal notes cannot be shared publicly.")
        }

        // Paid content cannot be reposted to free public feed
        if card.isPaidContent && targetSurface == .feed {
            return .denied(reason: "Paid content cannot be reposted to a free feed.")
        }

        // Child content going outside Amen requires church admin approval
        if card.hasMinors && action == .shareExternal {
            return .requiresChurchAdminApproval
        }

        // Private prayer requests cannot be made public
        if card.hasPrayerContent && card.originalAudience == .private && targetSurface == .feed {
            return .denied(reason: "Private prayer requests cannot be shared publicly.")
        }

        return nil
    }

    // MARK: - Audience Gate

    private static func audienceGate(
        action: ContentAction,
        card: ContentCard,
        requestorIsSpaceAdmin: Bool,
        requestorIsChurchAdmin: Bool,
        requestorIsTrustedMember: Bool,
        targetSurface: ContentSurface
    ) -> ContentPermissionOutcome {
        // Prayer content has its own privacy gate regardless of audience
        if card.hasPrayerContent || card.sourceType == .prayerRequest {
            return prayerGate(card: card, requestorIsTrustedMember: requestorIsTrustedMember)
        }

        switch card.originalAudience {
        case .private:
            return .denied(reason: "This content is private.")

        case .trustedCircle:
            return requestorIsTrustedMember
                ? .allowedWithAttribution
                : .requiresCreatorApproval

        case .smallGroup:
            if targetSurface == .feed { return .requiresCreatorApproval }
            return requestorIsTrustedMember
                ? .restrictedToTrustedMembers
                : .requiresCreatorApproval

        case .churchOnly:
            if requestorIsChurchAdmin { return .allowedWithAttribution }
            if targetSurface == .feed { return .requiresChurchAdminApproval }
            return .restrictedToSameSpace

        case .spaceMembers:
            if requestorIsSpaceAdmin { return .allowedWithAttribution }
            if card.sensitivityScore > 0.6 { return .requiresSpaceAdminApproval }
            return .allowedWithAttribution

        case .paidMembers:
            return .requiresCreatorApproval

        case .publicFeed:
            if card.sensitivityScore > 0.8 { return .requiresCreatorApproval }
            return card.attributionRules.requiresAttribution
                ? .allowedWithAttribution
                : .allowedInstantly
        }
    }

    // MARK: - Prayer Gate

    private static func prayerGate(
        card: ContentCard,
        requestorIsTrustedMember: Bool
    ) -> ContentPermissionOutcome {
        switch card.originalAudience {
        case .private, .trustedCircle:
            return .denied(reason: "Private prayer requests cannot be forwarded or shared.")
        case .smallGroup, .churchOnly:
            return requestorIsTrustedMember
                ? .allowedAnonymously
                : .requiresCreatorApproval
        case .spaceMembers:
            return .allowedAnonymously
        case .publicFeed, .paidMembers:
            return .allowedWithAttribution
        }
    }

    // MARK: - External Share Risk

    static func externalShareRisk(for card: ContentCard) -> ExternalShareRisk {
        ExternalShareRisk(
            exposesPrivateContext:   card.originalAudience.isRestricted,
            includesNames:           card.creatorDisplayName != nil && !card.isAnonymous,
            includesPrayerDetails:   card.hasPrayerContent,
            includesLocationOrEvent: card.hasLocationData,
            includesMinors:          card.hasMinors || card.hasChildContent,
            wasNotOriginallyPublic:  card.originalAudience != .publicFeed
        )
    }

    // MARK: - Redaction Suggestions

    static func redactionSuggestions(for card: ContentCard) -> [ContentRedactionSuggestion] {
        var suggestions: [ContentRedactionSuggestion] = []

        if card.creatorDisplayName != nil && !card.isAnonymous {
            suggestions.append(.init(type: .removeNames, description: "Remove the author's name before sharing."))
        }
        if card.hasPrayerContent {
            suggestions.append(.init(type: .removePrayerDetails, description: "Remove personal prayer details."))
            suggestions.append(.init(type: .convertToAnonymousTestimony, description: "Convert to an anonymous testimony."))
        }
        if card.hasLocationData {
            suggestions.append(.init(type: .removeLocation, description: "Remove location information."))
        }
        if card.originalAudience.isRestricted {
            suggestions.append(.init(type: .askPermissionFirst, description: "Ask the creator before sharing."))
            suggestions.append(.init(type: .summarize, description: "Share a summary instead."))
        }
        if card.sensitivityScore > 0.5 {
            suggestions.append(.init(type: .convertToDiscussionPrompt, description: "Turn into a general discussion prompt."))
        }

        return suggestions
    }

    // MARK: - Available Actions

    /// Returns the ContentActions visible on the share sheet for this card + requestor context.
    @MainActor
    static func availableActions(
        for card: ContentCard,
        requestorIsCreator: Bool,
        requestorIsTrustedMember: Bool
    ) -> [ContentAction] {
        guard AMENFeatureFlags.shared.contentOSEnabled else { return [] }

        var actions: [ContentAction] = []

        if !card.isDM {
            actions.append(.discussInSpace)
            actions.append(.discussInConnect)
        }

        if !card.isAnonymous || requestorIsCreator {
            actions.append(.sendToMentor)
            actions.append(.sendToSmallGroup)
        }

        if requestorIsTrustedMember || requestorIsCreator {
            actions.append(.sendToChurchTeam)
        }

        // Saving to Church Notes is always safe — stays private to the user
        actions.append(.saveToChurchNotes)

        if card.sourceType != .message && card.sourceType != .prayerRequest {
            actions.append(.createStudy)
        }

        if card.hasPrayerContent || card.sourceType == .prayerRequest {
            actions.append(.createPrayerRoom)
        }

        if card.sourceType == .event
            || card.sourceType == .sermonClip
            || card.sourceType == .livestreamMoment {
            actions.append(.createEventFollowUp)
        }

        if AMENFeatureFlags.shared.contentForwardingEnabled && !card.isDM {
            actions.append(.forwardDM)
            actions.append(.forwardGroup)
        }

        if AMENFeatureFlags.shared.contentForwardingEnabled {
            actions.append(.shareExternal)
        }

        if card.originalAudience != .private && !card.isAnonymous {
            actions.append(.quoteInPost)
        }

        if !requestorIsCreator && card.originalAudience.isRestricted {
            actions.append(.requestPermission)
        }

        return actions
    }
}
