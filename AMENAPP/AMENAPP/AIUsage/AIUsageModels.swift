import Foundation
import FirebaseFirestore

// Bridge: PostAILabel maps to the existing AIPublicLabel type defined in PostAIUsage.swift
typealias PostAILabel = AIPublicLabel

// MARK: - AI Usage Event (analytics only, no raw text stored)

struct AIUsageEvent: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let targetType: String          // "post", "comment", "prayer", "church_note"
    let targetId: String
    let aiUseTypes: [String]
    let primaryLabel: String?
    let eventType: String           // "tone_checker_used", "tone_rewrite_accepted", "ai_label_rendered"
    @ServerTimestamp var timestamp: Date?
}
