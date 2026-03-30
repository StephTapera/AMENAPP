//
//  ChurchNotesFeatureModels.swift
//  AMENAPP
//
//  New data models for the Church Notes smart features.
//  Does NOT redefine ChurchNote, WorshipSongReference, Color(hex:), or FlowLayout.
//

import SwiftUI
import Foundation

// MARK: - AI Insights

struct AIInsights: Codable {
    var detectedTheme: String
    var emotionalDepthScore: Double   // 0.0 to 1.0
    var actionItems: [String]
    var keyQuote: String
    var topKeywords: [String]
    var generatedAt: Date
}

// MARK: - Scripture DNA

struct ScriptureDNAResult: Identifiable, Codable {
    var id: UUID
    var reference: String
    var verseText: String
    var crossReferences: [CrossRef]
    var originalLanguageWords: [OriginalWord]
    var keyThemes: [String]
}

struct CrossRef: Identifiable, Codable {
    var id: UUID
    var reference: String
    var snippet: String
}

struct OriginalWord: Identifiable, Codable {
    var id: UUID
    var english: String
    var original: String
    var language: String   // "Greek" or "Hebrew"
    var definition: String
}

// MARK: - Community Duet / Note Stitching

struct DuetBlock: Identifiable, Codable {
    var id: UUID
    var originalAuthor: String
    var originalNote: String
    var scriptureRef: String
    var stitchedAt: Date
}

// MARK: - Church Radar

struct LiveChurch: Identifiable, Codable {
    var id: UUID
    var name: String
    var pastorName: String
    var distanceMiles: Double
    var isLive: Bool
    var sermonTitle: String
    var latitude: Double
    var longitude: Double
}

// MARK: - Growth Arc

struct GrowthDataPoint: Identifiable, Codable {
    var id: UUID
    var weekNumber: Int
    var noteCount: Int
    var date: Date
    var topTheme: String
}

// MARK: - Community Notes

struct CommunityNote: Identifiable, Codable {
    var id: UUID
    var authorName: String
    var authorInitials: String
    var avatarColorHex: String
    var noteSnippet: String
    var scriptureRef: String
    var churchName: String
    var likeCount: Int
    var postedAt: Date
}

// MARK: - Quote Forge / Reel Styles
// CNReelStyle is not Codable because Color is not Codable.
struct CNReelStyle: Identifiable {
    var id: UUID = UUID()
    var name: String
    var gradientColors: [Color]
    var emoji: String
    var fontName: String
}
