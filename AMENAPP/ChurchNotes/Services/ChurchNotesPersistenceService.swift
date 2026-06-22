import Foundation
import FirebaseAuth

@MainActor
final class ChurchNotesPersistenceService {
    private let notesService: ChurchNotesService
    private let formatter = AttributedStringFormatter()

    init(notesService: ChurchNotesService) {
        self.notesService = notesService
    }

    func buildNote(
        from base: ChurchNote?,
        title: String,
        sermonTitle: String,
        metadata: ChurchNoteMetadata,
        content: String,
        attributedText: NSAttributedString,
        blocks: [ChurchNoteBlock],
        tags: [String],
        scriptureReferences: [String],
        worshipSongs: [WorshipSongReference],
        actionStep: String,
        prayer: String,
        revisitMidweek: Bool
    ) throws -> ChurchNote {
        let richDoc = formatter.encode(attributedString: attributedText)
        let richJSON = String(data: try JSONEncoder().encode(richDoc), encoding: .utf8)
        let currentUserId = base?.userId ?? FirebaseManager.shared.currentUser?.uid ?? ""

        var note = base ?? ChurchNote(userId: currentUserId, title: title, content: content)
        note.title = title
        note.sermonTitle = sermonTitle.isEmpty ? nil : sermonTitle
        note = metadata.applying(to: note)
        note.content = content
        note.richContentJSON = richJSON
        note.blocks = blocks
        note.tags = tags
        note.scriptureReferences = scriptureReferences
        note.worshipSongs = worshipSongs
        note.actionStepThisWeek = actionStep.isEmpty ? nil : actionStep
        note.prayerFromSermon = prayer.isEmpty ? nil : prayer
        note.shouldRevisit = revisitMidweek
        note.updatedAt = Date()
        return note
    }

    func save(note: ChurchNote) async throws {
        if note.id == nil {
            try await notesService.createNote(note)
        } else {
            try await notesService.updateNote(note)
        }
    }
}
