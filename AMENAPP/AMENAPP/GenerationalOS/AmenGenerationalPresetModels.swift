// AmenGenerationalPresetModels.swift
// AMENAPP — GenerationalOS
//
// Data model layer for the Generational Presets safety system.
// Five tiers calibrate safety, discovery, messaging, and UX over one platform.
// No separate apps — same platform, different safety profiles.

import Foundation

// MARK: - PostAudienceOption

/// The audience options a user may choose when composing a post.
/// Teens receive a restricted subset; all others receive the full set.
enum PostAudienceOption: String, CaseIterable, Codable {
    case everyone        = "Everyone"
    case followers       = "Followers"
    case friendsOfFriends = "Friends of Friends"
    case privateCircle   = "Private Circle"
    case familyOnly      = "Family Only"
}

// MARK: - AmenGenerationalPreset

enum AmenGenerationalPreset: String, CaseIterable, Codable {
    case teen
    case youngAdult
    case parent
    case professional
    case senior

    // MARK: Display

    var displayName: String {
        switch self {
        case .teen:         return "Teen"
        case .youngAdult:   return "Young Adult"
        case .parent:       return "Parent"
        case .professional: return "Professional"
        case .senior:       return "Senior"
        }
    }

    var symbolName: String {
        switch self {
        case .teen:         return "figure.child"
        case .youngAdult:   return "person.fill"
        case .parent:       return "figure.2.and.child.holdinghands"
        case .professional: return "briefcase.fill"
        case .senior:       return "figure.seated.side"
        }
    }

    var description: String {
        switch self {
        case .teen:
            return "Safe spaces for learning and growing in faith. Conservative discovery, mentorship-focused messaging."
        case .youngAdult:
            return "Full platform experience with community, mentorship, and spiritual formation."
        case .parent:
            return "Family-oriented features: family circles, child activity visibility, shared devotionals."
        case .professional:
            return "Full access with professional networking, ministry leadership tools."
        case .senior:
            return "Simplified navigation with large text. One-tap access to what matters most."
        }
    }
}

// MARK: - AmenGenerationalSafetyConfig

struct AmenGenerationalSafetyConfig {

    // MARK: Posting

    /// Whether the user may address posts to the general public.
    /// Charter mandate: teens always post to a restricted set only.
    let canPostPublicly: Bool

    /// The audience options available in the post composer.
    let postAudienceOptions: [PostAudienceOption]

    /// Charter mandate: every tier must choose audience before posting.
    let requiresAudienceFirst: Bool

    // MARK: Discovery

    /// When true the platform hides suggested strangers and limits search results.
    let discoveryRestricted: Bool

    /// Whether the user may search the full user directory.
    let canSearchAllUsers: Bool

    /// Whether the platform surfaces suggested people the user does not know.
    let showSuggestedStrangers: Bool

    // MARK: Messaging

    /// When true only verified contacts (mutual followers) may initiate DMs.
    let messagingConservative: Bool

    /// Whether unconnected users may open a DM thread with this account.
    let canReceiveDMsFromStrangers: Bool

    // MARK: Metrics

    /// When true vanity metrics are permanently hidden — the user cannot opt back in.
    let vanityMetricsAlwaysHidden: Bool

    /// Whether follower / following counts are displayed.
    let showFollowerCounts: Bool

    // MARK: Simple Mode

    /// When true the app defaults into the simplified senior-friendly interface on first launch.
    let defaultsToSimpleMode: Bool

    // MARK: Content

    /// When true the platform hard-blocks sensitive content categories.
    let sensitiveContentBlocked: Bool

    /// When true teen users need a parent or church leader to confirm church joins.
    let requireParentalApprovalForChurch: Bool

    // MARK: - Factory

    static func config(for preset: AmenGenerationalPreset) -> AmenGenerationalSafetyConfig {
        switch preset {

        case .teen:
            return AmenGenerationalSafetyConfig(
                canPostPublicly: false,
                postAudienceOptions: [.followers, .privateCircle],
                requiresAudienceFirst: true,
                discoveryRestricted: true,
                canSearchAllUsers: false,
                showSuggestedStrangers: false,
                messagingConservative: true,
                canReceiveDMsFromStrangers: false,
                vanityMetricsAlwaysHidden: true,
                showFollowerCounts: false,
                defaultsToSimpleMode: false,
                sensitiveContentBlocked: true,
                requireParentalApprovalForChurch: true
            )

        case .youngAdult:
            return AmenGenerationalSafetyConfig(
                canPostPublicly: true,
                postAudienceOptions: PostAudienceOption.allCases,
                requiresAudienceFirst: true,
                discoveryRestricted: false,
                canSearchAllUsers: true,
                showSuggestedStrangers: true,
                messagingConservative: false,
                canReceiveDMsFromStrangers: true,
                vanityMetricsAlwaysHidden: false,
                showFollowerCounts: true,
                defaultsToSimpleMode: false,
                sensitiveContentBlocked: false,
                requireParentalApprovalForChurch: false
            )

        case .parent:
            return AmenGenerationalSafetyConfig(
                canPostPublicly: true,
                postAudienceOptions: PostAudienceOption.allCases,
                requiresAudienceFirst: true,
                discoveryRestricted: false,
                canSearchAllUsers: true,
                showSuggestedStrangers: true,
                messagingConservative: false,
                canReceiveDMsFromStrangers: true,
                vanityMetricsAlwaysHidden: false,
                showFollowerCounts: true,
                defaultsToSimpleMode: false,
                sensitiveContentBlocked: false,
                requireParentalApprovalForChurch: false
            )

        case .professional:
            return AmenGenerationalSafetyConfig(
                canPostPublicly: true,
                postAudienceOptions: PostAudienceOption.allCases,
                requiresAudienceFirst: true,
                discoveryRestricted: false,
                canSearchAllUsers: true,
                showSuggestedStrangers: true,
                messagingConservative: false,
                canReceiveDMsFromStrangers: true,
                vanityMetricsAlwaysHidden: false,
                showFollowerCounts: true,
                defaultsToSimpleMode: false,
                sensitiveContentBlocked: false,
                requireParentalApprovalForChurch: false
            )

        case .senior:
            return AmenGenerationalSafetyConfig(
                canPostPublicly: true,
                postAudienceOptions: PostAudienceOption.allCases,
                requiresAudienceFirst: true,
                discoveryRestricted: false,
                canSearchAllUsers: true,
                showSuggestedStrangers: true,
                messagingConservative: false,
                canReceiveDMsFromStrangers: true,
                vanityMetricsAlwaysHidden: false,
                showFollowerCounts: true,
                defaultsToSimpleMode: true,
                sensitiveContentBlocked: false,
                requireParentalApprovalForChurch: false
            )
        }
    }
}
