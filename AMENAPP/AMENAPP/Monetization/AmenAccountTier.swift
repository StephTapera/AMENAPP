// AmenAccountTier.swift
// AMENAPP — Platform Monetization
//
// Platform-level account tier enum governing app-wide feature access.
// Distinct from AmenSpaceSubscriptionTier which governs per-Space membership.
// Written: 2026-06-05

import Foundation

// MARK: - AmenAccountTier

/// Platform-level account tier. Governs which app-wide features a user can access.
/// Per-Space membership is handled separately by AmenSpaceSubscriptionTier.
enum AmenAccountTier: String, CaseIterable, Codable {
    case free         = "free"
    case amenPlus     = "amenPlus"
    case amenPro      = "amenPro"
    case creatorPro   = "creatorPro"
    case churchPro    = "churchPro"
    case enterprise   = "enterprise"
}

// MARK: - Comparable

extension AmenAccountTier: Comparable {
    var tierOrder: Int {
        switch self {
        case .free:        return 0
        case .amenPlus:    return 1
        case .amenPro:     return 2
        case .creatorPro:  return 3
        case .churchPro:   return 4
        case .enterprise:  return 5
        }
    }

    static func < (lhs: AmenAccountTier, rhs: AmenAccountTier) -> Bool {
        lhs.tierOrder < rhs.tierOrder
    }
}

// MARK: - Display Properties

extension AmenAccountTier {
    var displayName: String {
        switch self {
        case .free:        return "Free"
        case .amenPlus:    return "AMEN Plus"
        case .amenPro:     return "AMEN Pro"
        case .creatorPro:  return "Creator Pro"
        case .churchPro:   return "Church Pro"
        case .enterprise:  return "Enterprise"
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free:        return "Free"
        case .amenPlus:    return "$4.99/mo"
        case .amenPro:     return "$9.99/mo"
        case .creatorPro:  return "$19.99/mo"
        case .churchPro:   return "$49/mo"
        case .enterprise:  return "Contact us"
        }
    }

    /// Key features shown in paywall UI for this tier.
    var featureList: [String] {
        switch self {
        case .free:
            return [
                "Full safety and trust tools",
                "Core social feed and discovery",
                "Church and community discovery",
                "Prayer and Bible reading tools",
            ]
        case .amenPlus:
            return [
                "Everything in Free",
                "AI writing coach and post suggestions",
                "AI content summaries",
                "Advanced search filters",
                "Photo memory vault",
                "Personal discovery agent",
            ]
        case .amenPro:
            return [
                "Everything in AMEN Plus",
                "AI Memory OS — long-term spiritual insights",
                "Advanced camera automation",
                "Family guardian dashboard",
                "Bulk auto-redact sensitive content",
            ]
        case .creatorPro:
            return [
                "Everything in AMEN Pro",
                "LIVE streaming with AI Producer",
                "Multi-cam live switching",
                "Community moderator AI",
                "Impact analytics dashboard",
                "Creator monetization tools",
                "Clip Studio — AI-powered highlight reels",
            ]
        case .churchPro:
            return [
                "Everything in Creator Pro",
                "Church broadcast and simulcast",
                "Safety dashboards for leadership",
                "Live giving and tithes integration",
                "Multi-campus management",
                "Live services with full production tools",
            ]
        case .enterprise:
            return [
                "Everything in Church Pro",
                "Governance and compliance tools",
                "CRM and member management",
                "API access",
                "Advanced moderation pipeline",
                "Dedicated account support",
            ]
        }
    }
}

// MARK: - Feature Gates

extension AmenAccountTier {
    /// User can broadcast a live stream.
    var canGoLive: Bool {
        self >= .creatorPro
    }

    /// Personal AI discovery agent surfaces curated content proactively.
    var canUsePersonalDiscoveryAgent: Bool {
        self >= .amenPlus
    }

    /// AI writing coach provides post drafts and suggestions.
    var canUseAIWritingCoach: Bool {
        self >= .amenPlus
    }

    /// AI Memory OS builds a long-term spiritual memory graph.
    var canUseAIMemoryOS: Bool {
        self >= .amenPro
    }

    /// Bulk auto-redact removes sensitive information from media in batch.
    var canUseBulkAutoRedact: Bool {
        self >= .amenPro
    }

    /// Family guardian dashboard for parental oversight.
    var canUseFamilyGuardianDashboard: Bool {
        self >= .amenPro
    }

    /// AI Producer for live stream direction and auto-switching.
    var canUseAIProducer: Bool {
        self >= .creatorPro
    }

    /// Clip Studio for AI-generated highlight reels.
    var canUseClipStudio: Bool {
        self >= .creatorPro
    }

    /// Community moderator AI for automated moderation at scale.
    var canUseCommunityModeratorAI: Bool {
        self >= .creatorPro
    }

    /// Impact analytics for reach, engagement, and spiritual health metrics.
    var canUseImpactAnalytics: Bool {
        self >= .creatorPro
    }

    /// Live giving and tithing integration during live services.
    var canUseLiveGiving: Bool {
        self >= .churchPro
    }

    /// Organizational account features (multi-campus, governance, CRM).
    var isOrganization: Bool {
        self >= .churchPro
    }
}

// MARK: - BereanCapabilityTier Bridge

extension AmenAccountTier {
    /// Maps the platform-level account tier to the Berean AI capability tier
    /// used by BereanFaithOSContracts. Call sites that depend on BereanCapabilityTier
    /// should derive it from this property rather than maintaining a parallel mapping.
    var bereanCapabilityTier: BereanCapabilityTier {
        switch self {
        case .free:                     return .free
        case .amenPlus:                 return .plus
        case .amenPro, .creatorPro,
             .churchPro, .enterprise:  return .pro
        }
    }
}

// MARK: - AmenLiveCapability

/// Describes whether a user is eligible to go live and the reason if not.
enum AmenLiveCapability {
    /// The user's current tier does not include live streaming.
    case notEligible(tier: AmenAccountTier)
    /// The user meets the tier requirement to go live.
    case eligible

    var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }

    /// The tier required to unlock live streaming, or nil if already eligible.
    var requiredTier: AmenAccountTier? {
        if case .notEligible = self { return .creatorPro }
        return nil
    }

    var blockedTier: AmenAccountTier? {
        if case .notEligible(let tier) = self { return tier }
        return nil
    }
}
