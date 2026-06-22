//
//  SupportGraphEdge.swift
//  AMENAPP
//
//  A private support relationship edge.
//  Stored at users/{userId}/support_graph/{edgeUserId}.
//  Never exposed publicly. Used internally to rank trusted contacts.
//

import Foundation

struct SupportGraphEdge: Identifiable, Codable, Sendable {
    var id: String                         // == edgeUserId
    var edgeUserId: String
    var supportStrength: Double            // 0.0–1.0 composite score
    var trustSignals: [String: Int]        // signal type → count
    var lastMeaningfulSupportAt: Date?
    var isMutualSupport: Bool
    var eligibleAsTrustedContact: Bool
    var updatedAt: Date?

    var supportiveReplies: Int  { trustSignals["supportiveReplies"] ?? 0 }
    var prayerInteractions: Int { trustSignals["prayerInteractions"] ?? 0 }
    var meaningfulDMs: Int      { trustSignals["meaningfulDMs"] ?? 0 }
    var resourceSharesAccepted: Int { trustSignals["resourceSharesAccepted"] ?? 0 }
}
