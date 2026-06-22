// ChurchReflectionService.swift
// AMENAPP
//
// Orchestrates the creation of templated church notes and links them
// to the church interaction lifecycle.

import Foundation
import FirebaseAuth

@MainActor
final class ChurchReflectionService {

    static let shared = ChurchReflectionService()

    private let notesService = ChurchNotesService()

    private init() {}

    // MARK: - Create Note from Template

    /// Creates a new church note from a template and links it to the church interaction.
    /// Returns the created note (with Firestore ID populated by the listener).
    @discardableResult
    func createNoteFromTemplate(
        template: ChurchVisitNoteTemplate,
        churchId: String?,
        churchName: String?,
        visitPlanId: String? = nil
    ) async throws -> ChurchNote {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw ChurchReflectionError.notAuthenticated
        }

        let note = template.createNote(
            userId: userId,
            churchId: churchId,
            churchName: churchName,
            visitPlanId: visitPlanId
        )

        try await notesService.createNote(note)

        // Link the note to the church interaction
        if let churchId, let noteId = note.id {
            linkNoteToInteraction(noteId: noteId, churchId: churchId)
        }

        return note
    }

    // MARK: - Link Reflection to Interaction

    /// Links an existing note to a church interaction.
    func linkNoteToInteraction(noteId: String, churchId: String) {
        ChurchInteractionService.shared.linkNote(
            churchId: churchId,
            noteId: noteId
        )
    }

    // MARK: - Query Church Notes

    /// Fetches all notes the current user has written for a specific church.
    func getChurchNotes(churchId: String) async throws -> [ChurchNote] {
        try await notesService.notesForChurch(churchId: churchId)
    }

    /// Fetches the note linked to a specific visit plan.
    func getNoteForVisitPlan(visitPlanId: String) async throws -> ChurchNote? {
        try await notesService.noteForVisitPlan(visitPlanId: visitPlanId)
    }
}

// MARK: - Errors

enum ChurchReflectionError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to create a note."
        }
    }
}
