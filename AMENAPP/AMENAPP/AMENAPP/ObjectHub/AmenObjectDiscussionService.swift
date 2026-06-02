import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Object Discussion Service
// Manages spawn/join, presence, and messaging for object-scoped discussion rooms.
// Firestore layout:
//   objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}
//   objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}/messages/{messageId}
//   objectDiscussionRooms/{canonicalObjectId}/rooms/{roomId}/presence/{uid}

@MainActor
final class AmenObjectDiscussionService {
    static let shared = AmenObjectDiscussionService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Collection References

    private func roomsCollection(objectId: String) -> CollectionReference {
        db.collection("objectDiscussionRooms").document(objectId).collection("rooms")
    }

    private func messagesCollection(objectId: String, roomId: String) -> CollectionReference {
        roomsCollection(objectId: objectId).document(roomId).collection("messages")
    }

    private func presenceCollection(objectId: String, roomId: String) -> CollectionReference {
        roomsCollection(objectId: objectId).document(roomId).collection("presence")
    }

    // MARK: - Fetch Rooms

    func fetchRooms(for objectId: String) async throws -> [ObjectDiscussionRoom] {
        let snap = try await roomsCollection(objectId: objectId)
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: ObjectDiscussionRoom.self) }
    }

    // MARK: - Get or Create Room (spawn/join)

    /// Returns the existing room for this object+type, or creates one.
    func getOrCreateRoom(
        objectId: String,
        objectTitle: String,
        type: ObjectDiscussionRoom.ObjectDiscussionRoomType
    ) async throws -> ObjectDiscussionRoom {
        // Try to find an existing room of this type
        let existing = try await roomsCollection(objectId: objectId)
            .whereField("roomType", isEqualTo: type.rawValue)
            .limit(to: 1)
            .getDocuments()

        if let doc = existing.documents.first,
           let room = try? doc.data(as: ObjectDiscussionRoom.self) {
            return room
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            throw DiscussionServiceError.notAuthenticated
        }

        let now = Timestamp(date: Date())
        let data: [String: Any] = [
            "canonicalObjectId":    objectId,
            "canonicalObjectTitle": objectTitle,
            "roomType":             type.rawValue,
            "participantCount":     0,
            "messageCount":         0,
            "createdBy":            uid,
            "createdAt":            now,
            "updatedAt":            now
        ]

        let ref = try await roomsCollection(objectId: objectId).addDocument(data: data)
        let doc  = try await ref.getDocument()
        guard let room = try? doc.data(as: ObjectDiscussionRoom.self) else {
            throw DiscussionServiceError.roomCreationFailed
        }
        return room
    }

    // MARK: - Presence

    func joinPresence(objectId: String, roomId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let displayName = Auth.auth().currentUser?.displayName ?? "Member"
        let data: [String: Any] = [
            "userId":      uid,
            "displayName": displayName,
            "joinedAt":    FieldValue.serverTimestamp()
        ]
        try? await presenceCollection(objectId: objectId, roomId: roomId)
            .document(uid)
            .setData(data)
    }

    func leavePresence(objectId: String, roomId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            try? await presenceCollection(objectId: objectId, roomId: roomId)
                .document(uid)
                .delete()
        }
    }

    func observePresence(
        objectId: String,
        roomId: String,
        onChange: @escaping ([DiscussionPresenceMember]) -> Void
    ) -> ListenerRegistration {
        presenceCollection(objectId: objectId, roomId: roomId)
            .addSnapshotListener { snapshot, _ in
                Task { @MainActor in
                    let members = snapshot?.documents
                        .compactMap { try? $0.data(as: DiscussionPresenceMember.self) } ?? []
                    onChange(members)
                }
            }
    }

    // MARK: - Messages

    func sendMessage(objectId: String, roomId: String, body: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw DiscussionServiceError.notAuthenticated
        }
        let displayName = Auth.auth().currentUser?.displayName ?? "Member"
        let avatarURL   = Auth.auth().currentUser?.photoURL?.absoluteString as Any

        let msgData: [String: Any] = [
            "canonicalObjectId":  objectId,
            "roomId":             roomId,
            "authorId":           uid,
            "authorDisplayName":  displayName,
            "authorAvatarURL":    avatarURL,
            "body":               body,
            "reactions":          [String: Int](),
            "isDeleted":          false,
            "createdAt":          FieldValue.serverTimestamp()
        ]

        try await messagesCollection(objectId: objectId, roomId: roomId).addDocument(data: msgData)

        // Best-effort room metadata update
        let roomRef = roomsCollection(objectId: objectId).document(roomId)
        try? await roomRef.updateData([
            "lastMessage":    body,
            "lastMessageAt":  FieldValue.serverTimestamp(),
            "messageCount":   FieldValue.increment(Int64(1)),
            "updatedAt":      FieldValue.serverTimestamp()
        ])
    }

    func listenMessages(
        objectId: String,
        roomId: String,
        onChange: @escaping ([ObjectDiscussionMessage]) -> Void
    ) -> ListenerRegistration {
        messagesCollection(objectId: objectId, roomId: roomId)
            .order(by: "createdAt", descending: false)
            .limit(to: 100)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                Task { @MainActor in
                    let messages = snapshot.documents
                        .compactMap { try? $0.data(as: ObjectDiscussionMessage.self) }
                    onChange(messages)
                }
            }
    }

    // MARK: - Affordances

    /// Builds affordances from live Firestore rooms so the hub view shows real participant counts.
    func buildAffordances(objectId: String, objectTitle: String) async -> [ObjectAffordance] {
        let rooms: [ObjectDiscussionRoom]
        do { rooms = try await fetchRooms(for: objectId) }
        catch { rooms = [] }

        return ObjectDiscussionRoom.ObjectDiscussionRoomType.allCases.map { type in
            let existing = rooms.first { $0.roomType == type }
            return ObjectAffordance(
                id:               "\(objectId)-\(type.rawValue)",
                kind:             type.affordanceKind,
                roomId:           existing?.id,
                spawnable:        existing == nil,
                participantCount: existing?.participantCount ?? 0,
                label:            type.displayName
            )
        }
    }

    // MARK: - Errors

    enum DiscussionServiceError: LocalizedError {
        case notAuthenticated
        case roomCreationFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:  return "Sign in to join discussions."
            case .roomCreationFailed: return "Couldn't create the room. Please try again."
            }
        }
    }
}

// MARK: - Type helpers

private extension ObjectDiscussionRoom.ObjectDiscussionRoomType {
    var affordanceKind: ObjectAffordance.Kind {
        switch self {
        case .discussion: return .discussion
        case .prayer:     return .prayerRoom
        case .studyGroup: return .studyGroup
        }
    }
}
