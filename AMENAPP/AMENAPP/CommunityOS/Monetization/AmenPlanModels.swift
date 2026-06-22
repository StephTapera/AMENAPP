// AmenPlanModels.swift
// AMEN App — CommunityOS/Monetization
//
// Phase 6 — Agent M1 (Plans & Entitlements)
// The 5 canonical plan tiers: Free, Community Pro, Church Pro, Organization Pro, Enterprise.
// Feature gates, entitlement state, and minimum-tier resolution.
//
// EXTENDS (does not replace):
//   AmenAccountTier.swift     — legacy platform tiers (free/amenPlus/amenPro/creatorPro/churchPro/enterprise)
//   CovenantModels.swift      — per-Covenant membership and tier objects
//   AmenSpaceEntitlementService — per-Space entitlement cache
//
// HUMAN-GATED: payment flow changes require explicit human approval per §9 operating model.
// No StoreKit — Stripe only via Firebase Callable Functions.
// Written: 2026-06-05

import Foundation

// MARK: - AmenPlanTier

/// The 5 canonical Community OS plan tiers.
/// Distinct from AmenAccountTier (user-level) and CovenantTier (per-community creator tiers).
enum AmenPlanTier: String, Codable, CaseIterable, Sendable {
    case free
    case communityPro     = "community_pro"
    case churchPro        = "church_pro"
    case organizationPro  = "organization_pro"
    case enterprise

    // MARK: Display

    var displayName: String {
        switch self {
        case .free:             return "Free"
        case .communityPro:     return "Community Pro"
        case .churchPro:        return "Church Pro"
        case .organizationPro:  return "Organization Pro"
        case .enterprise:       return "Enterprise"
        }
    }

    /// USD monthly price. `nil` for enterprise (contact-sales only).
    var monthlyPriceUSD: Double? {
        switch self {
        case .free:             return 0
        case .communityPro:     return 9
        case .churchPro:        return 49
        case .organizationPro:  return 99
        case .enterprise:       return nil
        }
    }

    // MARK: Feature set

    /// All features included in this plan tier.
    var features: [AmenFeatureGate] {
        switch self {
        case .free:
            return []
        case .communityPro:
            return [
                .advancedPrivacyControls,
                .prioritySupport,
                .customProfile,
                .advancedAI,
                .extendedStorage,
            ]
        case .churchPro:
            return AmenPlanTier.communityPro.features + [
                .broadcastMessaging,
                .churchAnalytics,
                .volunteerManagement,
                .multiCampus,
                .advancedChurchModeration,
                .customBranding,
                .guestManagement,
            ]
        case .organizationPro:
            return AmenPlanTier.churchPro.features + [
                .orgAssistant,
                .orgBroadcast,
                .advancedAnalytics,
                .crmIntegrations,
                .apiAccess,
            ]
        case .enterprise:
            return AmenPlanTier.organizationPro.features + [
                .enterpriseGovernance,
                .multiOrgManagement,
                .ssoIntegration,
                .dedicatedSupport,
                .customContracts,
            ]
        }
    }

    // MARK: Gate check

    /// Returns `true` if this tier includes the requested feature.
    func includes(_ feature: AmenFeatureGate) -> Bool {
        features.contains(feature)
    }

    // MARK: Ordering

    /// Numeric tier rank used only for UI ordering. Do NOT use for access decisions.
    var tierOrder: Int {
        switch self {
        case .free:             return 0
        case .communityPro:     return 1
        case .churchPro:        return 2
        case .organizationPro:  return 3
        case .enterprise:       return 4
        }
    }
}

// MARK: - AmenFeatureGate

/// All plan-gated features. Grouped by the tier that first unlocks them.
enum AmenFeatureGate: String, Codable, CaseIterable, Sendable {

    // MARK: Community Pro features
    case advancedPrivacyControls    = "advanced_privacy_controls"
    case prioritySupport            = "priority_support"
    case customProfile              = "custom_profile"

    // MARK: Church Pro features
    case broadcastMessaging         = "broadcast_messaging"
    case churchAnalytics            = "church_analytics"
    case volunteerManagement        = "volunteer_management"
    case multiCampus                = "multi_campus"
    case advancedChurchModeration   = "advanced_church_moderation"
    case customBranding             = "custom_branding"
    case guestManagement            = "guest_management"

    // MARK: Organization Pro features
    /// AI assistant backed by Anthropic SDK via CF proxy (bereanChatProxy).
    case orgAssistant               = "org_assistant"
    case orgBroadcast               = "org_broadcast"
    case advancedAnalytics          = "advanced_analytics"
    case crmIntegrations            = "crm_integrations"
    case apiAccess                  = "api_access"

    // MARK: All Pro+ tiers
    case advancedAI                 = "advanced_ai"           // Berean Pro features
    case extendedStorage            = "extended_storage"

    // MARK: Enterprise only
    case enterpriseGovernance       = "enterprise_governance"
    case multiOrgManagement         = "multi_org_management"
    case ssoIntegration             = "sso_integration"
    case dedicatedSupport           = "dedicated_support"
    case customContracts            = "custom_contracts"

    // MARK: Minimum tier

    /// The lowest AmenPlanTier that first unlocks this feature.
    var minimumTier: AmenPlanTier {
        switch self {
        case .advancedPrivacyControls,
             .prioritySupport,
             .customProfile,
             .advancedAI,
             .extendedStorage:
            return .communityPro

        case .broadcastMessaging,
             .churchAnalytics,
             .volunteerManagement,
             .multiCampus,
             .advancedChurchModeration,
             .customBranding,
             .guestManagement:
            return .churchPro

        case .orgAssistant,
             .orgBroadcast,
             .advancedAnalytics,
             .crmIntegrations,
             .apiAccess:
            return .organizationPro

        case .enterpriseGovernance,
             .multiOrgManagement,
             .ssoIntegration,
             .dedicatedSupport,
             .customContracts:
            return .enterprise
        }
    }

    /// Human-readable display label for use in upgrade prompts.
    var displayName: String {
        switch self {
        case .advancedPrivacyControls:    return "Advanced Privacy Controls"
        case .prioritySupport:            return "Priority Support"
        case .customProfile:              return "Custom Profile"
        case .broadcastMessaging:         return "Broadcast Messaging"
        case .churchAnalytics:            return "Church Analytics"
        case .volunteerManagement:        return "Volunteer Management"
        case .multiCampus:                return "Multi-Campus Management"
        case .advancedChurchModeration:   return "Advanced Church Moderation"
        case .customBranding:             return "Custom Branding"
        case .guestManagement:            return "Guest Management"
        case .orgAssistant:               return "Organization AI Assistant"
        case .orgBroadcast:               return "Organization Broadcast"
        case .advancedAnalytics:          return "Advanced Analytics"
        case .crmIntegrations:            return "CRM Integrations"
        case .apiAccess:                  return "API Access"
        case .advancedAI:                 return "Advanced AI (Berean Pro)"
        case .extendedStorage:            return "Extended Storage"
        case .enterpriseGovernance:       return "Enterprise Governance"
        case .multiOrgManagement:         return "Multi-Org Management"
        case .ssoIntegration:             return "SSO Integration"
        case .dedicatedSupport:           return "Dedicated Support"
        case .customContracts:            return "Custom Contracts"
        }
    }
}

// MARK: - EntitlementStatus

enum EntitlementStatus: String, Codable, Sendable {
    case active
    case trialing
    case pastDue     = "past_due"
    case cancelled
    case incomplete

    /// Returns `true` when the entitlement grants feature access.
    /// Mirrors the fail-closed posture: unknown state = no access.
    var isAccessGranted: Bool {
        self == .active || self == .trialing
    }
}

// MARK: - AmenEntitlement

/// Server-authoritative entitlement record for a user, organization, or church.
/// Read from `/entitlements/{holderId}` in Firestore.
/// Written exclusively by Stripe webhook Cloud Functions — never by iOS client.
struct AmenEntitlement: Codable, Identifiable, Sendable {
    /// Entitlement document ID — matches the holderId (userId / orgId / churchId).
    var id: String
    /// Discriminator: "user" | "organization" | "church"
    var holderType: String
    /// The currently active plan tier.
    var planTier: AmenPlanTier
    /// Internal Stripe customer ID. NEVER shown in UI — internal Firestore field only.
    var stripeCustomerId: String?
    /// Internal Stripe subscription ID. NEVER shown in UI — internal Firestore field only.
    var stripeSubscriptionId: String?
    var status: EntitlementStatus
    /// When the current billing period ends. Nil for free tier.
    var currentPeriodEnd: Date?
    /// Whether the subscription is set to cancel at period end.
    var cancelAtPeriodEnd: Bool
    var createdAt: Date
    var updatedAt: Date

    // MARK: Convenience

    /// Returns `true` if the entitlement grants access to the given feature.
    func hasFeature(_ feature: AmenFeatureGate) -> Bool {
        guard status.isAccessGranted else { return false }
        return planTier.includes(feature)
    }

    // MARK: CodingKeys — strip Stripe IDs from any serialization sent to non-server layers

    enum CodingKeys: String, CodingKey {
        case id
        case holderType           = "holder_type"
        case planTier             = "plan_tier"
        case stripeCustomerId     = "stripe_customer_id"
        case stripeSubscriptionId = "stripe_subscription_id"
        case status
        case currentPeriodEnd     = "current_period_end"
        case cancelAtPeriodEnd    = "cancel_at_period_end"
        case createdAt            = "created_at"
        case updatedAt            = "updated_at"
    }
}
