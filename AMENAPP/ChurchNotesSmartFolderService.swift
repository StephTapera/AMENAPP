//
//  ChurchNotesSmartFolderService.swift
//  AMENAPP
//
//  Feature 5: Tags + Smart Folders
//  Provides smart folder filtering logic and AI-powered tag generation.
//  Claude generates spiritual theme tags and merges them into note.claudeTags.
//

import Foundation
import FirebaseAuth

// MARK: - Smart Folder Enum

enum SmartFolder: String, CaseIterable, Identifiable {
    case thisWeek          = "This Week"
    case unfinishedActions = "Unfinished Actions"
    case prayerBased       = "Prayer Based"
    case hasAudio          = "Has Audio"
    case holidayNotes      = "Holiday Notes"
    case sharedToFeed      = "Shared to Feed"
    case firstTimeVisits   = "First Time Visits"
    case favorites         = "Favorites"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .thisWeek:          return "calendar.circle.fill"
        case .unfinishedActions: return "checklist.unchecked"
        case .prayerBased:       return "hands.sparkles.fill"
        case .hasAudio:          return "mic.fill"
        case .holidayNotes:      return "sparkles"
        case .sharedToFeed:      return "globe"
        case .firstTimeVisits:   return "door.left.hand.open"
        case .favorites:         return "star.fill"
        }
    }

    var description: String {
        switch self {
        case .thisWeek:          return "Notes from the past 7 days"
        case .unfinishedActions: return "Notes with incomplete action items"
        case .prayerBased:       return "Notes tagged with prayer content"
        case .hasAudio:          return "Notes with sermon recordings"
        case .holidayNotes:      return "Notes near major Christian holidays"
        case .sharedToFeed:      return "Notes shared to the community feed"
        case .firstTimeVisits:   return "Notes tagged as first visit"
        case .favorites:         return "Your starred notes"
        }
    }
}

// MARK: - Smart Folder Service

@MainActor
final class SmartFolderService: ObservableObject {
    static let shared = SmartFolderService()
    private init() {}

    // MARK: - Primary Filter Method

    /// Returns notes that match the given smart folder criteria.
    func notes(for folder: SmartFolder, from notes: [ChurchNote]) -> [ChurchNote] {
        switch folder {
        case .thisWeek:
            return notesThisWeek(notes)

        case .unfinishedActions:
            return notesWithUnfinishedActions(notes)

        case .prayerBased:
            return notesPrayerBased(notes)

        case .hasAudio:
            return notesWithAudio(notes)

        case .holidayNotes:
            return notesNearHolidays(notes)

        case .sharedToFeed:
            return notesSharedToFeed(notes)

        case .firstTimeVisits:
            return notesFirstTimeVisits(notes)

        case .favorites:
            return notes.filter { $0.isFavorite }
        }
    }

    // MARK: - Folder Implementations

    private func notesThisWeek(_ notes: [ChurchNote]) -> [ChurchNote] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return notes.filter { $0.date >= cutoff }
    }

    private func notesWithUnfinishedActions(_ notes: [ChurchNote]) -> [ChurchNote] {
        // Notes that have action-type tags or keyPoints with action language
        let actionKeywords = ["action", "do", "apply", "follow", "pray about",
                              "memorize", "ask", "complete", "finish", "this week"]
        return notes.filter { note in
            let combined = (note.tags + note.claudeTags + note.keyPoints)
                .map { $0.lowercased() }
                .joined(separator: " ")
            return actionKeywords.contains(where: { combined.contains($0) })
        }
    }

    private func notesPrayerBased(_ notes: [ChurchNote]) -> [ChurchNote] {
        let prayerKeywords = ["prayer", "pray", "intercession", "petition",
                              "supplication", "devotion"]
        return notes.filter { note in
            let allText = [
                note.title, note.content,
                note.tags.joined(separator: " "),
                note.claudeTags.joined(separator: " ")
            ].joined(separator: " ").lowercased()
            return prayerKeywords.contains(where: { allText.contains($0) })
        }
    }

    private func notesWithAudio(_ notes: [ChurchNote]) -> [ChurchNote] {
        return notes.filter { $0.hasTranscript || $0.audioRecordingURL != nil }
    }

    private func notesNearHolidays(_ notes: [ChurchNote]) -> [ChurchNote] {
        let service = ChurchNotesAIService.shared
        return notes.filter { note in
            service.generateHolidayTheme(for: note.date) != nil
        }
    }

    private func notesSharedToFeed(_ notes: [ChurchNote]) -> [ChurchNote] {
        return notes.filter { $0.permission == .publicNote || $0.permission == .shared }
    }

    private func notesFirstTimeVisits(_ notes: [ChurchNote]) -> [ChurchNote] {
        let visitKeywords = ["first time", "first visit", "new church", "visited",
                             "guest", "first sunday"]
        return notes.filter { note in
            let allText = [note.title, note.content,
                           note.tags.joined(separator: " ")]
                .joined(separator: " ").lowercased()
            return visitKeywords.contains(where: { allText.contains($0) })
        }
    }

    // MARK: - Folder Counts

    /// Returns the count for each folder, useful for badges.
    func folderCounts(from notes: [ChurchNote]) -> [SmartFolder: Int] {
        var counts: [SmartFolder: Int] = [:]
        for folder in SmartFolder.allCases {
            counts[folder] = self.notes(for: folder, from: notes).count
        }
        return counts
    }
}

// MARK: - AI Tag Generation Extension

extension ChurchNotesAIService {
    /// Generates spiritual theme tags for a note via Claude.
    /// Returns an array of short tag strings to merge into note.claudeTags.
    func generateTags(for note: ChurchNote) async throws -> [String] {
        let prompt = """
        Analyse these sermon notes and return 4-7 short spiritual theme tags (2-3 words max each).
        Return only the tags, one per line, no bullets or numbering. Focus on spiritual themes,
        not generic words.

        Title: \(note.title)
        Content: \(note.content.prefix(600))
        """

        var result = ""
        for try await chunk in ClaudeService.shared.sendMessage(prompt) {
            result += chunk
        }

        let tags = result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 40 }
            .map { $0.lowercased() }

        return Array(Set(tags)).sorted()
    }
}
