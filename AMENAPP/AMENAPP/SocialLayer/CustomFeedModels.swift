// CustomFeedModels.swift
// AMENAPP — SocialLayer
//
// Supplementary types for the Custom Feeds feature.
// Core contract types (CustomFeedConfig, CustomFeedSlot) live in ComposerContract.swift.
// Do NOT redefine those here.

import Foundation

// MARK: - DefaultFeed icon map

/// Maps the well-known built-in feed names to their canonical SF Symbol.
/// Used by CustomFeedEditorView to show the right icon per feed row.
enum DefaultFeedIcon {
    static let symbolMap: [String: String] = [
        "For You":     "sparkles",
        "Following":   "person.2.fill",
        "Prayer":      "hands.sparkles.fill",
        "Testimonies": "star.bubble.fill",
        "Scripture":   "book.fill",
        "Your Church": "building.columns.fill",
    ]

    /// Returns the SF Symbol name for a feed name, or a generic fallback.
    static func symbol(for feedName: String) -> String {
        symbolMap[feedName] ?? "list.bullet"
    }
}

// MARK: - Topic picker option

/// Static topic options presented in CreateFeedSheet (faith-community topics).
/// Distinct from HeyFeedModels.FeedTopic which covers general-interest topics.
enum CustomFeedTopic: String, CaseIterable, Identifiable {
    case scripture  = "Scripture"
    case prayer     = "Prayer"
    case worship    = "Worship"
    case testimony  = "Testimony"
    case churchLife = "Church Life"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .scripture:  return "book.fill"
        case .prayer:     return "hands.sparkles.fill"
        case .worship:    return "music.note"
        case .testimony:  return "star.bubble.fill"
        case .churchLife: return "building.columns.fill"
        }
    }
}

// MARK: - CustomFeedServiceError

enum CustomFeedServiceError: LocalizedError {
    case builtInDeletionForbidden
    case firestoreWriteFailed(Error)
    case missingUserId

    var errorDescription: String? {
        switch self {
        case .builtInDeletionForbidden:
            return "Built-in feeds cannot be deleted."
        case .firestoreWriteFailed(let underlying):
            return "Feed could not be saved: \(underlying.localizedDescription)"
        case .missingUserId:
            return "User ID is required to manage feeds."
        }
    }
}
