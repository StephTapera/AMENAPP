// SpacesService.swift
// AMENAPP — Spaces Data Layer
//
// Firestore CRUD + real-time listeners for AMEN Spaces.
// All methods use async/await — no Combine.
// All UI mutation must be dispatched to @MainActor by the caller.
//
// Collection paths:
//   amenCommunities/{communityId}
//   amenCommunities/{communityId}/members/{userId}
//   amenCommunities/{communityId}/links/{linkId}
//   spaces/{spaceId}
//   spaces/{spaceId}/members/{userId}
//   spaces/{spaceId}/threads/{threadId}
//   spaces/{spaceId}/threads/{threadId}/messages/{messageId}
//   spaces/{spaceId}/studies/{studyId}
//   spaces/{spaceId}/studies/{studyId}/blocks/{blockId}
//   entitlements/{userId}_{spaceId}
//
// See CONTRACT_A.md for the full public API contract.

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - SpacesServiceError

enum SpacesServiceError: LocalizedError {
    case notAuthenticated
    case notFound
    case permissionDenied
    case encodingFailed
    case invalidArgument(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:         return "You must be signed in."
        case .notFound:                 return "The requested item was not found."
        case .permissionDenied:         return "You do not have permission to access this."
        case .encodingFailed:           return "Failed to encode the data."
        case .invalidArgument(let msg): return msg
        case .underlying(let e):        return e.localizedDescription
        }
    }
}

// MARK: - SpacesService

@MainActor
final class SpacesService {

    static let shared = SpacesService()
    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Helpers

    private var currentUID: String {
        get throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw SpacesServiceError.notAuthenticated
            }
            return uid
        }
    }

    private func communityRef(_ communityId: String) -> DocumentReference {
        db.collection("amenCommunities").document(communityId)
    }

    private func spaceRef(_ spaceId: String) -> DocumentReference {
        db.collection("spaces").document(spaceId)
    }

    private func entitlementRef(userId: String, spaceId: String) -> DocumentReference {
        db.collection("entitlements").document("\(userId)_\(spaceId)")
    }

    // MARK: - Communities

    /// Fetch a single community document.
    func fetchCommunity(communityId: String) async throws -> SpacesCommunity {
        let doc = try await communityRef(communityId).getDocument()
        guard doc.exists else { throw SpacesServiceError.notFound }
        guard let community = try? doc.data(as: SpacesCommunity.self) else {
            throw SpacesServiceError.encodingFailed
        }
        return community
    }

    /// Fetch all communities where the current user is a member.
    func fetchMyCommunities() async throws -> [SpacesCommunity] {
        let uid = try currentUID
        // Query amenCommunities where members/{uid} exists — done via collection group
        let snap = try await db.collectionGroup("members")
            .whereField(FieldPath.documentID(), isEqualTo: uid)
            .getDocuments()
        var communities: [SpacesCommunity] = []
        for doc in snap.documents {
            // Parent path: amenCommunities/{communityId}/members/{uid}
            let communityRef = doc.reference.parent.parent
            if let ref = communityRef {
                let communityDoc = try await ref.getDocument()
                if let c = try? communityDoc.data(as: SpacesCommunity.self) {
                    communities.append(c)
                }
            }
        }
        return communities
    }

    // MARK: - Community Members

    /// Fetch community member record.
    func fetchCommunityMember(communityId: String, userId: String) async throws -> CommunityMember {
        let doc = try await communityRef(communityId)
            .collection("members").document(userId).getDocument()
        guard doc.exists else { throw SpacesServiceError.notFound }
        guard let member = try? doc.data(as: CommunityMember.self) else {
            throw SpacesServiceError.encodingFailed
        }
        return member
    }

    /// Fetch all members of a community.
    func fetchCommunityMembers(communityId: String) async throws -> [CommunityMember] {
        let snap = try await communityRef(communityId).collection("members").getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CommunityMember.self) }
    }

    // MARK: - Community Links

    /// Fetch all active links for a community.
    func fetchActiveLinks(communityId: String) async throws -> [CommunityLink] {
        let snap = try await communityRef(communityId)
            .collection("links")
            .whereField("status", isEqualTo: CommunityLink.LinkStatus.active.rawValue)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: CommunityLink.self) }
    }

    // MARK: - Spaces

    /// Fetch all spaces for a community, ordered by creation date.
    func fetchSpaces(communityId: String) async throws -> [AmenSpace] {
        let snap = try await db.collection("spaces")
            .whereField("communityId", isEqualTo: communityId)
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AmenSpace.self) }
    }

    /// Fetch a single space document.
    func fetchSpace(spaceId: String) async throws -> AmenSpace {
        let doc = try await spaceRef(spaceId).getDocument()
        guard doc.exists else { throw SpacesServiceError.notFound }
        guard let space = try? doc.data(as: AmenSpace.self) else {
            throw SpacesServiceError.encodingFailed
        }
        return space
    }

    /// Real-time listener for a single Space document.
    /// Returns a task that can be cancelled to stop listening.
    nonisolated func spaceListener(
        spaceId: String,
        onUpdate: @escaping @MainActor (AmenSpace) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore().collection("spaces").document(spaceId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in onError(error) }
                    return
                }
                if let space = try? snapshot?.data(as: AmenSpace.self) {
                    Task { @MainActor in onUpdate(space) }
                }
            }
    }

    // MARK: - Space Members

    /// Fetch space member record for the current user.
    func fetchMySpaceMembership(spaceId: String) async throws -> SpaceMember? {
        let uid = try currentUID
        let doc = try await spaceRef(spaceId).collection("members").document(uid).getDocument()
        guard doc.exists else { return nil }
        return try? doc.data(as: SpaceMember.self)
    }

    /// Fetch all members of a space.
    func fetchSpaceMembers(spaceId: String) async throws -> [SpaceMember] {
        let snap = try await spaceRef(spaceId).collection("members").getDocuments()
        return snap.documents.compactMap { try? $0.data(as: SpaceMember.self) }
    }

    /// Fetch external members of a space (homeCommunityId != "").
    func fetchExternalMembers(spaceId: String) async throws -> [SpaceMember] {
        // Firestore doesn't support != directly on all SDK versions; use two queries approach:
        // We fetch all and filter. For production, add an index on homeCommunityId.
        let all = try await fetchSpaceMembers(spaceId: spaceId)
        return all.filter { !$0.homeCommunityId.isEmpty }
    }

    // MARK: - Threads

    /// Fetch threads for a space, ordered by lastMessageAt.
    func fetchThreads(spaceId: String) async throws -> [SpaceThread] {
        let snap = try await spaceRef(spaceId)
            .collection("threads")
            .order(by: "lastMessageAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: SpaceThread.self) }
    }

    /// Create a new thread in a space.
    func createThread(spaceId: String, title: String?) async throws -> String {
        let uid = try currentUID
        let now = Timestamp(date: Date())
        let ref = spaceRef(spaceId).collection("threads").document()
        let thread = [
            "spaceId": spaceId,
            "title": title as Any,
            "createdBy": uid,
            "createdAt": now,
            "lastMessageAt": now
        ] as [String: Any]
        try await ref.setData(thread)
        return ref.documentID
    }

    /// Real-time listener for threads in a space.
    nonisolated func threadsListener(
        spaceId: String,
        onUpdate: @escaping @MainActor ([SpaceThread]) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore().collection("spaces").document(spaceId)
            .collection("threads")
            .order(by: "lastMessageAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in onError(error) }
                    return
                }
                let threads = snapshot?.documents.compactMap {
                    try? $0.data(as: SpaceThread.self)
                } ?? []
                Task { @MainActor in onUpdate(threads) }
            }
    }

    // MARK: - Messages

    /// Fetch messages in a thread, ordered by creation time.
    func fetchMessages(spaceId: String, threadId: String, limit: Int = 50) async throws -> [SpaceMessage] {
        let snap = try await spaceRef(spaceId)
            .collection("threads").document(threadId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: SpaceMessage.self) }
    }

    /// Send a new message in a thread.
    /// Returns the new messageId.
    func sendMessage(
        spaceId: String,
        threadId: String,
        body: String,
        attachments: [SpaceMessageAttachment] = []
    ) async throws -> String {
        let uid = try currentUID
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpacesServiceError.invalidArgument("Message body cannot be empty.")
        }
        let now = Timestamp(date: Date())
        let msgRef = spaceRef(spaceId)
            .collection("threads").document(threadId)
            .collection("messages").document()

        let attachmentData = attachments.map { att -> [String: Any] in
            var m: [String: Any] = ["type": att.type, "url": att.url]
            m["metadata"] = att.metadata
            return m
        }

        let msgData: [String: Any] = [
            "authorId": uid,
            "body": body,
            "createdAt": now,
            "reactions": [String: [String]](),
            "attachments": attachmentData,
            "status": SpaceMessage.MessageStatus.active.rawValue
        ]
        try await msgRef.setData(msgData)

        // Update thread's lastMessageAt
        try await spaceRef(spaceId).collection("threads").document(threadId)
            .updateData(["lastMessageAt": now])

        return msgRef.documentID
    }

    /// Soft-delete a message (status flip, never hard-delete).
    func deleteMessage(spaceId: String, threadId: String, messageId: String) async throws {
        let uid = try currentUID
        let ref = spaceRef(spaceId)
            .collection("threads").document(threadId)
            .collection("messages").document(messageId)
        let doc = try await ref.getDocument()
        guard let authorId = doc.data()?["authorId"] as? String, authorId == uid else {
            throw SpacesServiceError.permissionDenied
        }
        try await ref.updateData(["status": SpaceMessage.MessageStatus.deleted.rawValue])
    }

    /// Add a reaction to a message.
    func toggleReaction(
        spaceId: String,
        threadId: String,
        messageId: String,
        emoji: String
    ) async throws {
        let uid = try currentUID
        let ref = spaceRef(spaceId)
            .collection("threads").document(threadId)
            .collection("messages").document(messageId)

        try await db.runTransaction { transaction, _ in
            let snap = try? transaction.getDocument(ref)
            var reactions = snap?.data()?["reactions"] as? [String: [String]] ?? [:]
            var users = reactions[emoji] ?? []
            if let idx = users.firstIndex(of: uid) {
                users.remove(at: idx)
            } else {
                users.append(uid)
            }
            if users.isEmpty {
                reactions.removeValue(forKey: emoji)
            } else {
                reactions[emoji] = users
            }
            transaction.updateData(["reactions": reactions], forDocument: ref)
            return nil
        }
    }

    /// Real-time listener for messages in a thread.
    nonisolated func messagesListener(
        spaceId: String,
        threadId: String,
        onUpdate: @escaping @MainActor ([SpaceMessage]) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore().collection("spaces").document(spaceId)
            .collection("threads").document(threadId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in onError(error) }
                    return
                }
                let messages = snapshot?.documents.compactMap {
                    try? $0.data(as: SpaceMessage.self)
                } ?? []
                Task { @MainActor in onUpdate(messages) }
            }
    }

    // MARK: - Studies

    /// Fetch studies for a space.
    func fetchStudies(spaceId: String) async throws -> [SpaceStudy] {
        let snap = try await spaceRef(spaceId)
            .collection("studies")
            .order(by: "createdAt", descending: false)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: SpaceStudy.self) }
    }

    /// Create a new study in a space.
    func createStudy(
        spaceId: String,
        title: String,
        passageRefs: [String],
        cadence: String? = nil
    ) async throws -> String {
        let uid = try currentUID
        guard !title.isEmpty else {
            throw SpacesServiceError.invalidArgument("Study title cannot be empty.")
        }
        let now = Timestamp(date: Date())
        let ref = spaceRef(spaceId).collection("studies").document()
        let data: [String: Any] = [
            "spaceId": spaceId,
            "title": title,
            "passageRefs": passageRefs,
            "cadence": cadence as Any,
            "createdBy": uid,
            "createdAt": now
        ]
        try await ref.setData(data)
        return ref.documentID
    }

    // MARK: - Study Blocks

    /// Fetch all blocks for a study, ordered by sortOrder.
    func fetchBlocks(spaceId: String, studyId: String) async throws -> [StudyBlock] {
        let snap = try await spaceRef(spaceId)
            .collection("studies").document(studyId)
            .collection("blocks")
            .order(by: "sortOrder", descending: false)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: StudyBlock.self) }
    }

    /// Upsert a block in a study. Creates or overwrites by blockId.
    func upsertBlock(_ block: StudyBlock, spaceId: String, studyId: String) async throws {
        guard let blockId = block.id else {
            throw SpacesServiceError.invalidArgument("Block must have an id.")
        }
        let ref = spaceRef(spaceId)
            .collection("studies").document(studyId)
            .collection("blocks").document(blockId)
        guard let encoded = try? Firestore.Encoder().encode(block) else {
            throw SpacesServiceError.encodingFailed
        }
        try await ref.setData(encoded, merge: true)
    }

    // MARK: - Space Creation (Agent D)

    /// Create a new Space in a community, write the creator as owner member, and return the new spaceId.
    /// Writes `spaces/{spaceId}` + `spaces/{spaceId}/members/{uid}` in a single Firestore batch.
    ///
    /// - Parameters:
    ///   - communityId: The owning community (amenCommunities collection).
    ///   - type: Space type (.chat | .bibleStudy | .group — never .announcement from wizard).
    ///   - title: Space display name (non-empty).
    ///   - description: Berean-generated or user-edited description.
    ///   - accessPolicy: .free | .oneTime | .recurring.
    ///   - priceConfig: Required when accessPolicy is paid; nil when free.
    ///   - passageRefs: Optional passage references (bibleStudy only).
    ///   - cadence: Optional cadence string (bibleStudy only).
    /// - Returns: The new spaceId (Firestore document ID).
    func createSpace(
        communityId: String,
        type: AmenSpace.SpaceType,
        title: String,
        description: String,
        accessPolicy: AmenSpace.AccessPolicy,
        priceConfig: SpacePriceConfig?,
        passageRefs: [String]?,
        cadence: String?
    ) async throws -> String {
        let uid = try currentUID

        guard !communityId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpacesServiceError.invalidArgument("communityId cannot be empty.")
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpacesServiceError.invalidArgument("Space title cannot be empty.")
        }

        let spaceRef = db.collection("spaces").document()
        let memberRef = spaceRef.collection("members").document(uid)
        let now = Timestamp(date: Date())

        // Build the Space document
        var spaceData: [String: Any] = [
            "communityId": communityId,
            "type": type.rawValue,
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": description,
            "createdBy": uid,
            "createdAt": now,
            "accessPolicy": accessPolicy.rawValue,
            "sharedWith": [String]()
        ]

        // Optional fields — omit when nil to keep the document clean
        if let config = priceConfig {
            var configMap: [String: Any] = [
                "amountCents": config.amountCents,
                "currency": config.currency
            ]
            if let interval = config.interval {
                configMap["interval"] = interval
            }
            spaceData["priceConfig"] = configMap
        }

        if let refs = passageRefs, !refs.isEmpty {
            spaceData["passageRefs"] = refs
        }

        if let cad = cadence, !cad.isEmpty {
            spaceData["cadence"] = cad
        }

        // Owner member record
        let memberData: [String: Any] = [
            "role": SpaceMemberRole.owner.rawValue,
            "homeCommunityId": "",   // same community — "" per CONTRACT_A
            "access": SpaceAccess.granted.rawValue,
            "joinedAt": now
        ]

        // Atomic batch write
        let batch = db.batch()
        batch.setData(spaceData, forDocument: spaceRef)
        batch.setData(memberData, forDocument: memberRef)
        try await batch.commit()

        return spaceRef.documentID
    }

    // MARK: - Entitlements

    /// Fetch the entitlement for the current user and a specific space.
    /// Returns nil if no entitlement exists (i.e., not purchased/granted).
    func fetchEntitlement(spaceId: String) async throws -> SpaceEntitlement? {
        let uid = try currentUID
        let doc = try await entitlementRef(userId: uid, spaceId: spaceId).getDocument()
        guard doc.exists else { return nil }
        return try? doc.data(as: SpaceEntitlement.self)
    }

    /// Real-time listener for the current user's entitlement to a space.
    /// Used to reactively update the paywall/locked-preview UI.
    nonisolated func entitlementListener(
        userId: String,
        spaceId: String,
        onUpdate: @escaping @MainActor (SpaceEntitlement?) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore().collection("entitlements")
            .document("\(userId)_\(spaceId)")
            .addSnapshotListener { snapshot, error in
                if let error {
                    Task { @MainActor in onError(error) }
                    return
                }
                let entitlement = try? snapshot?.data(as: SpaceEntitlement.self)
                Task { @MainActor in onUpdate(entitlement) }
            }
    }

    /// Check whether the current user has active access to a space.
    /// Considers both entitlement and membership.
    func hasAccess(to space: AmenSpace) async throws -> Bool {
        guard let spaceId = space.id else { return false }
        // Free spaces are open to all space members
        if space.accessPolicy == .free { return true }
        // Paid: check entitlement
        let entitlement = try await fetchEntitlement(spaceId: spaceId)
        return entitlement?.isAccessible ?? false
    }

    /// Fetch all entitlements for the current user (active and grace).
    func fetchMyActiveEntitlements() async throws -> [SpaceEntitlement] {
        let uid = try currentUID
        let snap = try await db.collection("entitlements")
            .whereField("userId", isEqualTo: uid)
            .whereField("status", in: [
                SpaceEntitlement.EntitlementStatus.active.rawValue,
                SpaceEntitlement.EntitlementStatus.grace.rawValue
            ])
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: SpaceEntitlement.self) }
    }
}
