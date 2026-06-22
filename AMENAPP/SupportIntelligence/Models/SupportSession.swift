//
//  SupportSession.swift
//  AMENAPP
//
//  A single support interaction session (e.g., user opens grounding tool).
//  Stored at users/{userId}/support_sessions/{sessionId}.
//

import Foundation

struct SupportSession: Identifiable, Codable, Sendable {
    var id: String
    var sessionType: String         // "wellness_flow", "crisis_flow", "resource_browse"
    var entrySurface: SupportSurface
    var entryReason: String         // SupportReasonCode or prompt type
    var startedAt: Date
    var endedAt: Date?
    var actionsPerformed: [String]  // e.g., "opened_grounding", "dismissed_reachout"
    var resolvedState: String?      // "deescalated", "continued", "escalated"

    var duration: TimeInterval? {
        guard let end = endedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
}
