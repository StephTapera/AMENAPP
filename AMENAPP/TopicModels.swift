// TopicModels.swift
// AMENAPP
//
// Canonical topic types, feed filter/sort enums, and topic score model
// for the Topic Drill-Down system (System 11).

import Foundation

// MARK: - Canonical Topic

/// A normalized topic key with display metadata.
/// Maps user-typed labels and SemanticTopicService clusters to a single canonical form.
struct CanonicalTopic: Identifiable, Codable, Hashable {
    /// Lowercased, hyphenated key used in Firestore `normalizedTopicKeys` arrays.
    /// Example: "faith-and-work", "mental-health", "prayer"
    let key: String

    /// Human-readable display label.
    let displayName: String

    /// The SemanticTopicService cluster this maps to (if any).
    let cluster: SpiritualTopicCluster?

    var id: String { key }

    /// Firestore-safe key derived from display name.
    static func canonicalKey(from raw: String) -> String {
        raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "--", with: "-")
    }
}

// MARK: - Topic Feed Filter

enum TopicFeedFilter: String, CaseIterable, Identifiable {
    case all          = "all"
    case openTable    = "openTable"
    case testimonies  = "testimonies"
    case prayer       = "prayer"
    case tip          = "tip"
    case funFact      = "funFact"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:          return "All"
        case .openTable:    return "#OPENTABLE"
        case .testimonies:  return "Testimonies"
        case .prayer:       return "Prayer"
        case .tip:          return "Tips"
        case .funFact:      return "Fun Facts"
        }
    }

    /// Maps to the Post.PostCategory for Firestore queries.
    /// Returns nil for `.all` (no category filter).
    var postCategory: Post.PostCategory? {
        switch self {
        case .all:          return nil
        case .openTable:    return .openTable
        case .testimonies:  return .testimonies
        case .prayer:       return .prayer
        case .tip:          return .tip
        case .funFact:      return .funFact
        }
    }
}

// MARK: - Topic Feed Sort

enum TopicFeedSort: String, CaseIterable, Identifiable {
    case recent   = "recent"
    case popular  = "popular"
    case relevant = "relevant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recent:   return "Recent"
        case .popular:  return "Popular"
        case .relevant: return "Relevant"
        }
    }

    var icon: String {
        switch self {
        case .recent:   return "clock"
        case .popular:  return "flame"
        case .relevant: return "sparkles"
        }
    }
}

// MARK: - Topic Score Entry

/// Per-topic confidence score stored in a post's `topicScoreMap`.
/// Keys are canonical topic keys, values are 0–1.0 confidence from SemanticTopicService.
typealias TopicScoreMap = [String: Double]
