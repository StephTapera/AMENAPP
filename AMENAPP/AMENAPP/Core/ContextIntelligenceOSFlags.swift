import Foundation

/// Context Intelligence OS feature flags — 20 capabilities, all default OFF
/// Enable via Firebase Remote Config with keys matching the property names
enum ContextIntelligenceFlags {
    static var signalBus: Bool              { AMENFeatureFlags.ctx_signal_bus_enabled }
    static var permissionsCenter: Bool      { AMENFeatureFlags.ctx_permissions_center_enabled }
    static var crisisDampening: Bool        { AMENFeatureFlags.ctx_crisis_dampening_enabled }
    static var gentleCheckIns: Bool         { AMENFeatureFlags.ctx_gentle_check_ins_enabled }
    static var rhythmEngine: Bool           { AMENFeatureFlags.ctx_rhythm_engine_enabled }
    static var noteToBridge: Bool           { AMENFeatureFlags.ctx_note_to_give_bridge_enabled }
    static var messagePrayer: Bool          { AMENFeatureFlags.ctx_message_prayer_extraction_enabled }
    static var visitVerification: Bool      { AMENFeatureFlags.ctx_visit_verification_enabled }
    static var bereanContext: Bool          { AMENFeatureFlags.ctx_berean_context_injection_enabled }
    static var verseResonance: Bool         { AMENFeatureFlags.ctx_verse_resonance_enabled }
    static var cohortResonance: Bool        { AMENFeatureFlags.ctx_cohort_resonance_enabled }
    static var givingPortfolio: Bool        { AMENFeatureFlags.ctx_giving_portfolio_enabled }
    static var continuityCrossDevice: Bool  { AMENFeatureFlags.ctx_continuity_cross_device_enabled }
    static var seasonsInsights: Bool        { AMENFeatureFlags.ctx_seasons_insights_enabled }
    static var volunteerNeeds: Bool         { AMENFeatureFlags.ctx_volunteer_needs_posting_enabled }
    static var groupFormation: Bool         { AMENFeatureFlags.ctx_group_formation_analytics_enabled }
}
