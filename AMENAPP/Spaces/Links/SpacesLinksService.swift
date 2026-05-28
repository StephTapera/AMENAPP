// SpacesLinksService.swift
// AMENAPP — Spaces v2 Cross-Community Links (Agent F)
//
// @MainActor service for all community link operations.
// Wraps the three SpacesCallable callables (linkCommunity, acceptCommunityLink,
// revokeCommunityLink) and provides Firestore listeners for live state.
//
// Hard constraints:
//   - NEVER call .delete() on any Firestore document. Status flips only.
//   - Money never crosses a link — this service does NOT touch entitlements.
//   - No "church" in code.
//   - No force-unwrap.
//   - @MainActor — all published mutations on main actor.
//   - Listener refs stored and cancelled in deinit.

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// MARK: - SpacesLinksService

@MainActor
final class SpacesLinksService: ObservableObject {

    // MARK: - Published state

    @Published var pendingInvitations: [PendingLinkInvitation] = []
    @Published var activeLinks: [CommunityLink] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    // MARK: - Private

    private let db = Firestore.firestore()
    private lazy var functions = Functions.functions()

    /// All active listener registrations — cancelled on deinit.
    private var listeners: [ListenerRegistration] = []

    // MARK: - Init / deinit

    init() {}

    deinit {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Load links (live listener)

    /// Attaches a Firestore snapshot listener on `amenCommunities/{communityId}/links`
    /// ordered by createdAt. Splits results into `activeLinks` and `pendingInvitations`.
    func loadLinks(communityId: String) async {
        isLoading = true
        error = nil

        let ref = db.collection("amenCommunities")
            .document(communityId)
            .collection("links")
            .order(by: "createdAt", descending: false)

        let listener = ref.addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }
            if let err {
                self.error = err.localizedDescription
                self.isLoading = false
                return
            }
            guard let snapshot else {
                self.isLoading = false
                return
            }

            var active: [CommunityLink] = []

            for doc in snapshot.documents {
                guard let link = Self.mapLink(doc) else { continue }
                if link.status == .active {
                    active.append(link)
                }
            }

            self.activeLinks = active
            self.isLoading = false
        }
        listeners.append(listener)
    }

    // MARK: - Search community by handle

    /// Queries the `amenCommunities` collection where `handle == handle`.
    /// Returns nil if no matching community is found.
    /// Query is authenticated — Firestore rules gate the read.
    func searchCommunity(handle: String) async throws -> AmenCommunity? {
        let trimmed = handle
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        guard !trimmed.isEmpty else { return nil }

        let snapshot = try await db.collection("amenCommunities")
            .whereField("handle", isEqualTo: trimmed)
            .limit(to: 1)
            .getDocuments()

        guard let doc = snapshot.documents.first else { return nil }
        return try? doc.data(as: AmenCommunity.self)
    }

    // MARK: - Invite to link

    /// Calls the `linkCommunity` Firebase callable.
    /// Returns the new linkId on success.
    /// Money never crosses a link — this call creates only the link record.
    func inviteToLink(
        fromCommunityId: String,
        targetCommunityId: String,
        spaceId: String
    ) async throws -> String {
        let payload: [String: Any] = [
            "fromCommunityId": fromCommunityId,
            "targetCommunityId": targetCommunityId,
            "spaceId": spaceId
        ]
        let callable = functions.httpsCallable(SpacesCallable.linkCommunity.rawValue)
        let result = try await callable.call(payload)

        guard let data = result.data as? [String: Any],
              let linkId = data["linkId"] as? String else {
            throw LinksServiceError.unexpectedResponse
        }
        return linkId
    }

    // MARK: - Accept a link

    /// Calls the `acceptCommunityLink` callable.
    /// The backend fan-outs `sharedWith` on the space doc.
    /// `activeLinks` updates automatically via the Firestore listener.
    func acceptLink(linkId: String, communityId: String) async throws {
        let payload: [String: Any] = [
            "linkId": linkId,
            "communityId": communityId
        ]
        let callable = functions.httpsCallable(SpacesCallable.acceptCommunityLink.rawValue)
        _ = try await callable.call(payload)
        // Listener update picks up the status change; no client-side array mutation needed.
    }

    // MARK: - Revoke a link

    /// Calls the `revokeCommunityLink` callable.
    /// Status flips to revoked on backend; external members' access drops via backend.
    /// Never calls .delete() on any Firestore document.
    func revokeLink(linkId: String, communityId: String) async throws {
        let payload: [String: Any] = [
            "linkId": linkId,
            "communityId": communityId
        ]
        let callable = functions.httpsCallable(SpacesCallable.revokeCommunityLink.rawValue)
        _ = try await callable.call(payload)
        // Listener update removes the link from activeLinks automatically.
    }

    // MARK: - Load pending invitations (for target community admins)

    /// Loads `amenCommunities/{communityId}/links` where status == "pending"
    /// and `toCommunityId == communityId` (invitations TO this community).
    /// Resolves the inviting community's name and avatar for display.
    func loadPendingInvitations(forCommunityId communityId: String) async {
        isLoading = true
        error = nil

        let ref = db.collection("amenCommunities")
            .document(communityId)
            .collection("links")
            .whereField("status", isEqualTo: "pending")
            .whereField("toCommunityId", isEqualTo: communityId)

        let listener = ref.addSnapshotListener { [weak self] snapshot, err in
            guard let self else { return }
            if let err {
                self.error = err.localizedDescription
                self.isLoading = false
                return
            }
            guard let snapshot else {
                self.isLoading = false
                return
            }

            // Resolve community names asynchronously.
            Task { [weak self] in
                guard let self else { return }
                var invitations: [PendingLinkInvitation] = []

                for doc in snapshot.documents {
                    guard let invitation = await self.resolvePendingInvitation(doc: doc) else {
                        continue
                    }
                    invitations.append(invitation)
                }

                self.pendingInvitations = invitations
                self.isLoading = false
            }
        }
        listeners.append(listener)
    }

    // MARK: - Private: resolve a pending invitation doc

    private func resolvePendingInvitation(
        doc: QueryDocumentSnapshot
    ) async -> PendingLinkInvitation? {
        let d = doc.data()
        guard
            let fromCommunityId = d["fromCommunityId"] as? String,
            let spaceId = d["spaceId"] as? String
        else { return nil }

        let createdAt = (d["createdAt"] as? Timestamp)?.dateValue() ?? Date()

        // Resolve sending community name + avatar (one-time get, not a listener).
        var fromCommunityName = fromCommunityId
        var fromCommunityAvatarURL: String? = nil

        if let communitySnap = try? await db.collection("amenCommunities")
            .document(fromCommunityId)
            .getDocument(),
           communitySnap.exists {
            fromCommunityName = communitySnap.data()?["name"] as? String ?? fromCommunityId
            fromCommunityAvatarURL = communitySnap.data()?["avatarURL"] as? String
        }

        // Resolve Space title for display.
        var spaceTitle = "Shared Space"
        if let spaceSnap = try? await db.collection("spaces").document(spaceId).getDocument(),
           spaceSnap.exists {
            spaceTitle = spaceSnap.data()?["title"] as? String ?? spaceTitle
        }

        return PendingLinkInvitation(
            id: doc.documentID,
            spaceId: spaceId,
            spaceTitle: spaceTitle,
            fromCommunityId: fromCommunityId,
            fromCommunityName: fromCommunityName,
            fromCommunityAvatarURL: fromCommunityAvatarURL,
            createdAt: createdAt
        )
    }

    // MARK: - Private: map Firestore doc to CommunityLink

    private static func mapLink(_ doc: QueryDocumentSnapshot) -> CommunityLink? {
        // CommunityLink is defined in SpacesModels.swift (Agent A).
        // We try? Codable decode first; if that fails (e.g. missing @DocumentID mapping),
        // we fall back to manual extraction.
        if let link = try? doc.data(as: CommunityLink.self) {
            return link
        }

        let d = doc.data()
        guard
            let otherCommunityId = d["otherCommunityId"] as? String,
            let statusRaw = d["status"] as? String,
            let status = CommunityLink.LinkStatus(rawValue: statusRaw),
            let scope = d["scope"] as? String,
            let createdBy = d["createdBy"] as? String,
            let createdAtTimestamp = d["createdAt"] as? Timestamp,
            let updatedAtTimestamp = d["updatedAt"] as? Timestamp
        else { return nil }

        return CommunityLink(
            otherCommunityId: otherCommunityId,
            status: status,
            scope: scope,
            createdBy: createdBy,
            createdAt: createdAtTimestamp,
            updatedAt: updatedAtTimestamp
        )
    }
}

// MARK: - LinksServiceError

enum LinksServiceError: LocalizedError {
    case unexpectedResponse
    case notAuthenticated
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse:  return "Received an unexpected response from the server."
        case .notAuthenticated:    return "You must be signed in to perform this action."
        case .underlying(let e):   return e.localizedDescription
        }
    }
}
