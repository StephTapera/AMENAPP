// DiscussionModeModels.swift — AMEN App
// Data models for the Discussion Modes Engine.

import SwiftUI

// MARK: - Discussion Mode

enum DiscussionMode: String, Codable, CaseIterable {
    case general, qa, prayer, study, testimony, mentorship, church, expert, community

    var displayName: String {
        switch self {
        case .general:     return "Discussion"
        case .qa:          return "Q&A"
        case .prayer:      return "Prayer"
        case .study:       return "Study"
        case .testimony:   return "Testimony"
        case .mentorship:  return "Mentorship"
        case .church:      return "Church"
        case .expert:      return "Expert"
        case .community:   return "Community"
        }
    }

    var icon: String {
        switch self {
        case .general:     return "bubble.left.and.bubble.right"
        case .qa:          return "questionmark.circle"
        case .prayer:      return "hands.sparkles"
        case .study:       return "book.closed"
        case .testimony:   return "person.wave.2"
        case .mentorship:  return "person.2.circle"
        case .church:      return "building.columns"
        case .expert:      return "checkmark.seal"
        case .community:   return "person.3"
        }
    }

    var composerPlaceholder: String {
        switch self {
        case .general:     return "Share your perspective…"
        case .qa:          return "Ask a question or share an answer…"
        case .prayer:      return "Share a prayer or encouragement…"
        case .study:       return "Share a study insight or reflection…"
        case .testimony:   return "Share what God has done in your life…"
        case .mentorship:  return "Share wisdom or ask for guidance…"
        case .church:      return "Share with your church community…"
        case .expert:      return "Share your expertise…"
        case .community:   return "Share with the community…"
        }
    }

    var availableResponseTypes: [DiscussionResponseType] {
        switch self {
        case .general:     return [.comment, .question, .reflection, .resource]
        case .qa:          return [.question, .comment, .resource, .correction]
        case .prayer:      return [.prayer, .encouragement, .reflection, .testimony]
        case .study:       return [.studyNote, .question, .comment, .resource]
        case .testimony:   return [.testimony, .encouragement, .prayer, .reflection]
        case .mentorship:  return [.comment, .question, .encouragement, .actionItem]
        case .church:      return [.comment, .prayer, .encouragement, .actionItem]
        case .expert:      return [.comment, .question, .correction, .resource]
        case .community:   return [.comment, .question, .encouragement, .actionItem]
        }
    }

    var accentColor: Color {
        switch self {
        case .prayer:      return Color(hex: "#8B7CC8")
        case .study:       return Color(hex: "#4A9B8A")
        case .expert:      return Color(hex: "#C9A84C")
        default:           return Color(hex: "#C9A84C")
        }
    }

    var moderationLevel: DiscussionModerationLevel {
        switch self {
        case .church, .expert: return .moderated
        case .prayer, .testimony: return .sensitive
        default: return .standard
        }
    }
}

// MARK: - Response Type

enum DiscussionResponseType: String, Codable, CaseIterable {
    case comment, question, prayer, reflection, testimony, resource,
         studyNote, encouragement, correction, actionItem

    var label: String {
        switch self {
        case .comment:      return "Comment"
        case .question:     return "Question"
        case .prayer:       return "Prayer"
        case .reflection:   return "Reflection"
        case .testimony:    return "Testimony"
        case .resource:     return "Resource"
        case .studyNote:    return "Study Note"
        case .encouragement:return "Encourage"
        case .correction:   return "Correction"
        case .actionItem:   return "Action"
        }
    }

    var icon: String {
        switch self {
        case .comment:      return "bubble.left"
        case .question:     return "questionmark"
        case .prayer:       return "hands.sparkles"
        case .reflection:   return "moon.stars"
        case .testimony:    return "person.wave.2"
        case .resource:     return "link"
        case .studyNote:    return "book.closed"
        case .encouragement:return "heart"
        case .correction:   return "checkmark.circle"
        case .actionItem:   return "bolt"
        }
    }
}

// MARK: - Supporting Types

enum DiscussionRankingStrategy: String, Codable {
    case chronological, helpfulness, contextScore, expertFirst
}

enum DiscussionModerationLevel: String, Codable {
    case standard, sensitive, moderated
}
