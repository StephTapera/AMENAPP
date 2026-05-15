import Foundation
import FirebaseFirestore

/// A first-class action item that has passed AI-draft review.
/// Stored at `churchNotes/{noteId}/actionItems/{id}` and only mutable via
/// the `setChurchNoteActionItemCompletion` callable (completion fields)
/// or owner-only delete. The text + provenance fields are server-owned.
struct ChurchNoteActionItem: Identifiable, Equatable {
    let id: String
    let noteId: String
    let text: String
    let originalText: String?
    let wasEdited: Bool
    let sourceJobId: String?
    let approvedBy: String?
    let approvedAt: Date?
    let completed: Bool
    let completedBy: String?
    let completedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    init(
        id: String,
        noteId: String,
        text: String,
        originalText: String? = nil,
        wasEdited: Bool = false,
        sourceJobId: String? = nil,
        approvedBy: String? = nil,
        approvedAt: Date? = nil,
        completed: Bool = false,
        completedBy: String? = nil,
        completedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.noteId = noteId
        self.text = text
        self.originalText = originalText
        self.wasEdited = wasEdited
        self.sourceJobId = sourceJobId
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.completed = completed
        self.completedBy = completedBy
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func fromFirestore(id: String, data: [String: Any]) -> ChurchNoteActionItem? {
        guard let noteId = data["noteId"] as? String,
              let text   = data["text"]   as? String else { return nil }
        return ChurchNoteActionItem(
            id: id,
            noteId: noteId,
            text: text,
            originalText: data["originalText"] as? String,
            wasEdited:    (data["wasEdited"]   as? Bool) ?? false,
            sourceJobId:  data["sourceJobId"]  as? String,
            approvedBy:   data["approvedBy"]   as? String,
            approvedAt:   (data["approvedAt"]  as? Timestamp)?.dateValue(),
            completed:    (data["completed"]   as? Bool) ?? false,
            completedBy:  data["completedBy"]  as? String,
            completedAt:  (data["completedAt"] as? Timestamp)?.dateValue(),
            createdAt:    (data["createdAt"]   as? Timestamp)?.dateValue(),
            updatedAt:    (data["updatedAt"]   as? Timestamp)?.dateValue()
        )
    }
}

/// An item the user has approved (potentially edited) but not yet persisted.
struct ChurchNoteActionItemApproval: Equatable {
    let text: String
    /// Index into the original `actionItemsDraft` array on the job document — used
    /// for audit so the server knows whether the user edited the suggested text.
    let originalIndex: Int?
}
