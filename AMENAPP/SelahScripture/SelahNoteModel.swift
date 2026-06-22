//
//  SelahNoteModel.swift
//  AMENAPP
//
//  Personal corpus unit for the Selah Scripture reader.
//  Mirrors the SelahNote interface from selah.contracts.ts (FROZEN CONTRACT).
//
//  HARD LEGAL CONSTRAINT:
//  `translationRead` is for display ONLY and must NEVER be passed to any AI
//  engine, discernment check, Cloud Function, or Pinecone namespace.
//  Soft-delete only: `deletedAt` is the sole delete mechanism; hard-delete is
//  forbidden per contract §3.
//

import Foundation
import SwiftUI

// MARK: - SelahNoteKind

/// Classification of a personal corpus note.
/// Mirrors contracts: kind: 'highlight' | 'note' | 'question' | 'prayer'
enum SelahNoteKind: String, Codable, CaseIterable {
    case highlight
    case note
    case question
    case prayer
}

// MARK: - SelahNote

/// Personal corpus unit — atomic unit of the user's private study corpus.
///
/// Invariants enforced here and in SelahNoteService:
/// - `translationRead` never flows into any CF call payload.
/// - `deletedAt` is the ONLY delete mechanism; no hard-delete path.
/// - `indexedToCorpus` is set to `true` only after a successful
///   `indexSelahNote` Cloud Function call.
struct SelahNote: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let verseRef: String
    /// The translation the user is reading. May be a licensed version (ESV,
    /// NIV, NLT, etc.). For display ONLY — NEVER passed to the AI citation
    /// path, any Cloud Function, or Pinecone.
    let translationRead: String
    let kind: SelahNoteKind
    /// Hex color from the highlight palette (§8). One of the 4 defined values,
    /// or nil for note/question/prayer kinds.
    let color: String?
    let body: String?
    /// `true` after a successful `indexSelahNote` CF call.
    var indexedToCorpus: Bool
    let createdAt: TimeInterval
    var updatedAt: TimeInterval
    /// `nil` = active note. Non-nil = soft-deleted. ONLY delete mechanism.
    var deletedAt: TimeInterval?
}

// MARK: - SelahNote Factory

extension SelahNote {
    /// Create a new, un-indexed SelahNote with a fresh UUID and current
    /// timestamps. The caller passes all domain values; no defaults are
    /// assumed for `verseRef`, `translationRead`, or `kind`.
    static func new(
        userId: String,
        verseRef: String,
        translationRead: String,
        kind: SelahNoteKind,
        color: String? = nil,
        body: String? = nil
    ) -> SelahNote {
        let now = Date().timeIntervalSince1970
        return SelahNote(
            id: UUID().uuidString,
            userId: userId,
            verseRef: verseRef,
            translationRead: translationRead,
            kind: kind,
            color: color,
            body: body,
            indexedToCorpus: false,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
    }
}

// MARK: - SelahHighlightColor

/// The four highlight palette colors for verse annotation.
/// Matches contracts §8 `GLASS_TOKENS.highlightColors`.
/// These colors are exempt from the Selah UI color ban (reader path only).
enum SelahHighlightColor: String, CaseIterable {
    /// rgba(100, 200, 220, 0.25) — stored as hex with alpha
    case cyan     = "#64C8DC40"
    /// rgba(255, 180, 50, 0.25)
    case amber    = "#FFB43240"
    /// rgba(255, 100, 150, 0.20) — note: 0x33 ≈ 0.20 alpha
    case pink     = "#FF646633"
    /// rgba(160, 130, 255, 0.22) — note: 0x38 ≈ 0.22 alpha
    case lavender = "#A082FF38"

    /// SwiftUI Color parsed from the hex-with-alpha raw value.
    var displayColor: Color {
        switch self {
        case .cyan:
            return Color(red: 100/255, green: 200/255, blue: 220/255, opacity: 0.25)
        case .amber:
            return Color(red: 255/255, green: 180/255, blue: 50/255, opacity: 0.25)
        case .pink:
            return Color(red: 255/255, green: 100/255, blue: 150/255, opacity: 0.20)
        case .lavender:
            return Color(red: 160/255, green: 130/255, blue: 255/255, opacity: 0.22)
        }
    }

    var label: String {
        switch self {
        case .cyan:     return "Blue"
        case .amber:    return "Amber"
        case .pink:     return "Pink"
        case .lavender: return "Lavender"
        }
    }
}
