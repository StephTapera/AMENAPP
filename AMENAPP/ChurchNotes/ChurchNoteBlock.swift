//
//  ChurchNoteBlock.swift
//  AMENAPP
//
//  Semantic block model for Church Notes.
//  Blocks represent structured content extracted from the note body
//  (e.g., a prayer, action step, quote, or scripture callout).
//

import Foundation

// MARK: - Block Type

enum ChurchNoteBlockType: String, Codable, CaseIterable, Hashable, Identifiable {
    case paragraph
    case quote
    case takeaway
    case prayer
    case action
    case reflection
    case scripture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paragraph:  return "Paragraph"
        case .quote:      return "Quote"
        case .takeaway:   return "Takeaway"
        case .prayer:     return "Prayer"
        case .action:     return "Action Step"
        case .reflection: return "Reflection"
        case .scripture:  return "Scripture"
        }
    }

    var icon: String {
        switch self {
        case .paragraph:  return "text.alignleft"
        case .quote:      return "quote.opening"
        case .takeaway:   return "lightbulb.fill"
        case .prayer:     return "hands.sparkles.fill"
        case .action:     return "checkmark.circle.fill"
        case .reflection: return "heart.text.clipboard.fill"
        case .scripture:  return "book.fill"
        }
    }

    /// Whether this block type appears in conversion menus.
    var isConvertible: Bool {
        self != .paragraph
    }

    /// Corresponding highlight type for block tinting.
    var highlightType: ChurchNoteHighlightType? {
        switch self {
        case .paragraph:  return nil
        case .quote:      return .quote
        case .takeaway:   return .takeaway
        case .prayer:     return .prayer
        case .action:     return .action
        case .reflection: return nil
        case .scripture:  return .scripture
        }
    }
}

// MARK: - Block Model

struct ChurchNoteBlock: Codable, Identifiable, Hashable {
    var id: String
    var type: ChurchNoteBlockType
    var text: String
    var textRuns: [ChurchNoteTextRun]
    var highlight: ChurchNoteHighlightType?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        type: ChurchNoteBlockType,
        text: String,
        textRuns: [ChurchNoteTextRun] = [],
        highlight: ChurchNoteHighlightType? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.textRuns = textRuns.isEmpty ? [ChurchNoteTextRun(text: text, highlight: highlight ?? type.highlightType)] : textRuns
        self.highlight = highlight ?? type.highlightType
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case text
        case textRuns
        case highlight
        case tags
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try container.decode(ChurchNoteBlockType.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        highlight = try container.decodeIfPresent(ChurchNoteHighlightType.self, forKey: .highlight) ?? type.highlightType
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        textRuns = try container.decodeIfPresent([ChurchNoteTextRun].self, forKey: .textRuns)
            ?? [ChurchNoteTextRun(text: text, highlight: highlight)]
    }
}
