// CrossCommunityLinkService.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// async/await service for all cross-community link operations.
// @MainActor — all published mutations go to the main actor.
//
// Firestore schema (CONTRACT_A.md):
//   amenCommunities/{communityId}/links/{linkId}
//   spaces/{spaceId}.sharedWith: [communityId]
//   spaces/{spaceId}/members/{userId}
//
// Hard constraints:
//   - NEVER hard-delete any Firestore document.
//   - revokeSpaceLinkAccess Cloud Function (Agent A) does member access flips.
//   - Document ID for a link = {fromCommunityId}_{toCommunityId} (CONTRACT_A §8 assumption 2).
//   - No Combine — async/await only.
//   - No "church" in code.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - CrossCommunityLinkService

@MainActor
final class CrossCommunityLinkService: ObservableObject {

    static let shared = CrossCommunityLinkService()

    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    private init() {}

    // MARK: - Private helpers

    private var currentUID: String {
        get throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw CrossLinkError.notAuthenticated
            }
            return uid
        }
    }

    private func linksCollection(communityId: String) -> CollectionReference {
        db.collection("amenCommunities").document(communityId).collection("links")
    }

    private func spaceRef(_ spaceId: String) -> DocumentReference {
        db.collection("spaces").document(spaceId)
    }

    // MARK: - Send a link invite

    /// Creates a link document under the fromCommunity's /links sub-collection
    /// with status "pending". The Cloud Function `notifyCommunityLinkInvite`
    /// fires on onCreate and pushes FCM to the target community's admins.
    func sendLinkInvite(
        fromCommunityId: String,
        toCommunityId: String,
        spaceId: String,
        scope: String
    ) async throws {
        let uid = try currentUID
        // Document ID pattern: {homeCommunityId}_{owningCommunityId} (CONTRACT_A §8 #2)
        let linkId = "\(fromCommunityId)_\(toCommunityId)"
        let ref = linksCollection(communityId: fromCommunityId).document(linkId)

        // Check if an active or pending link already exists to avoid duplicates.
        let existing = try await ref.getDocument()
        if existing.exists {
            let statusRaw = existing.data()?["status"] as? String ?? ""
            if statusRaw == CrossLinkStatus.active.rawValue {
                throw CrossLinkError.alreadyLinked
            }
            if statusRaw == CrossLinkStatus.pending.rawValue {
                throw CrossLinkError.inviteAlreadyPending
            }
            // Revoked — allow re-invite by overwriting the doc below.
        }

        let now = Timestamp(date: Date())
        let data: [String: Any] = [
            "otherCommunityId": toCommunityId,
            "status": CrossLinkStatus.pending.rawValue,
            "scope": scope,
            "createdBy": uid,
            "createdAt": now,
            "updatedAt": now,
            // F-specific extension fields so the Cloud Function can look up the space
            "spaceId": spaceId,
            "fromCommunityId": fromCommunityId,
            "toCommunityId": toCommunityId
        ]
        try await ref.setData(data, merge: false)
    }

    // MARK: - Accept an incoming invite

    /// Sets link.status = "active" and atomically adds communityId to
    /// spaces/{spaceId}.sharedWith. The caller must be admin/owner of toCommunityId.
    func acceptLink(
        linkId: String,
        inCommunityId: String,
        spaceId: String
    ) async throws {
        let linkRef = linksCollection(communityId: inCommunityId).document(linkId)

        // Verify the link is still pending before accepting.
        let snap = try await linkRef.getDocument()
        guard snap.exists else { throw CrossLinkError.linkNotFound }
        let statusRaw = snap.data()?["status"] as? String ?? ""
        guard statusRaw == CrossLinkStatus.pending.rawValue else {
            throw CrossLinkError.invalidLinkState(statusRaw)
        }

        let now = Timestamp(date: Date())
        let batch = db.batch()

        // Flip link status to active.
        batch.updateData([
            "status": CrossLinkStatus.active.rawValue,
            "updatedAt": now
        ], forDocument: linkRef)

        // Atomically add this community to sharedWith on the Space.
        // arrayUnion is idempotent — safe if already present.
        let spaceDocument = spaceRef(spaceId)
        batch.updateData([
            "sharedWith": FieldValue.arrayUnion([inCommunityId])
        ], forDocument: spaceDocument)

        try await batch.commit()
    }

    // MARK: - Decline an invite

    /// Flips link.status to "revoked". Does NOT delete the document.
    func declineLink(
        linkId: String,
        inCommunityId: String
    ) async throws {
        let ref = linksCollection(communityId: inCommunityId).document(linkId)
        let now = Timestamp(date: Date())
        try await ref.updateData([
            "status": CrossLinkStatus.revoked.rawValue,
            "updatedAt": now
        ])
    }

    // MARK: - Revoke an active link

    /// Flips link.status to "revoked" and calls the Agent A
    /// `revokeSpaceLinkAccess` Cloud Function to flip all external members'
    /// access to "none". Never hard-deletes.
    func revokeLink(
        linkId: String,
        inCommunityId: String,
        spaceId: String
    ) async throws {
        let ref = linksCollection(communityId: inCommunityId).document(linkId)

        // Read to get fromCommunityId (the community whose members lose access).
        let snap = try await ref.getDocument()
        guard snap.exists else { throw CrossLinkError.linkNotFound }

        // Determine which communityId has external members to revoke.
        // If inCommunityId is the toCommunity, the fromCommunity's members are external here.
        // If inCommunityId is the fromCommunity, the toCommunity's members are external.
        let fromId = snap.data()?["fromCommunityId"] as? String ?? ""
        let toId   = snap.data()?["toCommunityId"]   as? String ?? ""
        let revokedCommunityId = (inCommunityId == fromId) ? toId : fromId

        let now = Timestamp(date: Date())

        // Step 1: Flip link status (non-atomic pre-step; CF handles the rest).
        try await ref.updateData([
            "status": CrossLinkStatus.revoked.rawValue,
            "updatedAt": now
        ])

        // Step 2: Call Agent A's Cloud Function to flip member access + remove from sharedWith.
        // CONTRACT_A §4 "revokeSpaceLinkAccess" payload: { spaceId, revokedCommunityId }
        let payload: [String: Any] = [
            "spaceId": spaceId,
            "revokedCommunityId": revokedCommunityId
        ]
        let callable = functions.httpsCallable("revokeSpaceLinkAccess")
        _ = try await callable.call(payload)
    }

    // MARK: - Fetch incoming invites

    /// Returns links where status == "pending" and the community is the recipient.
    /// The link lives in the sender's /links collection, so we use a collection group query.
    func fetchIncomingInvites(communityId: String) async throws -> [CommunityLinkRecord] {
        let snap = try await db.collectionGroup("links")
            .whereField("toCommunityId", isEqualTo: communityId)
            .whereField("status", isEqualTo: CrossLinkStatus.pending.rawValue)
            .getDocuments()
        return snap.documents.compactMap { mapToRecord($0) }
    }

    // MARK: - Fetch outgoing invites

    /// Returns links originating FROM communityId with any status.
    func fetchOutgoingInvites(communityId: String) async throws -> [CommunityLinkRecord] {
        let snap = try await linksCollection(communityId: communityId)
            .whereField("fromCommunityId", isEqualTo: communityId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { mapToRecord($0) }
    }

    // MARK: - Fetch linked communities for a Space

    /// Returns LinkedCommunityRecord list for all communities actively sharing spaceId.
    /// Resolves community names from amenCommunities.
    func fetchLinkedCommunities(spaceId: String) async throws -> [LinkedCommunityRecord] {
        // 1. Get the Space to read sharedWith.
        let spaceSnap = try await spaceRef(spaceId).getDocument()
        guard spaceSnap.exists else { throw CrossLinkError.spaceNotFound }
        let sharedWith = spaceSnap.data()?["sharedWith"] as? [String] ?? []
        guard !sharedWith.isEmpty else { return [] }

        // 2. For each sharedCommunityId, fetch community doc + external member count.
        var records: [LinkedCommunityRecord] = []
        for communityId in sharedWith {
            let communitySnap = try await db.collection("amenCommunities")
                .document(communityId).getDocument()
            let name = communitySnap.data()?["name"] as? String ?? communityId
            let avatarURL = communitySnap.data()?["avatarURL"] as? String

            // Count external members.
            let membersSnap = try await db.collection("spaces").document(spaceId)
                .collection("members")
                .whereField("homeCommunityId", isEqualTo: communityId)
                .whereField("access", isEqualTo: "granted")
                .getDocuments()
            let externalCount = membersSnap.count

            // Find active link document for this pair (collection group).
            let linkSnap = try await db.collectionGroup("links")
                .whereField("toCommunityId", isEqualTo: communityId)
                .whereField("status", isEqualTo: CrossLinkStatus.active.rawValue)
                .limit(to: 1)
                .getDocuments()
            let linkId = linkSnap.documents.first?.documentID ?? ""

            records.append(LinkedCommunityRecord(
                id: communityId,
                name: name,
                avatarURL: avatarURL,
                externalMemberCount: externalCount,
                linkId: linkId,
                linkStatus: .active
            ))
        }
        return records
    }

    // MARK: - Real-time stream of linked communities

    /// AsyncStream that emits every time the Space's sharedWith field changes.
    /// Resolves community names and member counts on each update.
    nonisolated func streamLinkedCommunities(spaceId: String) -> AsyncStream<[LinkedCommunityRecord]> {
        AsyncStream { continuation in
            let listener = Firestore.firestore()
                .collection("spaces")
                .document(spaceId)
                .addSnapshotListener { snapshot, _ in
                    guard let snap = snapshot, snap.exists else {
                        continuation.yield([])
                        return
                    }
                    let sharedWith = snap.data()?["sharedWith"] as? [String] ?? []
                    // Resolve community records asynchronously from the stream.
                    Task {
                        do {
                            let records = try await CrossCommunityLinkService.shared
                                .fetchLinkedCommunities(spaceId: spaceId)
                            continuation.yield(records)
                        } catch {
                            // Emit empty on error — never crash.
                            let _ = sharedWith
                            continuation.yield([])
                        }
                    }
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    // MARK: - Community search

    /// Searches amenCommunities by name prefix (Firestore range query).
    /// For production replace with Algolia; this is a safe Firestore fallback.
    func searchCommunities(query: String) async throws -> [SpacesCommunity] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let end = query + "\u{f8ff}"
        let snap = try await db.collection("amenCommunities")
            .whereField("name", isGreaterThanOrEqualTo: query)
            .whereField("name", isLessThanOrEqualTo: end)
            .limit(to: 20)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: SpacesCommunity.self) }
    }

    // MARK: - Write external member join record

    /// Called by ExternalJoinPrompt when an external member confirms.
    /// Writes spaces/{spaceId}/members/{userId} with homeCommunityId and access: "granted".
    /// Safe to call multiple times — uses setData(merge: true).
    func joinAsExternalMember(
        spaceId: String,
        homeCommunityId: String
    ) async throws {
        let uid = try currentUID
        let ref = db.collection("spaces").document(spaceId)
            .collection("members").document(uid)
        let now = Timestamp(date: Date())
        let data: [String: Any] = [
            "role": "member",
            "homeCommunityId": homeCommunityId,
            "access": "granted",
            "joinedAt": now
        ]
        try await ref.setData(data, merge: true)
    }

    // MARK: - Private mapping

    private func mapToRecord(_ doc: QueryDocumentSnapshot) -> CommunityLinkRecord? {
        let d = doc.data()
        guard
            let fromId   = d["fromCommunityId"] as? String,
            let toId     = d["toCommunityId"]   as? String,
            let statusRaw = d["status"] as? String,
            let status   = CrossLinkStatus(rawValue: statusRaw),
            let scope    = d["scope"] as? String,
            let createdBy = d["createdBy"] as? String
        else { return nil }

        let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (d["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        return CommunityLinkRecord(
            id: doc.documentID,
            fromCommunityId: fromId,
            toCommunityId: toId,
            status: status,
            scope: scope,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - CrossLinkError

enum CrossLinkError: LocalizedError {
    case notAuthenticated
    case alreadyLinked
    case inviteAlreadyPending
    case linkNotFound
    case spaceNotFound
    case invalidLinkState(String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:          return "You must be signed in."
        case .alreadyLinked:             return "These communities are already linked."
        case .inviteAlreadyPending:      return "An invite is already waiting for a response."
        case .linkNotFound:              return "The link could not be found."
        case .spaceNotFound:             return "The Space could not be found."
        case .invalidLinkState(let s):   return "Cannot perform this action on a link with status: \(s)."
        case .underlying(let e):         return e.localizedDescription
        }
    }
}
