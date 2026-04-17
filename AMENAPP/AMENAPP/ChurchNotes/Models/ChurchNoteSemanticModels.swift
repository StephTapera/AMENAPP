// ChurchNoteSemanticModels.swift
// AMENAPP
//
// Semantic extension layer for Church Notes.
// Adds typed payloads, extended block types, visibility, pinning, and semantic
// meaning on top of the existing ChurchNoteBlock/ChurchNoteHighlightType foundation.
//
// Key design rules:
//   - Does NOT redeclare ChurchNoteBlockType, ChurchNoteHighlightType, or ChurchNoteFormatStyle.
//   - ChurchNoteBlockV2 is used for all new notes; existing ChurchNote.blocks (V1) remain unchanged.
//   - Payload types are exhaustive but lightweight — no nested observable state.

import Foundation
import SwiftUI

// MARK: - Extended Block Type

enum ChurchNoteBlockV2Type: String, Codable, CaseIterable, Hashable, Identifiable {
    // --- Core content ---
    case paragraph
    case heading
    case subheading
    case bulletList
    case numberedList
    case checklist
    case quote
    case divider
    case section        // collapsible container

    // --- Semantic callouts ---
    case callout        // smart callout box (prayer, action, question, etc.)
    case verseEmbed     // first-class verse block
    case annotation     // margin note / study annotation

    // --- Legacy parity ---
    case takeaway       // maps to existing .takeaway block type
    case prayer         // maps to existing .prayer
    case action         // maps to existing .action
    case scripture      // maps to existing .scripture

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paragraph:    return "Paragraph"
        case .heading:      return "Heading"
        case .subheading:   return "Subheading"
        case .bulletList:   return "Bullet List"
        case .numberedList: return "Numbered List"
        case .checklist:    return "Checklist"
        case .quote:        return "Quote"
        case .divider:      return "Divider"
        case .section:      return "Section"
        case .callout:      return "Callout"
        case .verseEmbed:   return "Verse"
        case .annotation:   return "Annotation"
        case .takeaway:     return "Key Takeaway"
        case .prayer:       return "Prayer"
        case .action:       return "Action Step"
        case .scripture:    return "Scripture"
        }
    }

    var icon: String {
        switch self {
        case .paragraph:    return "text.alignleft"
        case .heading:      return "textformat.size.larger"
        case .subheading:   return "textformat.size"
        case .bulletList:   return "list.bullet"
        case .numberedList: return "list.number"
        case .checklist:    return "checklist"
        case .quote:        return "quote.opening"
        case .divider:      return "minus"
        case .section:      return "rectangle.compress.vertical"
        case .callout:      return "bell.badge"
        case .verseEmbed:   return "book.fill"
        case .annotation:   return "pencil.and.scribble"
        case .takeaway:     return "lightbulb.fill"
        case .prayer:       return "hands.sparkles.fill"
        case .action:       return "checkmark.circle.fill"
        case .scripture:    return "book.fill"
        }
    }

    /// Blocks a user can insert from the + menu in the editor.
    static var insertableTypes: [ChurchNoteBlockV2Type] {
        [.paragraph, .heading, .subheading, .bulletList, .numberedList,
         .checklist, .quote, .divider, .section, .callout, .verseEmbed,
         .annotation, .takeaway, .prayer, .action]
    }
}

// MARK: - Semantic Type

/// What the block *means* spiritually/intellectually — orthogonal to visual block type.
enum ChurchNoteSemanticType: String, Codable, CaseIterable, Hashable, Identifiable {
    case keyTruth
    case prayerPoint
    case conviction
    case question
    case actionStep
    case verseInsight
    case pastorQuote
    case reflection
    case discussion
    case testimony
    case memoryVerse
    case followUp
    case leadershipNote
    case ministryIdea
    case general           // default — no specific semantic intent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keyTruth:        return "Key Truth"
        case .prayerPoint:     return "Prayer Point"
        case .conviction:      return "Conviction"
        case .question:        return "Question"
        case .actionStep:      return "Action Step"
        case .verseInsight:    return "Verse Insight"
        case .pastorQuote:     return "Pastor Quote"
        case .reflection:      return "Reflection"
        case .discussion:      return "Discussion"
        case .testimony:       return "Testimony"
        case .memoryVerse:     return "Memory Verse"
        case .followUp:        return "Follow Up"
        case .leadershipNote:  return "Leadership Note"
        case .ministryIdea:    return "Ministry Idea"
        case .general:         return "Note"
        }
    }

    var icon: String {
        switch self {
        case .keyTruth:        return "lightbulb.fill"
        case .prayerPoint:     return "hands.sparkles.fill"
        case .conviction:      return "heart.circle.fill"
        case .question:        return "questionmark.circle"
        case .actionStep:      return "checkmark.circle.fill"
        case .verseInsight:    return "book.fill"
        case .pastorQuote:     return "quote.opening"
        case .reflection:      return "heart.text.clipboard.fill"
        case .discussion:      return "bubble.left.and.bubble.right.fill"
        case .testimony:       return "person.wave.2.fill"
        case .memoryVerse:     return "memory"
        case .followUp:        return "arrow.circlepath"
        case .leadershipNote:  return "person.badge.shield.checkmark"
        case .ministryIdea:    return "sparkles"
        case .general:         return "text.alignleft"
        }
    }

    /// Semantic label color for tinting icons and accent lines.
    var accentColor: Color {
        switch self {
        case .keyTruth:        return Color(hex: "F4C430")   // warm amber
        case .prayerPoint:     return Color(hex: "E8A0A8")   // rose
        case .conviction:      return Color(hex: "D97070")   // soft red
        case .question:        return Color(hex: "6FA8DC")   // sky blue
        case .actionStep:      return Color(hex: "7DBD8A")   // sage green
        case .verseInsight:    return Color(hex: "8AA8D8")   // dusty blue
        case .pastorQuote:     return Color(hex: "A89AC8")   // lavender
        case .reflection:      return Color(hex: "E8C070")   // gold
        case .discussion:      return Color(hex: "89C4C0")   // teal
        case .testimony:       return Color(hex: "C4A0B8")   // mauve
        case .memoryVerse:     return Color(hex: "7BBAD4")   // cerulean
        case .followUp:        return Color(hex: "A0C48C")   // light green
        case .leadershipNote:  return Color(hex: "88A0C4")   // steel blue
        case .ministryIdea:    return Color(hex: "C8A4D8")   // soft purple
        case .general:         return Color(.secondaryLabel)
        }
    }
}

// MARK: - Visibility

enum ChurchNoteVisibility: String, Codable, CaseIterable, Hashable {
    case privateOnly              // never leaves device / stays private
    case shareable                // can appear in a post or share
    case selectedForPostPreview   // explicitly chosen for post card
    case selectedForSelahEmphasis // pinned to Selah recap view

    var displayName: String {
        switch self {
        case .privateOnly:            return "Private"
        case .shareable:              return "Shareable"
        case .selectedForPostPreview: return "Post Preview"
        case .selectedForSelahEmphasis: return "Selah Emphasis"
        }
    }

    var icon: String {
        switch self {
        case .privateOnly:            return "lock.fill"
        case .shareable:              return "square.and.arrow.up"
        case .selectedForPostPreview: return "rectangle.and.pencil.and.ellipsis"
        case .selectedForSelahEmphasis: return "sparkles"
        }
    }
}

// MARK: - Pinned / Anchor State

enum ChurchNotePinnedState: String, Codable, CaseIterable, Hashable {
    case none
    case anchorInsight    // the key insight of this note
    case memoryVerse      // verse to memorize
    case revisitThisWeek  // midweek reminder candidate
    case shareLater       // queue for sharing

    var displayName: String {
        switch self {
        case .none:             return "Not Pinned"
        case .anchorInsight:    return "Anchor Insight"
        case .memoryVerse:      return "Memory Verse"
        case .revisitThisWeek:  return "Revisit This Week"
        case .shareLater:       return "Share Later"
        }
    }

    var icon: String {
        switch self {
        case .none:             return "pin.slash"
        case .anchorInsight:    return "anchor"
        case .memoryVerse:      return "text.badge.checkmark"
        case .revisitThisWeek:  return "arrow.circlepath"
        case .shareLater:       return "square.and.arrow.up.on.square"
        }
    }
}

// MARK: - Callout Style

enum ChurchNoteCalloutStyle: String, Codable, CaseIterable, Hashable, Identifiable {
    case prayer
    case reflection
    case action
    case question
    case counselingInsight
    case leadershipNote
    case familyNote
    case ministryIdea

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prayer:             return "Prayer"
        case .reflection:         return "Reflection"
        case .action:             return "Action"
        case .question:           return "Question"
        case .counselingInsight:  return "Counseling Insight"
        case .leadershipNote:     return "Leadership Note"
        case .familyNote:         return "Family Note"
        case .ministryIdea:       return "Ministry Idea"
        }
    }

    var icon: String {
        switch self {
        case .prayer:             return "hands.sparkles.fill"
        case .reflection:         return "heart.text.clipboard.fill"
        case .action:             return "checkmark.circle.fill"
        case .question:           return "questionmark.circle.fill"
        case .counselingInsight:  return "person.2.fill"
        case .leadershipNote:     return "person.badge.shield.checkmark.fill"
        case .familyNote:         return "figure.2.and.child.holdinghands"
        case .ministryIdea:       return "sparkles"
        }
    }

    /// Background fill tint for callout box.
    var fillColor: Color {
        switch self {
        case .prayer:             return Color(hex: "F7E8EA").opacity(0.6)
        case .reflection:         return Color(hex: "F5EFD8").opacity(0.6)
        case .action:             return Color(hex: "E4F0E0").opacity(0.6)
        case .question:           return Color(hex: "DCE9F5").opacity(0.6)
        case .counselingInsight:  return Color(hex: "EDE8F0").opacity(0.6)
        case .leadershipNote:     return Color(hex: "E0E8F0").opacity(0.6)
        case .familyNote:         return Color(hex: "F0EDE0").opacity(0.6)
        case .ministryIdea:       return Color(hex: "EDE0F0").opacity(0.6)
        }
    }

    var borderColor: Color {
        switch self {
        case .prayer:             return Color(hex: "D4A0AA")
        case .reflection:         return Color(hex: "C8B870")
        case .action:             return Color(hex: "9CC490")
        case .question:           return Color(hex: "90B8D8")
        case .counselingInsight:  return Color(hex: "B8A8C8")
        case .leadershipNote:     return Color(hex: "90A8C4")
        case .familyNote:         return Color(hex: "C4B888")
        case .ministryIdea:       return Color(hex: "B890C8")
        }
    }
}

// MARK: - Checklist Category

enum ChurchNoteChecklistCategory: String, Codable, CaseIterable, Hashable, Identifiable {
    case actionSteps
    case prayerCommitments
    case followUp
    case scriptureToRevisit
    case peopleToEncourage
    case questionsToAsk
    case ministryTasks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .actionSteps:         return "Action Steps"
        case .prayerCommitments:   return "Prayer Commitments"
        case .followUp:            return "Follow Up"
        case .scriptureToRevisit:  return "Scripture to Revisit"
        case .peopleToEncourage:   return "People to Encourage"
        case .questionsToAsk:      return "Questions to Ask"
        case .ministryTasks:       return "Ministry Tasks"
        }
    }

    var icon: String {
        switch self {
        case .actionSteps:         return "checkmark.circle"
        case .prayerCommitments:   return "hands.sparkles"
        case .followUp:            return "arrow.circlepath"
        case .scriptureToRevisit:  return "book"
        case .peopleToEncourage:   return "person.wave.2"
        case .questionsToAsk:      return "questionmark.circle"
        case .ministryTasks:       return "sparkles"
        }
    }
}

// MARK: - Block Payloads

/// Rich text span within a block body.
struct CNRichTextSpan: Codable, Equatable, Hashable {
    var text: String
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var highlight: ChurchNoteHighlightType?

    init(
        text: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        highlight: ChurchNoteHighlightType? = nil
    ) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.highlight = highlight
    }
}

/// Payload for a verse embed block.
struct VerseEmbedPayload: Codable, Equatable, Hashable {
    var reference: String        // e.g. "John 3:16"
    var translation: String      // e.g. "NIV"
    var verseText: String        // fetched verse body
    var commentary: String?      // user annotation on the verse
    var isExpanded: Bool         // compact pill vs. full card display
}

/// Payload for a smart callout block.
struct CalloutPayload: Codable, Equatable, Hashable {
    var style: ChurchNoteCalloutStyle
    var prompt: String?          // optional heading prompt shown in the callout
}

/// Payload for a collapsible section header block.
struct SectionPayload: Codable, Equatable, Hashable {
    var heading: String
    var isCollapsed: Bool
}

/// A single checklist item.
struct CNChecklistItem: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var text: String
    var completed: Bool
    var category: ChurchNoteChecklistCategory?

    init(
        id: String = UUID().uuidString,
        text: String,
        completed: Bool = false,
        category: ChurchNoteChecklistCategory? = nil
    ) {
        self.id = id
        self.text = text
        self.completed = completed
        self.category = category
    }
}

/// Payload for a semantic checklist block.
struct ChecklistPayload: Codable, Equatable, Hashable {
    var category: ChurchNoteChecklistCategory
    var items: [CNChecklistItem]
}

// MARK: - Block V2

/// Top-level semantic block for the new Church Notes system.
/// Stored as `churchNotes/{noteId}/blocks/{blockId}` subcollection documents.
struct ChurchNoteBlockV2: Codable, Identifiable, Hashable {
    var id: String
    var sortOrder: Int
    var type: ChurchNoteBlockV2Type
    var semanticType: ChurchNoteSemanticType
    var visibility: ChurchNoteVisibility
    var pinnedState: ChurchNotePinnedState

    // Plain text body — always present, even for structured blocks (for search/AI export).
    var text: String

    // Rich text spans for paragraph / quote / takeaway / annotation blocks.
    // nil for blocks that use a dedicated payload (verse, checklist, callout, section).
    var richSpans: [CNRichTextSpan]?

    // Typed payloads — at most one will be non-nil per block.
    var versePayload: VerseEmbedPayload?
    var calloutPayload: CalloutPayload?
    var sectionPayload: SectionPayload?
    var checklistPayload: ChecklistPayload?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        sortOrder: Int = 0,
        type: ChurchNoteBlockV2Type,
        semanticType: ChurchNoteSemanticType = .general,
        visibility: ChurchNoteVisibility = .privateOnly,
        pinnedState: ChurchNotePinnedState = .none,
        text: String = "",
        richSpans: [CNRichTextSpan]? = nil,
        versePayload: VerseEmbedPayload? = nil,
        calloutPayload: CalloutPayload? = nil,
        sectionPayload: SectionPayload? = nil,
        checklistPayload: ChecklistPayload? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.type = type
        self.semanticType = semanticType
        self.visibility = visibility
        self.pinnedState = pinnedState
        self.text = text
        self.richSpans = richSpans
        self.versePayload = versePayload
        self.calloutPayload = calloutPayload
        self.sectionPayload = sectionPayload
        self.checklistPayload = checklistPayload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: Factory helpers

    static func paragraph(text: String = "", order: Int = 0) -> ChurchNoteBlockV2 {
        ChurchNoteBlockV2(sortOrder: order, type: .paragraph, text: text)
    }

    static func callout(style: ChurchNoteCalloutStyle, order: Int = 0) -> ChurchNoteBlockV2 {
        ChurchNoteBlockV2(
            sortOrder: order,
            type: .callout,
            semanticType: style.defaultSemanticType,
            calloutPayload: CalloutPayload(style: style, prompt: style.defaultPrompt)
        )
    }

    static func checklist(category: ChurchNoteChecklistCategory, order: Int = 0) -> ChurchNoteBlockV2 {
        ChurchNoteBlockV2(
            sortOrder: order,
            type: .checklist,
            checklistPayload: ChecklistPayload(category: category, items: [])
        )
    }

    static func verseEmbed(reference: String, text: String, translation: String = "NIV", order: Int = 0) -> ChurchNoteBlockV2 {
        ChurchNoteBlockV2(
            sortOrder: order,
            type: .verseEmbed,
            semanticType: .verseInsight,
            text: text,
            versePayload: VerseEmbedPayload(
                reference: reference,
                translation: translation,
                verseText: text,
                commentary: nil,
                isExpanded: false
            )
        )
    }
}

// MARK: - ChurchNoteCalloutStyle conveniences

private extension ChurchNoteCalloutStyle {
    var defaultSemanticType: ChurchNoteSemanticType {
        switch self {
        case .prayer:            return .prayerPoint
        case .reflection:        return .reflection
        case .action:            return .actionStep
        case .question:          return .question
        case .counselingInsight: return .reflection
        case .leadershipNote:    return .leadershipNote
        case .familyNote:        return .general
        case .ministryIdea:      return .ministryIdea
        }
    }

    var defaultPrompt: String? {
        switch self {
        case .prayer:            return "What do you want to pray about?"
        case .reflection:        return "What stood out to you?"
        case .action:            return "What will you do this week?"
        case .question:          return "What question do you have?"
        case .counselingInsight: return nil
        case .leadershipNote:    return nil
        case .familyNote:        return nil
        case .ministryIdea:      return "What's the idea?"
        }
    }
}

// MARK: - Note document (top-level, not subcollection)

/// Top-level Firestore document at `churchNotes/{noteId}`.
/// Blocks are stored in the `blocks` subcollection, not inlined.
struct ChurchNoteV2: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    var title: String
    var sermonTitle: String?
    var sermonSpeaker: String?
    var churchId: String?
    var serviceDate: Date?
    var journeyId: String?      // links to a ChurchJourney if taken during a visit
    var noteSessionId: String?  // links to a ChurchNoteSession (Journey system)
    var tags: [String]
    var scriptureReferences: [String]
    var blockCount: Int         // denormalized for list views (avoids subcollection reads)
    var hasShareableBlocks: Bool // denormalized — true if any block has .shareable or .selectedForPostPreview
    var pinnedBlockIds: [String] // ordered list of pinned block IDs for quick access
    var schemaVersion: Int      // 2 = semantic block system
    let createdAt: Date
    var updatedAt: Date

    static func empty(userId: String) -> ChurchNoteV2 {
        ChurchNoteV2(
            id: UUID().uuidString,
            userId: userId,
            title: "",
            sermonTitle: nil,
            sermonSpeaker: nil,
            churchId: nil,
            serviceDate: nil,
            journeyId: nil,
            noteSessionId: nil,
            tags: [],
            scriptureReferences: [],
            blockCount: 0,
            hasShareableBlocks: false,
            pinnedBlockIds: [],
            schemaVersion: 2,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}


