// AmenCreationIntentDetector.swift
// AMENAPP
// Simple intent detection heuristics for Universal Create.

import Foundation

struct AmenCreationIntentDetector {
    static func detectIntent(text: String, mediaRefs: [MediaRef]) -> AmenCreationIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if mediaRefs.contains(where: { $0.type == .video }) {
            return .videoPost
        }
        if mediaRefs.count > 1 {
            return .carousel
        }
        if !mediaRefs.isEmpty {
            return .photoPost
        }
        if trimmed.contains("?") {
            return .discussionPrompt
        }
        if trimmed.count > 400 {
            return .note
        }
        return .textPost
    }
}
