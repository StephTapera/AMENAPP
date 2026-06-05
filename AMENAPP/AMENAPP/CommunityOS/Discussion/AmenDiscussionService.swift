// AmenDiscussionService.swift
// AMEN App — Community OS / Discussion OS (A6) Phase 2
//
// Full Firestore-backed service for AmenDiscussionRoom and DiscussionMessage.
//
// Firestore layout:
//   /amenDiscussionRooms/{roomId}                  — AmenDiscussionRoom document
//   /amenDiscussionRooms/{roomId}/messages/{msgId} — DiscussionMessage documents
//
// Rules:
//   - async/await, @MainActor
//   - Soft-delete only — `isDeleted: true`; documents are never hard-deleted
//   - Provenance is always preserved on reshares — never stripped
//   - When participationControl == .moderated, new messages are written with
//     isModerated: true (held for review queue)
//   - No public participant counts or message counts surfaced in UI
//   - trustedCircle membership enforced server-side by Firestore rules (C5)

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - AmenDiscussionServiceError

enum AmenDiscussionServiceError: LocalizedError {
    case notAuthenticated
    case roomNotFound
    case messageNotFound
    case writeFailure(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to participate in discussions."
        case .roomNotFound:
            return "Discussion room not found."
        case .messageNotFound:
            return "Message not found."
        case .writeFailure(let detail):
            return "Couldn't complete the action: \(detail)"
        }
    }
}

// MARK: - AmenDiscussionService

/// @MainActor service for the Discussion OS.
/// Owns all Firestore reads and writes for AmenDiscussionRoom and DiscussionMessage.
///
/// Usage:
/// ```swift
/// @StateObject var service = AmenDiscussionService()
/// ```
@MainActor
final class AmenDiscussionService: ObservableObject {

    // MARK: - Published state

    /// Rooms loaded for the current context (church, event, space, or global public)
    @Published var rooms: [AmenDiscussionRoom] = []
    /// Messages loaded for the currently-open room
    @Published var messages: [DiscussionMessage] = []
    /// True while a load or write operation is in flight
    @Published var isLoading: Bool = false
    /// Non-nil when the last operation produced an error
    @Published var errorMessage: String?

    // MARK: - Private

    private let db = Firestore.firestore()
    private var messageListener: ListenerRegistration?

    /// Authenticated current user UID. Throws if not signed in.
    private var currentUID: String {
        get throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw AmenDiscussionServiceError.notAuthenticated
            }
            return uid
        }
    }

    // MARK: - Collection helpers

    private var roomsCollection: CollectionReference {
        db.collection("amenDiscussionRooms")
    }

    private func messagesCollection(roomId: String) -> CollectionReference {
        roomsCollection.document(roomId).collection("messages")
    }

    // MARK: - deinit

    deinit {
        messageListener?.remove()
    }

    // MARK: - createRoom

    /// Creates a new AmenDiscussionRoom in Firestore.
    ///
    /// - Parameters:
    ///   - title: Human-readable room title.
    ///   - type: Functional type (7 options).
    ///   - privacy: Who can read/join.
    ///   - participation: How messages enter the room.
    ///   - sourceRef: Optional Firestore path of the parent object (e.g. "/posts/abc").
    ///   - sourceContextType: Optional AmenObjectType raw value of the parent.
    ///   - provenance: SpawnProvenance block. Pass nil for root-created rooms.
    ///   - creatorId: Firebase Auth UID of the creating user.
    /// - Returns: The new Firestore document ID.
    func createRoom(
        title: String,
        type: AmenDiscussionRoomType,
        privacy: AmenDiscussionPrivacyLevel,
        participation: AmenDiscussionParticipationControl,
        sourceRef: String?,
        sourceContextType: String?,
        provenance: SpawnProvenance?,
        creatorId: String
    ) async throws -> String {
        let docRef = roomsCollection.document()
        let now = FieldValue.serverTimestamp()

        var payload: [String: Any] = [
            "id":                   docRef.documentID,
            "title":                title,
            "description":          "",
            "type":                 type.rawValue,
            "privacyLevel":         privacy.rawValue,
            "participationControl": participation.rawValue,
            "participantIds":       [creatorId],
            "messageCount":         0,
            "followUpPrompts":      [String](),
            "moderatorIds":         [creatorId],
            "createdBy":            creatorId,
            "createdAt":            now,
            "updatedAt":            now,
            "isDeleted":            false,
            "isPinned":             false
        ]

        if let ref = sourceRef {
            payload["sourceContextRef"] = ref
        }
        if let ctxType = sourceContextType {
            payload["sourceContextType"] = ctxType
        }
        if let prov = provenance {
            payload["provenance"] = [
                "sourceType":    prov.sourceType,
                "sourceRef":     prov.sourceRef as Any,
                "sourceOwnerId": prov.sourceOwnerId as Any,
                "intent":        prov.intent,
                "createdAt":     now
            ]
        }

        try await docRef.setData(payload)
        return docRef.documentID
    }

    // MARK: - loadRooms

    /// Loads rooms for the given context ref (church, event, space, or nil = all public).
    ///
    /// Filters: `isDeleted == false`.
    /// Sort: `lastMessageAt` descending, then `createdAt` descending.
    /// Limit: 50.
    ///
    /// When `contextRef` is nil, loads all public rooms ordered by recent activity.
    func loadRooms(forContextRef contextRef: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        var query: Query = roomsCollection
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 50)

        if let ref = contextRef {
            query = query.whereField("sourceContextRef", isEqualTo: ref)
        } else {
            // Global public discovery — only public-privacy rooms
            query = query.whereField("privacyLevel", isEqualTo: AmenDiscussionPrivacyLevel.public.rawValue)
        }

        // Firestore requires a composite index for multi-field order when combined
        // with a whereField. Fall back to createdAt desc if lastMessageAt index is missing.
        let snap: QuerySnapshot
        do {
            snap = try await query
                .order(by: "lastMessageAt", descending: true)
                .getDocuments()
        } catch {
            // Index not yet created; fall back to createdAt ordering
            snap = try await query
                .order(by: "createdAt", descending: true)
                .getDocuments()
        }

        rooms = snap.documents.compactMap { doc -> AmenDiscussionRoom? in
            try? doc.data(as: AmenDiscussionRoom.self)
        }
    }

    // MARK: - loadMessages

    /// Paginates messages for a room, ordered by `createdAt` ascending.
    ///
    /// - Parameters:
    ///   - roomId: The room document ID.
    ///   - limit: Page size (default 50).
    ///   - before: When non-nil, loads messages created before this date (pagination cursor).
    func loadMessages(
        roomId: String,
        limit: Int = 50,
        before: Date? = nil
    ) async throws {
        isLoading = true
        defer { isLoading = false }

        var query: Query = messagesCollection(roomId: roomId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: false)
            .limit(to: limit)

        if let cursor = before {
            query = query.end(before: [Timestamp(date: cursor)])
        }

        let snap = try await query.getDocuments()
        let loaded: [DiscussionMessage] = snap.documents.compactMap { doc in
            try? doc.data(as: DiscussionMessage.self)
        }

        if before != nil {
            // Prepend older messages before the existing page
            messages = loaded + messages
        } else {
            messages = loaded
        }
    }

    // MARK: - listenMessages (live listener)

    /// Attaches a real-time Firestore listener for messages in the given room.
    /// Updates `self.messages` on every snapshot. Call `stopListening()` on disappear.
    func startListening(roomId: String) {
        messageListener?.remove()
        messageListener = messagesCollection(roomId: roomId)
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: false)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snap = snapshot else { return }
                Task { @MainActor in
                    self.messages = snap.documents.compactMap { doc in
                        try? doc.data(as: DiscussionMessage.self)
                    }
                }
            }
    }

    /// Removes the active real-time listener.
    func stopListening() {
        messageListener?.remove()
        messageListener = nil
    }

    // MARK: - postMessage

    /// Posts a new message to a room.
    ///
    /// Moderation gate: if `participationControl == .moderated`, sets `isModerated: true`
    /// so the message enters the review queue before becoming visible to others.
    ///
    /// - Parameters:
    ///   - roomId: The room document ID.
    ///   - body: Message text (max 2 000 chars; server validates).
    ///   - authorId: Firebase Auth UID of the poster.
    ///   - parentMessageId: When non-nil, this is a threaded reply.
    ///   - provenance: Optional provenance for messages citing/spawned-from another object.
    /// - Returns: The new message document ID.
    @discardableResult
    func postMessage(
        to roomId: String,
        body: String,
        authorId: String,
        parentMessageId: String? = nil,
        provenance: SpawnProvenance? = nil
    ) async throws -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AmenDiscussionServiceError.writeFailure("Message body cannot be empty.")
        }

        // Fetch room to determine participation control
        let roomSnap = try await roomsCollection.document(roomId).getDocument()
        guard roomSnap.exists else { throw AmenDiscussionServiceError.roomNotFound }

        let participationRaw = roomSnap.data()?["participationControl"] as? String ?? "open"
        let isModerated = participationRaw == AmenDiscussionParticipationControl.moderated.rawValue
            || participationRaw == AmenDiscussionParticipationControl.curated.rawValue

        let msgRef = messagesCollection(roomId: roomId).document()
        let now = FieldValue.serverTimestamp()

        var msgPayload: [String: Any] = [
            "id":              msgRef.documentID,
            "discussionId":    roomId,
            "authorId":        authorId,
            "body":            trimmed,
            "replyCount":      0,
            "isModerated":     isModerated,
            "isDeleted":       false,
            "attachmentRefs":  [String](),
            "createdAt":       now,
            "updatedAt":       now
        ]

        if let parentId = parentMessageId {
            msgPayload["parentMessageId"] = parentId
        }

        if let prov = provenance {
            msgPayload["provenance"] = [
                "sourceType":    prov.sourceType,
                "sourceRef":     prov.sourceRef as Any,
                "sourceOwnerId": prov.sourceOwnerId as Any,
                "intent":        prov.intent,
                "createdAt":     now
            ]
        }

        // Batch: write message + update room denorm fields atomically
        let batch = db.batch()
        batch.setData(msgPayload, forDocument: msgRef)
        batch.updateData(
            [
                "messageCount":  FieldValue.increment(Int64(1)),
                "lastMessageAt": now,
                "updatedAt":     now
            ],
            forDocument: roomsCollection.document(roomId)
        )

        // If this is a reply, increment parent's replyCount
        if let parentId = parentMessageId {
            let parentRef = messagesCollection(roomId: roomId).document(parentId)
            batch.updateData(
                ["replyCount": FieldValue.increment(Int64(1)), "updatedAt": now],
                forDocument: parentRef
            )
        }

        try await batch.commit()
        return msgRef.documentID
    }

    // MARK: - deleteMessage

    /// Soft-deletes a message (moderator action).
    /// Sets `isDeleted: true` and records a moderation note on the document.
    ///
    /// - Parameters:
    ///   - messageId: The message document ID.
    ///   - roomId: The parent room document ID.
    ///   - moderatorId: UID of the acting moderator (for audit trail).
    func deleteMessage(
        messageId: String,
        roomId: String,
        moderatorId: String
    ) async throws {
        let ref = messagesCollection(roomId: roomId).document(messageId)
        try await ref.updateData([
            "isDeleted":      true,
            "moderationNote": "Removed by moderator \(moderatorId).",
            "updatedAt":      FieldValue.serverTimestamp()
        ])
        // Decrement room messageCount
        try? await roomsCollection.document(roomId).updateData([
            "messageCount": FieldValue.increment(Int64(-1)),
            "updatedAt":    FieldValue.serverTimestamp()
        ])
    }

    // MARK: - moderateMessage

    /// Sets or clears the moderation flag on a message.
    ///
    /// - Parameters:
    ///   - messageId: The message document ID.
    ///   - roomId: The parent room document ID.
    ///   - isModerated: `true` to hold for review; `false` to approve.
    ///   - note: Optional explanation shown to the author.
    ///   - moderatorId: UID of the acting moderator.
    func moderateMessage(
        messageId: String,
        roomId: String,
        isModerated: Bool,
        note: String?,
        moderatorId: String
    ) async throws {
        var update: [String: Any] = [
            "isModerated": isModerated,
            "updatedAt":   FieldValue.serverTimestamp()
        ]
        if let note = note {
            update["moderationNote"] = note
        } else {
            update["moderationNote"] = FieldValue.delete()
        }
        let ref = messagesCollection(roomId: roomId).document(messageId)
        try await ref.updateData(update)
    }

    // MARK: - addFollowUpPrompt

    /// Appends a Berean-generated (or host-written) follow-up prompt to the room.
    ///
    /// - Parameters:
    ///   - prompt: The suggestion text.
    ///   - roomId: The room document ID.
    func addFollowUpPrompt(_ prompt: String, to roomId: String) async throws {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await roomsCollection.document(roomId).updateData([
            "followUpPrompts": FieldValue.arrayUnion([trimmed]),
            "updatedAt":       FieldValue.serverTimestamp()
        ])
    }

    // MARK: - reshare

    /// Spawns a new AmenDiscussionRoom from an existing room, preserving provenance.
    ///
    /// The new room's provenance records the source roomId, intent, and the actor.
    /// Provenance is NEVER stripped — the chain from original object is maintained.
    ///
    /// - Parameters:
    ///   - roomId: The source room document ID.
    ///   - intent: AmenIntent raw value for the spawn (e.g. "discuss", "share").
    ///   - actorId: Firebase Auth UID of the resharing user.
    /// - Returns: The new room document ID.
    @discardableResult
    func reshare(roomId: String, intent: String, actorId: String) async throws -> String {
        // Load source room
        let sourceSnap = try await roomsCollection.document(roomId).getDocument()
        guard
            sourceSnap.exists,
            let sourceRoom = try? sourceSnap.data(as: AmenDiscussionRoom.self)
        else {
            throw AmenDiscussionServiceError.roomNotFound
        }

        // Build new provenance preserving the full lineage
        let newProvenance = SpawnProvenance(
            sourceType:    "discussion",
            sourceRef:     "/amenDiscussionRooms/\(roomId)",
            sourceOwnerId: sourceRoom.createdBy,
            intent:        intent,
            createdAt:     Date() // will be overwritten by serverTimestamp in write
        )

        return try await createRoom(
            title:              "Re: \(sourceRoom.title)",
            type:               sourceRoom.type,
            privacy:            sourceRoom.privacyLevel,
            participation:      sourceRoom.participationControl,
            sourceRef:          "/amenDiscussionRooms/\(roomId)",
            sourceContextType:  "discussion",
            provenance:         newProvenance,
            creatorId:          actorId
        )
    }

    // MARK: - updateSummary (Berean integration hook)

    /// Updates the AI-generated summary on a room.
    /// Called by the Berean Cloud Function trigger — not by the iOS client directly.
    /// Exposed here for completeness and test-stub purposes.
    func updateSummary(_ summary: String, for roomId: String) async throws {
        try await roomsCollection.document(roomId).updateData([
            "summaryText": summary,
            "updatedAt":   FieldValue.serverTimestamp()
        ])
    }
}
