// SpacesFeatureFlags.swift
// AMENAPP — Phase 0: Spaces System Kill Switches
//
// Separate from AMENFeatureFlags (which is a final class and cannot be
// extended with stored properties). SpacesFeatureFlags follows the same
// Remote Config pattern.
//
// Rules:
//   - Every major Spaces system has a kill switch defaulting to OFF in prod.
//   - Kill switches are checked at the surface level — agents must call
//     SpacesFeatureFlags.shared before rendering any Spaces-gated UI.
//   - Flags are additive; never remove one without a deprecation cycle.
//   - Targeting (per-user rollout) is done via Firebase Remote Config
//     audiences — no client-side targeting logic.
//
// Usage:
//   guard SpacesFeatureFlags.shared.spacesIntelligenceEnabled else { return }

import Foundation
import Combine
import FirebaseRemoteConfig

@MainActor
final class SpacesFeatureFlags: ObservableObject {

    static let shared = SpacesFeatureFlags()

    // MARK: - Feature 1: Adaptive Intelligent Spaces
    /// Master switch for the Spaces intelligence layer (DNA, rhythm, ambient signals).
    @Published private(set) var spacesIntelligenceEnabled: Bool = false

    // MARK: - Feature 2: Liquid Glass Spatial Workspace
    /// Enables AmenLiquidGlassHeader, AmenSpaceHeroBanner, glass tab bar in Spaces.
    @Published private(set) var spacesLiquidGlassEnabled: Bool = false

    // MARK: - Feature 3: AI Relationship Graph
    /// Private graph of collaboration, mentorship, prayer, study signals.
    /// Server-only writes; client reads for mentorship matching UI.
    @Published private(set) var spacesRelationshipGraphEnabled: Bool = false

    // MARK: - Feature 4: Church Notes OS (Spaces integration layer)
    /// Notes-to-Space sharing, collab notes, sermon fan-out within Spaces.
    /// Does NOT gate the standalone Church Notes editor.
    @Published private(set) var spacesChurchNotesOSEnabled: Bool = false

    // MARK: - Feature 5: Intelligent Find a Church
    /// Church-type Spaces as live listings; relational graph matching.
    @Published private(set) var spacesFindChurchIntelligenceEnabled: Bool = false

    // MARK: - Feature 6: True Source Safety OS (per-Space covenant)
    /// GUARDIAN tuned per-Space covenant; moderation constitution per SpaceType.
    @Published private(set) var spacesTrueSourceSafetyEnabled: Bool = false

    // MARK: - Feature 7: Smart Gatherings + Events
    /// RSVP, smart prep, live notes, follow-ups, Space-linked events.
    @Published private(set) var spacesEventsRSVPEnabled: Bool = false

    // MARK: - Feature 8: Enterprise + School Mode
    /// School/business Space templates, domain-based joining, org admin controls.
    @Published private(set) var spacesEnterpriseSchoolModeEnabled: Bool = false

    // MARK: - Feature 9: Berean Multi-Agent System
    /// Berean as first-class Space member: @mention, DM, proactive surfacing,
    /// cited recall, rhythm-aware activation.
    @Published private(set) var spacesBereanMemberEnabled: Bool = false

    // MARK: - Feature 10: Smart Discovery Feed
    /// Space discovery ranked by usefulness, trust, locality, safety, user intent.
    @Published private(set) var spacesSmartDiscoveryEnabled: Bool = false

    // MARK: - Feature 11: Ambient Presence System
    /// Subtle presence states (studying, praying, hosting, in class, mentoring).
    @Published private(set) var spacesAmbientPresenceEnabled: Bool = false

    // MARK: - Feature 12: AI-Powered Group Formation
    /// Suggest study groups, accountability partners, volunteer teams.
    @Published private(set) var spacesGroupFormationEnabled: Bool = false

    // MARK: - Feature 13: Smart Media Intelligence
    /// Captions, key moments, scripture linking, topic extraction in Space media.
    @Published private(set) var spacesMediaIntelligenceEnabled: Bool = false

    // MARK: - Feature 14: Living Banners
    /// Ambient Spatial Motion Hero banners for Spaces, churches, events, orgs.
    @Published private(set) var spacesLivingBannersEnabled: Bool = false

    // MARK: - Feature 15: AI Reputation Without Vanity Metrics
    /// Private contribution quality, trust, mentorship signals. No public counts.
    @Published private(set) var spacesPrivateReputationEnabled: Bool = false

    // MARK: - Sub-flags (individual surface controls)

    /// Ephemeral rooms that auto-summarize into a Living Memory artifact.
    @Published private(set) var spacesEphemeralRoomsEnabled: Bool = false

    /// Space DNA generation via natural-language description.
    @Published private(set) var spacesDNAGenerationEnabled: Bool = false

    /// Space composition — a Space whose children are Spaces (denomination hierarchy).
    @Published private(set) var spacesCompositionEnabled: Bool = false

    /// Per-Space reading plans with daily thread + Berean question.
    @Published private(set) var spacesReadingPlansEnabled: Bool = false

    /// Scoped portable identity across Spaces (gifts, history, user-controlled visibility).
    @Published private(set) var spacesScopedIdentityEnabled: Bool = false

    // MARK: - Remote Config Keys

    private enum RCKey: String {
        case spacesIntelligence         = "spaces_intelligence_enabled"
        case spacesLiquidGlass          = "spaces_liquid_glass_enabled"
        case spacesRelationshipGraph    = "spaces_relationship_graph_enabled"
        case spacesChurchNotesOS        = "spaces_church_notes_os_enabled"
        case spacesFindChurch           = "spaces_find_church_intelligence_enabled"
        case spacesTrueSourceSafety     = "spaces_true_source_safety_enabled"
        case spacesEventsRSVP           = "spaces_events_rsvp_enabled"
        case spacesEnterpriseSchool     = "spaces_enterprise_school_mode_enabled"
        case spacesBereanMember         = "spaces_berean_member_enabled"
        case spacesSmartDiscovery       = "spaces_smart_discovery_enabled"
        case spacesAmbientPresence      = "spaces_ambient_presence_enabled"
        case spacesGroupFormation       = "spaces_group_formation_enabled"
        case spacesMediaIntelligence    = "spaces_media_intelligence_enabled"
        case spacesLivingBanners        = "spaces_living_banners_enabled"
        case spacesPrivateReputation    = "spaces_private_reputation_enabled"
        case spacesEphemeralRooms       = "spaces_ephemeral_rooms_enabled"
        case spacesDNAGeneration        = "spaces_dna_generation_enabled"
        case spacesComposition          = "spaces_composition_enabled"
        case spacesReadingPlans         = "spaces_reading_plans_enabled"
        case spacesScopedIdentity       = "spaces_scoped_identity_enabled"
    }

    // MARK: - Init

    private init() {
        Task { await fetchRemoteConfig() }
    }

    // MARK: - Remote Config Fetch

    func fetchRemoteConfig() async {
        let rc = RemoteConfig.remoteConfig()

        // Register safe defaults (all OFF in production)
        rc.setDefaults([
            RCKey.spacesIntelligence.rawValue:      false as NSObject,
            RCKey.spacesLiquidGlass.rawValue:       false as NSObject,
            RCKey.spacesRelationshipGraph.rawValue: false as NSObject,
            RCKey.spacesChurchNotesOS.rawValue:     false as NSObject,
            RCKey.spacesFindChurch.rawValue:        false as NSObject,
            RCKey.spacesTrueSourceSafety.rawValue:  false as NSObject,
            RCKey.spacesEventsRSVP.rawValue:        false as NSObject,
            RCKey.spacesEnterpriseSchool.rawValue:  false as NSObject,
            RCKey.spacesBereanMember.rawValue:      false as NSObject,
            RCKey.spacesSmartDiscovery.rawValue:    false as NSObject,
            RCKey.spacesAmbientPresence.rawValue:   false as NSObject,
            RCKey.spacesGroupFormation.rawValue:    false as NSObject,
            RCKey.spacesMediaIntelligence.rawValue: false as NSObject,
            RCKey.spacesLivingBanners.rawValue:     false as NSObject,
            RCKey.spacesPrivateReputation.rawValue: false as NSObject,
            RCKey.spacesEphemeralRooms.rawValue:    false as NSObject,
            RCKey.spacesDNAGeneration.rawValue:     false as NSObject,
            RCKey.spacesComposition.rawValue:       false as NSObject,
            RCKey.spacesReadingPlans.rawValue:      false as NSObject,
            RCKey.spacesScopedIdentity.rawValue:    false as NSObject,
        ])

        do {
            try await rc.fetch(withExpirationDuration: 3600)
            try await rc.activate()
            applyValues(from: rc)
        } catch {
            // Silently fall back to safe defaults — all features stay OFF
        }
    }

    private func applyValues(from rc: RemoteConfig) {
        spacesIntelligenceEnabled       = rc[RCKey.spacesIntelligence.rawValue].boolValue
        spacesLiquidGlassEnabled        = rc[RCKey.spacesLiquidGlass.rawValue].boolValue
        spacesRelationshipGraphEnabled  = rc[RCKey.spacesRelationshipGraph.rawValue].boolValue
        spacesChurchNotesOSEnabled      = rc[RCKey.spacesChurchNotesOS.rawValue].boolValue
        spacesFindChurchIntelligenceEnabled = rc[RCKey.spacesFindChurch.rawValue].boolValue
        spacesTrueSourceSafetyEnabled   = rc[RCKey.spacesTrueSourceSafety.rawValue].boolValue
        spacesEventsRSVPEnabled         = rc[RCKey.spacesEventsRSVP.rawValue].boolValue
        spacesEnterpriseSchoolModeEnabled = rc[RCKey.spacesEnterpriseSchool.rawValue].boolValue
        spacesBereanMemberEnabled       = rc[RCKey.spacesBereanMember.rawValue].boolValue
        spacesSmartDiscoveryEnabled     = rc[RCKey.spacesSmartDiscovery.rawValue].boolValue
        spacesAmbientPresenceEnabled    = rc[RCKey.spacesAmbientPresence.rawValue].boolValue
        spacesGroupFormationEnabled     = rc[RCKey.spacesGroupFormation.rawValue].boolValue
        spacesMediaIntelligenceEnabled  = rc[RCKey.spacesMediaIntelligence.rawValue].boolValue
        spacesLivingBannersEnabled      = rc[RCKey.spacesLivingBanners.rawValue].boolValue
        spacesPrivateReputationEnabled  = rc[RCKey.spacesPrivateReputation.rawValue].boolValue
        spacesEphemeralRoomsEnabled     = rc[RCKey.spacesEphemeralRooms.rawValue].boolValue
        spacesDNAGenerationEnabled      = rc[RCKey.spacesDNAGeneration.rawValue].boolValue
        spacesCompositionEnabled        = rc[RCKey.spacesComposition.rawValue].boolValue
        spacesReadingPlansEnabled       = rc[RCKey.spacesReadingPlans.rawValue].boolValue
        spacesScopedIdentityEnabled     = rc[RCKey.spacesScopedIdentity.rawValue].boolValue
    }

    // MARK: - Convenience Guards

    /// Returns true only if both the master switch AND the Berean member flag are on.
    var bereanAsSpaceMemberActive: Bool {
        spacesIntelligenceEnabled && spacesBereanMemberEnabled
    }

    /// Returns true only if intelligence + DNA generation are both enabled.
    var dnaGenerationActive: Bool {
        spacesIntelligenceEnabled && spacesDNAGenerationEnabled
    }

    /// Returns true if Spaces ambient presence is fully active.
    var ambientPresenceActive: Bool {
        spacesIntelligenceEnabled && spacesAmbientPresenceEnabled
    }
}
