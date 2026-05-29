// CommunityNotesService.swift
// AMENAPP — Community Notes service layer
//
// Firestore reads + Cloud Function calls for Community Notes.
// async/await only — no Combine.
// Field names match the Firestore schema exactly:
//   visibility, moderationStatus, likeCount, createdAt, category

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class CommunityNotesService: ObservableObject {

    static let shared = CommunityNotesService()

    private let functions = Functions.functions()
    private let db = Firestore.firestore()

    private var notesCollection: CollectionReference {
        db.collection("communityNotes")
    }

    private init() {}

    // MARK: - Search (Cloud Function)

    /// Calls the `searchCommunityNotes` callable Cloud Function.
    /// Returns a ranked list of lightweight search results.
    func search(
        query: String,
        category: NoteCategory? = nil,
        scriptureKey: String? = nil,
        mode: String = "hybrid"
    ) async throws -> [CommunityNotesSearchResult] {
        var payload: [String: Any] = [
            "query": query,
            "mode": mode
        ]
        if let cat = category { payload["category"] = cat.rawValue }
        if let key = scriptureKey { payload["scriptureKey"] = key }

        let callable = functions.httpsCallable("searchCommunityNotes")
        let result = try await callable.call(payload)

        guard let data = result.data as? [[String: Any]] else {
            return []
        }

        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode([CommunityNotesSearchResult].self, from: jsonData)
    }

    // MARK: - Fetch Top Notes (Firestore)

    /// Fetches top public + approved notes, ordered by likeCount desc.
    /// Composite index required:
    ///   visibility ASC, moderationStatus ASC, likeCount DESC
    func fetchTopNotes(category: NoteCategory? = nil) async throws -> [CommunityNote] {
        var query: Query = notesCollection
            .whereField("visibility", isEqualTo: "public")
            .whereField("moderationStatus", isEqualTo: "approved")
            .order(by: "likeCount", descending: true)
            .limit(to: 20)

        if let cat = category {
            query = notesCollection
                .whereField("visibility", isEqualTo: "public")
                .whereField("moderationStatus", isEqualTo: "approved")
                .whereField("category", isEqualTo: cat.rawValue)
                .order(by: "likeCount", descending: true)
                .limit(to: 20)
        }

        let snapshot = try await query.getDocuments()
        return try snapshot.documents.compactMap { try decodeNote($0) }
    }

    // MARK: - Fetch Recent Notes (Firestore)

    /// Fetches the most recently published public + approved notes.
    /// Composite index required:
    ///   visibility ASC, moderationStatus ASC, createdAt DESC
    func fetchRecentNotes(category: NoteCategory? = nil) async throws -> [CommunityNote] {
        var query: Query = notesCollection
            .whereField("visibility", isEqualTo: "public")
            .whereField("moderationStatus", isEqualTo: "approved")
            .order(by: "createdAt", descending: true)
            .limit(to: 20)

        if let cat = category {
            query = notesCollection
                .whereField("visibility", isEqualTo: "public")
                .whereField("moderationStatus", isEqualTo: "approved")
                .whereField("category", isEqualTo: cat.rawValue)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
        }

        let snapshot = try await query.getDocuments()
        return try snapshot.documents.compactMap { try decodeNote($0) }
    }

    // MARK: - Publish Note (Firestore write)

    /// Creates a new note document in `communityNotes`.
    /// Client writes the user-editable fields; the Cloud Function fills in
    /// excerpt, scriptureRefs, vector embeddings, and moderationStatus.
    ///
    /// - Returns: the Firestore document ID of the new note.
    @discardableResult
    func publishNote(
        title: String,
        body: String,
        category: NoteCategory,
        tags: [String],
        visibility: NoteVisibility,
        sourceNoteId: String?
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw CommunityNotesError.notAuthenticated
        }

        let docRef = notesCollection.document()
        let now = Timestamp(date: Date())

        var data: [String: Any] = [
            "authorId":    user.uid,
            "authorName":  user.displayName ?? "Anonymous",
            "authorHandle": (user.displayName ?? user.uid).lowercased()
                                 .replacingOccurrences(of: " ", with: ""),
            "authorInitial": String((user.displayName ?? "A").prefix(1)).uppercased(),
            "authorColor": "#7243CC",   // default; server may enrich with profile color
            "title":       title,
            "body":        body,
            "category":    category.rawValue,
            "tags":        tags,
            "visibility":  visibility.rawValue,
            // Server-populated fields — intentionally empty on write:
            "excerpt":              "",
            "scriptureRefStrings":  [String](),
            "scriptureKeys":        [String](),
            "likeCount":     0,
            "commentCount":  0,
            "saveCount":     0,
            "moderationStatus": "pending",
            "createdAt":  now,
            "updatedAt":  now,
            "publishedAt": now
        ]

        if let srcId = sourceNoteId {
            data["sourceNoteId"] = srcId
        }

        try await docRef.setData(data)
        return docRef.documentID
    }

    // MARK: - State Checks

    func isLikedByCurrentUser(noteId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let doc = try await notesCollection.document(noteId)
            .collection("likes").document(uid).getDocument()
        return doc.exists
    }

    func isSaved(noteId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let doc = try await db.collection("users").document(uid)
            .collection("savedNotes").document(noteId).getDocument()
        return doc.exists
    }

    // MARK: - Toggle Like

    /// Atomically increments or decrements likeCount.
    /// Also writes/removes the user's like record in `communityNotes/{id}/likes/{uid}`.
    func toggleLike(noteId: String, isLiked: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw CommunityNotesError.notAuthenticated
        }

        let noteRef = notesCollection.document(noteId)
        let likeRef = noteRef.collection("likes").document(uid)

        let delta: Int64 = isLiked ? 1 : -1

        try await db.runTransaction { transaction, _ in
            transaction.updateData(
                ["likeCount": FieldValue.increment(delta)],
                forDocument: noteRef
            )
            if isLiked {
                transaction.setData(["likedAt": Timestamp(date: Date())], forDocument: likeRef)
            } else {
                transaction.deleteDocument(likeRef)
            }
            return nil
        }
    }

    // MARK: - Save / Unsave Note

    /// Saves a note to the current user's `savedNotes` sub-collection.
    func saveNote(_ note: CommunityNote) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw CommunityNotesError.notAuthenticated
        }

        let saveRef = db.collection("users").document(uid)
            .collection("savedNotes").document(note.id)

        try await saveRef.setData([
            "noteId":     note.id,
            "title":      note.title,
            "category":   note.category.rawValue,
            "savedAt":    Timestamp(date: Date())
        ])

        // Increment saveCount on the note document (best-effort, non-atomic here)
        try await notesCollection.document(note.id)
            .updateData(["saveCount": FieldValue.increment(Int64(1))])
    }

    /// Removes a note from the current user's `savedNotes` sub-collection.
    func unsaveNote(noteId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw CommunityNotesError.notAuthenticated
        }

        let saveRef = db.collection("users").document(uid)
            .collection("savedNotes").document(noteId)

        try await saveRef.delete()

        try await notesCollection.document(noteId)
            .updateData(["saveCount": FieldValue.increment(Int64(-1))])
    }

    // MARK: - Comments

    func fetchComments(for noteId: String) async throws -> [CommunityNoteComment] {
        let snapshot = try await notesCollection.document(noteId)
            .collection("comments")
            .whereField("moderationStatus", isEqualTo: "approved")
            .order(by: "createdAt", descending: false)
            .limit(to: 50)
            .getDocuments()

        return try snapshot.documents.compactMap { doc -> CommunityNoteComment? in
            guard doc.exists else { return nil }
            var data = doc.data()
            if let ts = data["createdAt"] as? Timestamp {
                data["createdAt"] = ts.dateValue().timeIntervalSince1970
            }
            data["id"] = doc.documentID
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(CommunityNoteComment.self, from: jsonData)
        }
    }

    func addComment(to noteId: String, text: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw CommunityNotesError.notAuthenticated
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 2_000 else { return }

        let now = Timestamp(date: Date())
        let data: [String: Any] = [
            "authorId":       user.uid,
            "authorName":     user.displayName ?? "AMEN Member",
            "authorInitial":  String((user.displayName ?? "A").prefix(1)).uppercased(),
            "authorColor":    "#7243CC",
            "text":           cleaned,
            "amenCount":      0,
            "moderationStatus": "approved",
            "createdAt":      now,
            "updatedAt":      now
        ]
        try await notesCollection.document(noteId).collection("comments").addDocument(data: data)

        // Best-effort counter bump
        try? await notesCollection.document(noteId)
            .updateData(["commentCount": FieldValue.increment(Int64(1))])
    }

    // MARK: - Follow

    /// Returns whether the current user follows `authorId`.
    func isFollowing(authorId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let doc = try? await db.collection("users").document(uid)
            .collection("following").document(authorId).getDocument()
        return doc?.exists ?? false
    }

    /// Toggles follow/unfollow for `authorId`.
    /// - Returns: `true` if now following, `false` if unfollowed.
    @discardableResult
    func toggleFollow(authorId: String) async throws -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, uid != authorId else {
            throw CommunityNotesError.notAuthenticated
        }

        let followingRef = db.collection("users").document(uid)
            .collection("following").document(authorId)
        let followerRef  = db.collection("users").document(authorId)
            .collection("followers").document(uid)

        let alreadyFollowing = (try? await followingRef.getDocument().exists) ?? false
        let batch = db.batch()

        if alreadyFollowing {
            batch.deleteDocument(followingRef)
            batch.deleteDocument(followerRef)
        } else {
            batch.setData(["createdAt": Timestamp(date: Date())], forDocument: followingRef)
            batch.setData(["createdAt": Timestamp(date: Date())], forDocument: followerRef)
        }

        try await batch.commit()
        return !alreadyFollowing
    }

    // MARK: - Private helpers

    private func decodeNote(_ document: DocumentSnapshot) throws -> CommunityNote? {
        guard document.exists, var data = document.data() else { return nil }

        // Firestore Timestamp → Date for the Codable decoder
        ["createdAt", "updatedAt", "publishedAt"].forEach { key in
            if let ts = data[key] as? Timestamp {
                data[key] = ts.dateValue().timeIntervalSince1970
            }
        }

        // Inject the document ID
        data["id"] = document.documentID

        // Remap visibility raw value (Firestore stores "public", Codable expects "public")
        // — direct passthrough; no mapping needed.

        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(CommunityNote.self, from: jsonData)
    }
}

// MARK: - CommunityNotesError

enum CommunityNotesError: LocalizedError {
    case notAuthenticated
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .decodingFailed(let detail):
            return "Failed to read note data: \(detail)"
        }
    }
}
