//
//  SupportFeatureFlags.swift
//  AMENAPP
//
//  Feature flags for the Support Intelligence Layer.
//  Server-driven via RemoteConfig / Firestore; defaults to conservative (off).
//

import Foundation

/// All feature flags for the support intelligence system.
/// Default is false — nothing activates without explicit enablement.
enum SupportFeatureFlag: String, CaseIterable, Sendable {
    case supportDetection          // Phase 1: Core risk scoring
    case microPrompts              // Phase 1: Micro-intervention prompts
    case resourceAffinity          // Phase 1: Resource ranking by affinity
    case forFriendClassifier       // Phase 2: Helping-someone-else detection
    case postAftercare             // Phase 2: Post-submit gentle check-in
    case recoveryBackoff           // Phase 2: Back-off when recovering
    case supportGraph              // Phase 3: Trusted support graph
    case givingRelevance           // Phase 3: Context-aware giving ranking
    case distressDraftSignals      // Phase 4: Draft delete distress signals
    case crisisRoutingEnhancements // Phase 4: Enhanced crisis routing
}

/// Strongly-typed access to support flags.
/// In production, consult FirestoreFeatureFlagService or RemoteConfig.
struct SupportIntelligenceFlags {
    private let enabled: Set<SupportFeatureFlag>

    init(enabled: Set<SupportFeatureFlag> = []) {
        self.enabled = enabled
    }

    func isEnabled(_ flag: SupportFeatureFlag) -> Bool {
        enabled.contains(flag)
    }

    /// Phase 1 bundle — safe to ship first.
    static let phase1: SupportIntelligenceFlags = SupportIntelligenceFlags(
        enabled: [.supportDetection, .microPrompts, .resourceAffinity]
    )

    /// All flags on — for testing only.
    static let allEnabled: SupportIntelligenceFlags = SupportIntelligenceFlags(
        enabled: Set(SupportFeatureFlag.allCases)
    )

    /// No flags — fully disabled.
    static let disabled: SupportIntelligenceFlags = SupportIntelligenceFlags(enabled: [])
}
