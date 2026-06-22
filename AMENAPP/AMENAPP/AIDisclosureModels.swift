// AIDisclosureModels.swift
// AMENAPP
//
// Server-issued AI disclosure record. Every field comes from the server —
// this type is NEVER constructed client-side with guessed values.
// See TrustSpineService.getAIDisclosureDetails for the callable.

import Foundation

struct AIDisclosureRecord: Identifiable, Codable, Hashable {
    let id: String
    let postId: String
    let mediaId: String
    let ownerUid: String
    let actionType: String        // e.g. "ai_translated", "ai_alt_text", "ai_generated"
    let modelProvider: String
    let purpose: String
    let userVisibleLabel: String
    let userVisibleExplanation: String
    let confidence: Double

    var iconName: String {
        switch actionType {
        case "ai_generated":   return "sparkles"
        case "ai_translated":  return "globe"
        case "ai_edited":      return "wand.and.stars"
        case "ai_alt_text":    return "accessibility"
        case "ai_summarized":  return "doc.text.magnifyingglass"
        case "ai_captioned":   return "captions.bubble"
        default:               return "info.circle"
        }
    }
}
