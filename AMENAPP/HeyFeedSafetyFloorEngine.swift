//
//  HeyFeedSafetyFloorEngine.swift
//  AMENAPP
//
//  HeyFeed v2 — the immovable SafetyFloor that runs BEFORE ranking and cannot be relaxed by any
//  user preference. Pure value logic — no network, no Firestore, no model judgment.
//
//  Reuses PostSafetyMetadata + SensitivityFilter from HeyFeedModels.swift. Mirrors the pure
//  helpers in heyFeedSteering.ts (effectiveRiskThreshold / failClosedFloorVerdict).
//
//  ALWAYS-ON: this engine is NOT gated by the heyFeedSteering flag. It runs even when steering
//  is OFF — like child safety. Fail-closed: when a post cannot be evaluated, it never surfaces.
//

import Foundation

// MARK: - Default Floor Table

enum SafetyFloorTable {
    /// The frozen default floors. childSafety / csam hard-block at near-zero risk; the rest impose
    /// a ceiling that even SensitivityFilter.off cannot exceed. All are alwaysOn.
    static let defaults: [SafetyFloor] = [
        SafetyFloor(category: .childSafety,   action: .hardBlock,    ceilingRisk: 0.0,  alwaysOn: true),
        SafetyFloor(category: .csam,          action: .hardBlock,    ceilingRisk: 0.0,  alwaysOn: true),
        SafetyFloor(category: .harassment,    action: .ceiling,      ceilingRisk: 0.4,  alwaysOn: true),
        SafetyFloor(category: .hate,          action: .ceiling,      ceilingRisk: 0.4,  alwaysOn: true),
        SafetyFloor(category: .threats,       action: .ceiling,      ceilingRisk: 0.3,  alwaysOn: true),
        SafetyFloor(category: .selfHarm,      action: .alwaysShield, ceilingRisk: 0.3,  alwaysOn: true),
        SafetyFloor(category: .sexualContent, action: .ceiling,      ceilingRisk: 0.4,  alwaysOn: true),
        SafetyFloor(category: .violence,      action: .ceiling,      ceilingRisk: 0.5,  alwaysOn: true),
        SafetyFloor(category: .scam,          action: .ceiling,      ceilingRisk: 0.5,  alwaysOn: true),
        SafetyFloor(category: .spam,          action: .ceiling,      ceilingRisk: 0.6,  alwaysOn: true),
    ]

    /// Maps a v1 risk reason (PostSafetyMetadata.SafetyRiskReason) to a floor category.
    static func category(for reason: PostSafetyMetadata.SafetyRiskReason) -> SafetyFloorCategory? {
        switch reason {
        case .harassment:     return .harassment
        case .hate:           return .hate
        case .selfHarm:       return .selfHarm
        case .sexual:         return .sexualContent
        case .violence:       return .violence
        case .spam:           return .spam
        case .scam:           return .scam
        case .pii, .toxicity, .misinformation:
            // Not a floor category on their own; handled by the toxicity/provenance hooks elsewhere.
            return nil
        }
    }
}

// MARK: - Safety Floor Engine

enum SafetyFloorEngine {

    /// Pure pre-rank gate. Runs BEFORE the scorer. Returns a verdict whose `allowed == false`
    /// means the post never surfaces — no preference can override it.
    ///
    /// - Parameters:
    ///   - postId:    stable post identifier.
    ///   - safety:    the post's safety metadata, or nil when unavailable (=> fail-closed).
    ///   - viewerFilter: the viewer's chosen SensitivityFilter (a user may go STRICTER only).
    ///   - viewerIsMinor: when true, the viewer is forced to strict regardless of their setting.
    ///   - floors:    the active floor table (defaults to SafetyFloorTable.defaults).
    static func gate(
        postId: String,
        safety: PostSafetyMetadata?,
        viewerFilter: SensitivityFilter,
        viewerIsMinor: Bool,
        floors: [SafetyFloor] = SafetyFloorTable.defaults
    ) -> SafetyFloorVerdict {

        // Fail-closed: no evaluable safety metadata => never surfaces.
        guard let safety else {
            return SteeringBounds.failClosedFloorVerdict(postId: postId)
        }

        // Minor viewers are forced to the strictest filter, always.
        let effectiveFilter: SensitivityFilter = viewerIsMinor ? .strict : viewerFilter
        let userThreshold = effectiveFilter.riskThreshold

        // Resolve every floor category implicated by the post's risk reasons.
        let implicated: [SafetyFloor] = floors.filter { floor in
            safety.riskReasons.contains { reason in
                SafetyFloorTable.category(for: reason) == floor.category
            }
        }

        // 1. Any hardBlock floor whose ceiling is exceeded => block immediately.
        for floor in implicated where floor.action == .hardBlock {
            if safety.riskScore > floor.ceilingRisk {
                return SafetyFloorVerdict(
                    postId: postId,
                    allowed: false,
                    appliedFloor: floor.category,
                    appliedAction: floor.action,
                    isMinorShielded: viewerIsMinor,
                    reasons: ["hardBlock:\(floor.category.rawValue)"]
                )
            }
        }

        // 2. Ceiling / alwaysShield floors: the effective threshold is the STRICTER of the user's
        //    chosen threshold and the floor's ceiling. The user may only narrow, never widen.
        for floor in implicated {
            let threshold = SteeringBounds.effectiveRiskThreshold(
                userThreshold: userThreshold,
                ceilingRisk: floor.ceilingRisk
            )
            if safety.riskScore > threshold {
                return SafetyFloorVerdict(
                    postId: postId,
                    allowed: false,
                    appliedFloor: floor.category,
                    appliedAction: floor.action,
                    isMinorShielded: viewerIsMinor,
                    reasons: ["ceiling:\(floor.category.rawValue):risk=\(safety.riskScore)>thr=\(threshold)"]
                )
            }
        }

        // 3. No implicated floor blocked, but still honor the viewer's own sensitivity threshold
        //    (a non-floor elevated risk that exceeds their chosen filter).
        if safety.riskScore > userThreshold {
            return SafetyFloorVerdict(
                postId: postId,
                allowed: false,
                appliedFloor: nil,
                appliedAction: nil,
                isMinorShielded: viewerIsMinor,
                reasons: ["sensitivityFilter:risk=\(safety.riskScore)>thr=\(userThreshold)"]
            )
        }

        return SafetyFloorVerdict(
            postId: postId,
            allowed: true,
            appliedFloor: nil,
            appliedAction: nil,
            isMinorShielded: viewerIsMinor,
            reasons: []
        )
    }
}
