//
//  SupportIntervention.swift
//  AMENAPP
//
//  Records every support-related intervention decision (shown, dismissed, engaged).
//  Stored at users/{userId}/support_interventions/{interventionId}.
//  Used for audit trails, fatigue calculation, and model tuning.
//

import Foundation

struct SupportIntervention: Identifiable, Codable, Sendable {
    var id: String
    var interventionType: String       // "micro_prompt", "resource_rerank", "crisis_surface"
    var promptType: SupportPromptType?
    var surface: SupportSurface
    var outcome: InterventionOutcome
    var reasonCodes: [SupportReasonCode]
    var riskTierAtTime: SupportRiskTier
    var supportNeedScoreAtTime: Double
    var createdAt: Date
    var resolvedAt: Date?

    var shown: Bool    { outcome != .suppressed && outcome != .expired }
    var acted: Bool    { outcome == .engaged }
    var dismissed: Bool { outcome == .dismissed }
}
