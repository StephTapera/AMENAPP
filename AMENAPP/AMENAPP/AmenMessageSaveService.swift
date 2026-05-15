// AmenMessageSaveService.swift
// AMENAPP
//
// Stateless async helpers for the messaging intelligence cross-surface save sheet.
// All writes use the caller's authenticated UID and target the user's own data paths only.
// Private DM message text is NEVER written to shared or public collections.
//
// Church notes → churchNotes/{auto-id}  (same format as ChurchNotesService.createNote)
// Selah        → users/{uid}/selahSessions/{auto-id}  (via SelahService.shared)

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum AmenSaveError: LocalizedError {
    case notAuthenticated
    case emptyMessage

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to save."
        case .emptyMessage:     return "Cannot save an empty message."
        }
    }
}

@MainActor
struct AmenMessageSaveService {

    // MARK: — Church Notes

    /// Creates a minimal V1 ChurchNote in the user's private churchNotes collection.
    /// Matches the Firestore document format written by ChurchNotesService.createNote().
    /// permission is always "private" — message text never reaches any shared path.
    static func saveToChurchNotes(
        message: AppMessage,
        conversationName: String
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AmenSaveError.notAuthenticated
        }
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AmenSaveError.emptyMessage
        }
        let db = Firestore.firestore()
        let ref = db.collection("churchNotes").document()
        let now = Timestamp(date: Date())
        let senderLabel: String = {
            if let n = message.senderName, !n.isEmpty { return n }
            return conversationName.isEmpty ? "" : conversationName
        }()
        let title = senderLabel.isEmpty
            ? String(message.text.prefix(60))
            : "Message from \(senderLabel)"
        let data: [String: Any] = [
            "userId":              uid,
            "title":               title,
            "content":             message.text,
            "date":                Timestamp(date: message.timestamp),
            "createdAt":           now,
            "updatedAt":           now,
            "tags":                ["saved_message"],
            "keyPoints":           [String](),
            "isFavorite":          false,
            "version":             1,
            "permission":          "private",
            "sharedWith":          [String](),
            "scriptureReferences": [String](),
            "checklists":          [Any](),
            "blocks":              [Any](),
            "formattingRanges":    [Any](),
            "worshipSongs":        [Any](),
            "claudeTags":          [String](),
            "linkedNoteIds":       [String](),
            "attachmentCount":     0,
            "hasTranscript":       false,
            "shouldRevisit":       false
        ]
        try await ref.setData(data)
    }

    // MARK: — Selah

    /// Saves a DM message as a Selah session in the user's private selahSessions collection.
    /// The message text is the session query; no AI generation is invoked.
    /// Scripture references are detected locally via BereanStudyNotesService.
    @discardableResult
    static func saveToSelah(
        message: AppMessage,
        conversationName: String
    ) async throws -> String {
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AmenSaveError.emptyMessage
        }
        let senderLabel: String = {
            if let n = message.senderName, !n.isEmpty { return n }
            return conversationName.isEmpty ? "" : conversationName
        }()
        let title = senderLabel.isEmpty
            ? String(message.text.prefix(60))
            : "Message from \(senderLabel)"
        let scriptureRefs: [String] = BereanStudyNotesService
            .detectVerseReference(in: message.text)
            .map { [$0] } ?? []
        return try await SelahService.shared.saveSession(
            title: title,
            query: message.text,
            responsePreview: String(message.text.prefix(500)),
            format: .tldr,
            scriptureRefs: scriptureRefs,
            tags: ["saved_message"]
        )
    }
}
