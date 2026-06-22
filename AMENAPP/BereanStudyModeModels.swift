//
//  BereanStudyModeModels.swift
//  AMENAPP
//
//  Study Mode state and reasoning categories for Berean chat.
//

import Foundation

enum BereanStudyModeState: Equatable {
    case off
    case idle
    case reasoning
    case resolved
    case collapsedSummary
}

enum BereanReasoningCategory: String, CaseIterable, Identifiable {
    case scripture
    case crossReferences
    case commentary
    case sermons
    case articles
    case originalLanguage
    case historicalContext
    case application
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scripture: return "Scripture"
        case .crossReferences: return "Cross References"
        case .commentary: return "Commentary"
        case .sermons: return "Sermons"
        case .articles: return "Articles"
        case .originalLanguage: return "Original Language"
        case .historicalContext: return "Context"
        case .application: return "Application"
        case .notes: return "Notes"
        }
    }

    var icon: String {
        switch self {
        case .scripture: return "book"
        case .crossReferences: return "link"
        case .commentary: return "text.book.closed"
        case .sermons: return "mic"
        case .articles: return "doc.text"
        case .originalLanguage: return "character.book.closed"
        case .historicalContext: return "clock"
        case .application: return "sparkles"
        case .notes: return "note.text"
        }
    }
}

enum BereanReasoningCategoryState: Equatable {
    case idle
    case scanning
    case active
    case complete
}

struct BereanReasoningNode: Identifiable, Equatable {
    let id = UUID()
    let category: BereanReasoningCategory
    var state: BereanReasoningCategoryState
    var summary: String?
}
