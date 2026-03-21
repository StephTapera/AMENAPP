//
//  BereanStudyNotesService.swift
//  AMENAPP
//
//  Local persistence for Berean AI study notes.
//  Uses UserDefaults to store [BereanStudyNote] keyed by verse reference.
//

import Combine
import Foundation

// MARK: - BereanStudyNote Model

struct BereanStudyNote: Codable, Identifiable {
    let id: UUID
    let verseReference: String   // e.g. "John 3:16" or "Romans 8:28"
    let noteText: String         // The AI response text saved as a note
    let timestamp: Date
    let messageId: String        // UUID string of the originating BereanMessage

    init(
        id: UUID = UUID(),
        verseReference: String,
        noteText: String,
        timestamp: Date = Date(),
        messageId: String
    ) {
        self.id = id
        self.verseReference = verseReference
        self.noteText = noteText
        self.timestamp = timestamp
        self.messageId = messageId
    }
}

// MARK: - BereanStudyNotesService

final class BereanStudyNotesService: ObservableObject {

    static let shared = BereanStudyNotesService()

    private let storageKey = "berean_study_notes_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published private(set) var notes: [BereanStudyNote] = []

    private init() {
        notes = loadNotes()
    }

    // MARK: - Public API

    /// Persist a new study note. If a note for the same reference already exists,
    /// it is replaced so there is one canonical note per reference.
    func saveNote(_ note: BereanStudyNote) {
        var current = loadNotes()
        // Replace existing note for same reference, or append
        if let index = current.firstIndex(where: {
            $0.verseReference.lowercased() == note.verseReference.lowercased()
        }) {
            current[index] = note
        } else {
            current.insert(note, at: 0)  // newest first
        }
        persist(current)
        DispatchQueue.main.async { self.notes = current }
    }

    /// Load all saved study notes from UserDefaults (sorted newest first).
    func loadNotes() -> [BereanStudyNote] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? decoder.decode([BereanStudyNote].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    /// Returns true if any saved note matches the given verse reference (case-insensitive).
    func hasNote(forReference ref: String) -> Bool {
        return loadNotes().contains {
            $0.verseReference.lowercased().contains(ref.lowercased()) ||
            ref.lowercased().contains($0.verseReference.lowercased())
        }
    }

    /// Retrieve the note for a specific verse reference, if it exists.
    func note(forReference ref: String) -> BereanStudyNote? {
        return loadNotes().first {
            $0.verseReference.lowercased().contains(ref.lowercased()) ||
            ref.lowercased().contains($0.verseReference.lowercased())
        }
    }

    /// Delete a specific note by ID.
    func deleteNote(id: UUID) {
        var current = loadNotes()
        current.removeAll { $0.id == id }
        persist(current)
        DispatchQueue.main.async { self.notes = current }
    }

    // MARK: - Private Helpers

    private func persist(_ notes: [BereanStudyNote]) {
        if let data = try? encoder.encode(notes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Bible Reference Detection Utility

extension BereanStudyNotesService {

    /// Heuristically detects the first Bible reference found in a block of text.
    /// Matches patterns like "John 3:16", "1 Corinthians 13:4-7", "Genesis 1", "Ps 23:1".
    static func detectVerseReference(in text: String) -> String? {
        // Common book name abbreviations + full names (covers the majority of references)
        let bookNames = [
            "Genesis", "Gen", "Exodus", "Ex", "Leviticus", "Lev", "Numbers", "Num",
            "Deuteronomy", "Deut", "Joshua", "Josh", "Judges", "Judg", "Ruth",
            "Samuel", "Sam", "Kings", "Chronicles", "Chr", "Ezra", "Nehemiah", "Neh",
            "Esther", "Job", "Psalms", "Psalm", "Ps", "Proverbs", "Prov", "Pro",
            "Ecclesiastes", "Ecc", "Song", "Isaiah", "Isa", "Jeremiah", "Jer",
            "Lamentations", "Lam", "Ezekiel", "Ezek", "Daniel", "Dan",
            "Hosea", "Hos", "Joel", "Amos", "Obadiah", "Obad", "Jonah",
            "Micah", "Mic", "Nahum", "Nah", "Habakkuk", "Hab", "Zephaniah", "Zeph",
            "Haggai", "Hag", "Zechariah", "Zech", "Malachi", "Mal",
            "Matthew", "Matt", "Mat", "Mark", "Luke", "John",
            "Acts", "Romans", "Rom",
            "Corinthians", "Cor", "Galatians", "Gal", "Ephesians", "Eph",
            "Philippians", "Phil", "Colossians", "Col",
            "Thessalonians", "Thess", "Timothy", "Tim", "Titus", "Tit",
            "Philemon", "Phlm", "Hebrews", "Heb", "James", "Jas",
            "Peter", "Pet", "Jude", "Revelation", "Rev"
        ]

        // Pattern: optional leading number (1, 2, 3), book name, optional chapter:verse
        // e.g. "1 Corinthians 13:4", "John 3:16", "Psalm 23", "2 Tim 3:16-17"
        let bookPattern = bookNames.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let fullPattern = "(?:1|2|3 )?\\b(?:\(bookPattern))\\b\\.? ?\\d+(?::\\d+(?:-\\d+)?)?"

        guard let regex = try? NSRegularExpression(pattern: fullPattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let matchRange = Range(match.range, in: text) {
            return String(text[matchRange]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Returns true if the text contains at least one detectable Bible reference.
    static func containsVerseReference(_ text: String) -> Bool {
        return detectVerseReference(in: text) != nil
    }
}
