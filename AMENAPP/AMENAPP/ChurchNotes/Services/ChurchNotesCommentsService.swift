import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ChurchNotesCommentsService: ObservableObject {
    @Published private(set) var comments: [ChurchNoteCommentThread] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    var currentUid: String? { Auth.auth().currentUser?.uid }

    /// Total number of comment threads on the note. Updated live by the same
    /// Firestore snapshot listener that powers `comments` — adds, resolves, and
    /// deletes all propagate without a manual refresh.
    var totalCount: Int { comments.count }

    /// Number of open (non-resolved) comment threads. The header badge uses
    /// this so users see at a glance how much active conversation a note has.
    var openCount: Int { comments.lazy.filter { !$0.resolved }.count }

    func start(noteId: String) {
        stop()
        isLoading = true
        errorMessage = nil
        listener = db.collection("churchNotes")
            .document(noteId)
            .collection("comments")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.comments = snapshot?.documents.compactMap { document in
                        ChurchNoteCommentThread(documentID: document.documentID, data: document.data())
                    } ?? []
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func addComment(noteId: String, anchorText: String, anchorStart: Int?, anchorEnd: Int?, body: String) async {
        guard let uid = currentUid else {
            errorMessage = "Sign in to comment."
            return
        }
        await writeComment(
            noteId: noteId,
            parentCommentId: nil,
            anchorText: anchorText,
            anchorStart: anchorStart,
            anchorEnd: anchorEnd,
            body: body,
            authorUid: uid
        )
    }

    func reply(noteId: String, parentCommentId: String, body: String) async {
        guard let uid = currentUid else {
            errorMessage = "Sign in to reply."
            return
        }
        await writeComment(
            noteId: noteId,
            parentCommentId: parentCommentId,
            anchorText: "",
            anchorStart: nil,
            anchorEnd: nil,
            body: body,
            authorUid: uid
        )
    }

    func setResolved(noteId: String, commentId: String, resolved: Bool) async {
        errorMessage = nil
        do {
            try await db.collection("churchNotes")
                .document(noteId)
                .collection("comments")
                .document(commentId)
                .updateData([
                    "resolved": resolved,
                    "updatedAt": FieldValue.serverTimestamp(),
                ])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteOwnComment(noteId: String, commentId: String) async {
        errorMessage = nil
        do {
            try await db.collection("churchNotes")
                .document(noteId)
                .collection("comments")
                .document(commentId)
                .delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func writeComment(
        noteId: String,
        parentCommentId: String?,
        anchorText: String,
        anchorStart: Int?,
        anchorEnd: Int?,
        body: String,
        authorUid: String
    ) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        let ref = db.collection("churchNotes")
            .document(noteId)
            .collection("comments")
            .document()
        var data: [String: Any] = [
            "id": ref.documentID,
            "noteId": noteId,
            "anchorText": anchorText,
            "body": trimmed,
            "authorUid": authorUid,
            "authorName": Auth.auth().currentUser?.displayName ?? "Someone",
            "resolved": false,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let anchorStart { data["anchorStart"] = anchorStart }
        if let anchorEnd { data["anchorEnd"] = anchorEnd }
        if let parentCommentId { data["parentCommentId"] = parentCommentId }

        do {
            try await ref.setData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ChurchNoteCommentThread: Identifiable, Equatable {
    let id: String
    let noteId: String
    let anchorText: String
    let body: String
    let authorUid: String
    let authorName: String
    let parentCommentId: String?
    let resolved: Bool

    init(documentID: String, data: [String: Any]) {
        id = (data["id"] as? String) ?? documentID
        noteId = (data["noteId"] as? String) ?? ""
        anchorText = (data["anchorText"] as? String) ?? ""
        body = (data["body"] as? String) ?? ""
        authorUid = (data["authorUid"] as? String) ?? ""
        authorName = (data["authorName"] as? String) ?? "Someone"
        parentCommentId = data["parentCommentId"] as? String
        resolved = (data["resolved"] as? Bool) ?? false
    }

    var isReply: Bool { parentCommentId != nil }
}
