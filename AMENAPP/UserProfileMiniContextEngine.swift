//
//  UserProfileMiniContextEngine.swift
//  AMENAPP
//
//  Derives context-aware CTAs, reason chips, and explanation text
//  for UserProfileViewMini based on source, engagement overlap, and
//  user relationship data. Never produces vague filler copy.
//

import Foundation

// MARK: - Context Resolution Protocol

protocol UserProfileMiniContextResolving {
    func resolve(for model: UserProfileMiniModel) -> UserMiniContextSnapshot
    /// Derive the primary CTA for this model and source.
    func primaryAction(for model: UserProfileMiniModel) -> UserMiniPrimaryAction
    /// Derive the secondary CTA.
    func secondaryAction(for model: UserProfileMiniModel) -> UserMiniSecondaryAction
    /// Generate up to 3 ranked reason chips.
    func reasons(for model: UserProfileMiniModel) -> [UserMiniReason]
    /// Generate a single-sentence explanation (never empty filler).
    func explanation(for model: UserProfileMiniModel) -> String
    /// Smart expandable actions shown below the bio.
    func smartActions(for model: UserProfileMiniModel) -> [UserMiniOverflowAction]
}

// MARK: - Context Engine

/// Derives all context-dependent display data for a UserProfileMiniModel.
/// Priority order: prayer/testimony overlap → shared engagement → mutuals
/// → community → city/area → popularity fallback.
struct UserProfileMiniContextEngine: UserProfileMiniContextResolving {

    func resolve(for model: UserProfileMiniModel) -> UserMiniContextSnapshot {
        let primaryAction = primaryAction(for: model)
        let secondaryAction = secondaryAction(for: model)
        let reasons = reasons(for: model)
        let explanation = explanation(for: model)
        let showContextPanel = !reasons.isEmpty || (model.suggestionScore ?? 0) >= 0.15
        return UserMiniContextSnapshot(
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            reasons: reasons,
            explanation: explanation,
            priorityExplanation: priorityExplanation(for: model),
            smartActions: smartActions(for: model),
            showContextPanel: showContextPanel
        )
    }

    // MARK: Primary Action

    func primaryAction(for model: UserProfileMiniModel) -> UserMiniPrimaryAction {
        if model.isProfileUnavailable || model.isBlocked { return .viewProfile }

        switch model.suggestionSource {
        case .discovery, .findFriends, .unknown:
            return model.isFollowed ? .viewProfile : .follow

        case .openTable:
            guard let trigger = model.trigger else { return .follow }
            switch trigger.viewerState {
            case .unread:  return .readThread
            case .read:    return .joinConversation
            case .replied: return .follow
            default:       return .joinConversation
            }

        case .prayer:
            guard let trigger = model.trigger else {
                return model.canMessage ? .prayTogether : .follow
            }
            if trigger.viewerState == .prayedToday { return .follow }
            if let topic = trigger.topic, !topic.isEmpty { return .prayForTopic(topic: topic) }
            return model.canMessage ? .prayTogether : .follow

        case .testimonies:
            return .viewTestimony(postId: model.trigger?.artifactId, title: model.trigger?.title)
        }
    }

    // MARK: Secondary Action

    func secondaryAction(for model: UserProfileMiniModel) -> UserMiniSecondaryAction {
        if model.isProfileUnavailable || model.isBlocked { return .viewProfile }
        if model.canMessage { return .message }
        return .viewProfile
    }

    // MARK: Reasons

    func reasons(for model: UserProfileMiniModel) -> [UserMiniReason] {
        // Use engine-resolved reasons if already set; otherwise derive.
        if !model.contextReasons.isEmpty {
            return Array(model.contextReasons.prefix(3))
        }
        return deriveReasons(for: model)
    }

    private func deriveReasons(for model: UserProfileMiniModel) -> [UserMiniReason] {
        var reasons: [UserMiniReason] = []

        if let directRelationshipReason = model.directRelationshipReason, !directRelationshipReason.isEmpty {
            reasons.append(UserMiniReason(
                id: "direct_relationship",
                label: directRelationshipReason,
                icon: "person.crop.circle.badge.checkmark",
                kind: .engagementCompatibility
            ))
        }

        if let recentSharedEngagementReason = model.recentSharedEngagementReason, !recentSharedEngagementReason.isEmpty, reasons.count < 3 {
            reasons.append(UserMiniReason(
                id: "shared_engagement",
                label: recentSharedEngagementReason,
                icon: "sparkles.rectangle.stack",
                kind: .engagementCompatibility
            ))
        }

        // Prayer/testimony/topic overlap
        if let prayerCount = model.sharedPrayerCount, prayerCount > 0 {
            let label = prayerCount == 1
                ? "1 shared prayer topic"
                : "\(prayerCount) shared prayer topics"
            reasons.append(UserMiniReason(
                id: "prayer", label: label,
                icon: "hands.sparkles", kind: .prayerOverlap
            ))
        }

        if let testimonyOverlapCount = model.testimonyOverlapCount, testimonyOverlapCount > 0, reasons.count < 3 {
            let label = testimonyOverlapCount == 1
                ? "1 shared testimony theme"
                : "\(testimonyOverlapCount) shared testimony themes"
            reasons.append(UserMiniReason(
                id: "testimony_overlap",
                label: label,
                icon: "quote.bubble",
                kind: .testimonyOverlap
            ))
        }

        if let sharedTopicReason = model.sharedTopicReason, !sharedTopicReason.isEmpty, reasons.count < 3 {
            reasons.append(UserMiniReason(
                id: "shared_topic",
                label: sharedTopicReason,
                icon: "text.bubble",
                kind: .topicOverlap
            ))
        }

        // Mutuals
        if let mutuals = model.mutualConnectionCount, mutuals > 0 {
            let label = mutuals == 1
                ? "1 mutual connection"
                : "\(mutuals) mutual connections"
            reasons.append(UserMiniReason(
                id: "mutuals", label: label,
                icon: "person.2", kind: .mutualConnections
            ))
        }

        // City/community relevance
        if let communityReason = model.communityReason, !communityReason.isEmpty, reasons.count < 3 {
            reasons.append(UserMiniReason(
                id: "community",
                label: communityReason,
                icon: "building.2",
                kind: .communityOverlap
            ))
        }

        // Source-specific fallback — only used when no primary signals exist
        if reasons.isEmpty {
            switch model.suggestionSource {
            case .openTable:
                reasons.append(UserMiniReason(
                    id: "opentable", label: "Engages with similar topics",
                    icon: "text.bubble", kind: .topicOverlap
                ))
            case .testimonies:
                reasons.append(UserMiniReason(
                    id: "testimony", label: "Shares testimony content",
                    icon: "quote.bubble", kind: .testimonyOverlap
                ))
            case .discovery, .findFriends:
                reasons.append(UserMiniReason(
                    id: "interests", label: "Shared faith interests",
                    icon: "sparkle", kind: .sharedInterest
                ))
            case .prayer:
                reasons.append(UserMiniReason(
                    id: "prayer_active", label: "Active in prayer conversations",
                    icon: "hands.sparkles", kind: .prayerOverlap
                ))
            case .unknown:
                break
            }
        }

        if let city = model.city, reasons.count < 3 {
            reasons.append(UserMiniReason(
                id: "city", label: "Also in \(city)",
                icon: "location", kind: .popularInArea
            ))
        }

        // Popularity fallback
        if let popularityReason = model.popularityReason, !popularityReason.isEmpty, reasons.count < 3 {
            reasons.append(UserMiniReason(
                id: "popularity",
                label: popularityReason,
                icon: "chart.line.uptrend.xyaxis",
                kind: .popularInArea
            ))
        }

        return Array(reasons.prefix(3))
    }

    // MARK: Explanation

    func explanation(for model: UserProfileMiniModel) -> String {
        if let priorityExplanation = model.priorityExplanation, !priorityExplanation.isEmpty {
            return priorityExplanation
        }

        if let directRelationshipReason = model.directRelationshipReason, !directRelationshipReason.isEmpty {
            return directRelationshipReason
        }

        if let recentSharedEngagementReason = model.recentSharedEngagementReason, !recentSharedEngagementReason.isEmpty {
            return recentSharedEngagementReason
        }

        if let sharedTopicReason = model.sharedTopicReason, !sharedTopicReason.isEmpty {
            return sharedTopicReason
        }

        if let prayerCount = model.sharedPrayerCount, prayerCount > 0 {
            let topicLabel = prayerCount == 1 ? "topic" : "topics"
            return "You share \(prayerCount) prayer \(topicLabel) in common."
        }

        if let mutuals = model.mutualConnectionCount, mutuals > 0 {
            let suffix = mutuals == 1 ? "person you know follows them." : "people you know follow them."
            return "\(mutuals) \(suffix)"
        }

        if let communityReason = model.communityReason, !communityReason.isEmpty {
            return communityReason
        }

        if let popularityReason = model.popularityReason, !popularityReason.isEmpty {
            return popularityReason
        }

        switch model.suggestionSource {
        case .openTable:
            return "You've both engaged with similar faith and leadership discussions."
        case .prayer:
            return "Frequently participates in prayer conversations you've joined."
        case .testimonies:
            return "Shares testimony content similar to what you've read."
        case .discovery:
            return "Popular among people with similar interests."
        case .findFriends:
            return "Suggested based on your faith interests and activity."
        case .unknown:
            return "Suggested based on your activity."
        }
    }

    func priorityExplanation(for model: UserProfileMiniModel) -> String {
        if let priorityExplanation = model.priorityExplanation, !priorityExplanation.isEmpty {
            return priorityExplanation
        }
        return explanation(for: model)
    }

    // MARK: Smart Actions

    func smartActions(for model: UserProfileMiniModel) -> [UserMiniOverflowAction] {
        var actions: [UserMiniOverflowAction] = [.viewProfile, .saveForLater, .hideSuggestion]

        switch model.suggestionSource {
        case .prayer:
            actions.insert(.seeSimilar, at: 2)
        case .testimonies:
            actions.insert(.seeSimilar, at: 2)
        default:
            break
        }

        actions.append(.report)
        return actions
    }
}
