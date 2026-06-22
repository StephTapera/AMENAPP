import Foundation

// MARK: - Selah Contextual Flags
// Bridges AMENFeatureFlags (the Remote Config–backed master/cluster/sensitive gates)
// to the engine's `SelahContextualFeature` set. A feature is only ever offered to the
// evaluator when the master gate, its cluster gate, and — for the three high-trust
// signals (Photos, Screen Time, Health) — its sensitive override are all ON.
//
// This is the single place that turns flags into capability. Nothing here grants a
// permission or surfaces a suggestion; it only narrows `enabledFeatures` so the
// restraint contract in SelahContextualIntelligenceService never sees a disabled feature.

@MainActor
enum SelahContextualFlags {

    /// Master gate. When false the whole subsystem is inert.
    static func isMasterEnabled() -> Bool {
        AMENFeatureFlags.shared.selahContextualEnabled
    }

    /// Whether a cluster's Remote Config gate is ON.
    static func isClusterEnabled(_ cluster: SelahContextualCluster) -> Bool {
        let flags = AMENFeatureFlags.shared
        switch cluster {
        case .inTheRoom:      return flags.selahContextualInTheRoomEnabled
        case .acrossTheWeek:  return flags.selahContextualAcrossTheWeekEnabled
        case .flowOfLife:     return flags.selahContextualFlowOfLifeEnabled
        case .restraintSpine: return flags.selahContextualRestraintSpineEnabled
        case .trustAndDepth:  return flags.selahContextualTrustDepthEnabled
        }
    }

    /// Whether the sensitive override flag a feature additionally requires is ON.
    /// Returns true for features that need no extra high-trust gate.
    static func sensitiveOverrideSatisfied(for feature: SelahContextualFeature) -> Bool {
        let flags = AMENFeatureFlags.shared
        switch feature {
        case .photoMemoryAnchoring: return flags.selahContextualPhotosEnabled
        case .doomscrollInterceptor: return flags.selahContextualScreenTimeEnabled
        case .stressAwareSurfacing:  return flags.selahContextualHealthEnabled
        default:                     return true
        }
    }

    /// True iff master + cluster + (sensitive override) are all ON for this feature.
    static func isFeatureFlagEnabled(_ feature: SelahContextualFeature) -> Bool {
        guard isMasterEnabled() else { return false }
        guard isClusterEnabled(feature.cluster) else { return false }
        return sensitiveOverrideSatisfied(for: feature)
    }

    /// The full set of features the flags currently permit. Feed into
    /// `SelahContextualSettings.enabledFeatures` (intersected with the user's own toggles).
    static func flagEnabledFeatures() -> Set<SelahContextualFeature> {
        guard isMasterEnabled() else { return [] }
        return Set(SelahContextualFeature.allCases.filter { isFeatureFlagEnabled($0) })
    }
}
