// CommunityNotesModels.swift
// AMENAPP — Community Notes data model layer
//
// NoteCategory, CommunityNote, NoteVisibility, and search types.
// All color tokens from AmenTheme.Colors — no raw system colors.

import SwiftUI
import FirebaseFirestore

// MARK: - NoteCategory

enum NoteCategory: String, CaseIterable, Codable, Identifiable {
    case sermon     = "sermon"
    case revelation = "revelation"
    case study      = "study"
    case prayer     = "prayer"
    case testimony  = "testimony"
    case devotional = "devotional"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sermon:     return "Sermon Notes"
        case .revelation: return "Revelation"
        case .study:      return "Bible Study"
        case .prayer:     return "Prayer"
        case .testimony:  return "Testimony"
        case .devotional: return "Devotional"
        }
    }

    var icon: String {
        switch self {
        case .sermon:     return "doc.text.fill"
        case .revelation: return "lightbulb.fill"
        case .study:      return "book.fill"
        case .prayer:     return "hands.sparkles.fill"
        case .testimony:  return "person.fill.checkmark"
        case .devotional: return "sunrise.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sermon:     return AmenTheme.Colors.amenPurple
        case .revelation: return AmenTheme.Colors.amenGold
        case .study:      return AmenTheme.Colors.amenBlue
        case .prayer:     return AmenTheme.Colors.amenGold
        case .testimony:  return AmenTheme.Colors.amenPurple
        case .devotional: return AmenTheme.Colors.amenBlue
        }
    }
}

// MARK: - NoteVisibility

enum NoteVisibility: String, Codable {
    case public_    = "public"
    case followers  = "followers"
    case private_   = "private"

    var displayName: String {
        switch self {
        case .public_:   return "Public"
        case .followers: return "Followers"
        case .private_:  return "Private"
        }
    }

    var icon: String {
        switch self {
        case .public_:   return "globe.americas.fill"
        case .followers: return "person.2.fill"
        case .private_:  return "lock.fill"
        }
    }

    var description: String {
        switch self {
        case .public_:
            return "Anyone in the AMEN community can read this note."
        case .followers:
            return "Only your followers can read this note."
        case .private_:
            return "Only you can see this note."
        }
    }
}

// MARK: - CommunityNote

struct CommunityNote: Identifiable, Codable {
    var id: String
    var authorId: String
    var authorName: String
    var authorHandle: String
    var authorInitial: String
    var authorColor: String          // hex string, e.g. "#7243CC"
    var title: String
    var excerpt: String
    var body: String
    var category: NoteCategory
    var tags: [String]
    var scriptureRefStrings: [String] // human-readable, e.g. ["Romans 8:28", "John 3:16"]
    var scriptureKeys: [String]       // Firestore lookup keys, e.g. ["ROM.8.28", "JHN.3.16"]
    var visibility: NoteVisibility
    var likeCount: Int
    var commentCount: Int
    var saveCount: Int
    var createdAt: Date
    var updatedAt: Date
    var publishedAt: Date?

    // MARK: - Firestore coding keys

    enum CodingKeys: String, CodingKey {
        case id
        case authorId
        case authorName
        case authorHandle
        case authorInitial
        case authorColor
        case title
        case excerpt
        case body
        case category
        case tags
        case scriptureRefStrings
        case scriptureKeys
        case visibility
        case likeCount
        case commentCount
        case saveCount
        case createdAt
        case updatedAt
        case publishedAt
    }

    // MARK: - Convenience

    /// Hex string → SwiftUI Color. Falls back to amenPurple if the hex is invalid.
    var authorSwiftUIColor: Color {
        Color(hex: authorColor) ?? AmenTheme.Colors.amenPurple
    }
}

// MARK: - CommunityNotesSearchResult
// Lighter struct returned by the `searchCommunityNotes` Cloud Function.
// Only the fields needed to render CommunityNoteCardView.

struct CommunityNotesSearchResult: Identifiable, Codable {
    var id: String
    var authorName: String
    var authorHandle: String
    var authorInitial: String
    var authorColor: String
    var title: String
    var excerpt: String
    var category: NoteCategory
    var scriptureRefStrings: [String]
    var likeCount: Int
    var commentCount: Int
    var score: Double?          // relevance score from the CF, optional

    var authorSwiftUIColor: Color {
        Color(hex: authorColor) ?? AmenTheme.Colors.amenPurple
    }
}

// MARK: - NotesSearchRequest

struct NotesSearchRequest: Codable {
    var query: String
    var category: NoteCategory?
    var scriptureKey: String?
    /// "hybrid" | "semantic" | "keyword"
    var mode: String = "hybrid"
}

// MARK: - Color hex init (private helper)

private extension Color {
    /// Initialise from a 6-digit hex string with optional leading "#".
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.count == 6,
              let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8)  & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
