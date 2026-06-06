// AmenOrganizationService.swift
// AMEN Community OS — Organization OS (A9)
//
// @MainActor service for fetching, following, and managing organizations.
// Reuses the AmenEdge / EdgeService pattern (CommunityOS/Core/EdgeService.swift)
// for follow/unfollow — no bespoke follower-count field.
//
// RBAC: profile updates are enforced server-side via Firestore security rules
// (C5) and the callable `updateOrgProfile` Cloud Function. The iOS layer only
// calls the function — it does not validate role locally (defense-in-depth).
//
// Privacy contract:
//   - memberCount is loaded internally only — never exposed to public UI
//   - contactEmail and ein fields are never read on this service path
//
// Feature gate: AppStorage("community_os_org_os_enabled") — defaults to false.

import Foundation
import FirebaseFirestore
import FirebaseFunctions

// MARK: - AmenOrganizationService

@MainActor
final class AmenOrganizationService: ObservableObject {

    // MARK: Published state

    @Published var organization: AmenOrganization?
    @Published var announcements: [AmenOrgAnnouncement] = []
    @Published var followedOrgs: [AmenOrganization] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: Private dependencies

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    // MARK: - Fetch single org

    /// Loads the full AmenOrganization from Firestore.
    /// Only active, non-deleted orgs are surfaced.
    func fetchOrg(id: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let doc = try await db
            .collection("organizations")
            .document(id)
            .getDocument()

        guard let data = doc.data() else {
            throw OrgServiceError.notFound(id)
        }

        organization = try decodeOrg(from: data, id: doc.documentID)
    }

    // MARK: - Follow / Unfollow

    /// Creates a user → org follow edge in Firestore `/edges/`.
    /// No follower count is stored on the org document — counts stay server-side.
    func followOrg(orgId: String, userId: String) async throws {
        let edgeData: [String: Any] = [
            "fromRef": "users/\(userId)",
            "fromType": "user",
            "toRef": "organizations/\(orgId)",
            "toType": "organization",
            "edgeType": "follows",
            "createdBy": userId,
            "visibility": "public",
            "createdAt": FieldValue.serverTimestamp(),
            "isDeleted": false
        ]

        let edgeId = "\(userId)_follows_\(orgId)"
        try await db
            .collection("edges")
            .document(edgeId)
            .setData(edgeData, merge: true)
    }

    /// Soft-deletes the follow edge — preserves the edge document with `isDeleted: true`.
    func unfollowOrg(orgId: String, userId: String) async throws {
        let edgeId = "\(userId)_follows_\(orgId)"
        try await db
            .collection("edges")
            .document(edgeId)
            .updateData([
                "isDeleted": true,
                "deletedAt": FieldValue.serverTimestamp()
            ])
    }

    // MARK: - Announcements

    /// Loads the most recent 20 non-deleted announcements for an org.
    /// `audienceType` filtering is applied server-side via Firestore rules.
    func loadAnnouncements(orgId: String) async throws {
        let snapshot = try await db
            .collection("organizations")
            .document(orgId)
            .collection("announcements")
            .whereField("isDeleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .limit(to: 20)
            .getDocuments()

        announcements = snapshot.documents.compactMap { doc in
            try? decodeAnnouncement(from: doc.data(), id: doc.documentID)
        }
    }

    /// Posts a new announcement for an org.
    /// - Returns: Firestore document ID of the new announcement.
    /// Server-side RBAC (C5) enforces that only owner/executiveAdmin/pastor can write.
    func postAnnouncement(
        orgId: String,
        title: String,
        body: String,
        audience: String,
        authorId: String
    ) async throws -> String {
        let ref = db
            .collection("organizations")
            .document(orgId)
            .collection("announcements")
            .document()

        let data: [String: Any] = [
            "id": ref.documentID,
            "orgId": orgId,
            "title": title,
            "body": body,
            "authorId": authorId,
            "audienceType": audience,
            "isPinned": false,
            "createdAt": FieldValue.serverTimestamp(),
            "isDeleted": false
        ]

        try await ref.setData(data)
        return ref.documentID
    }

    // MARK: - Followed Orgs

    /// Loads all orgs the user follows via their edge documents.
    func loadFollowedOrgs(userId: String) async throws {
        let snapshot = try await db
            .collection("edges")
            .whereField("fromRef", isEqualTo: "users/\(userId)")
            .whereField("toType", isEqualTo: "organization")
            .whereField("edgeType", isEqualTo: "follows")
            .whereField("isDeleted", isEqualTo: false)
            .limit(to: 50)
            .getDocuments()

        let orgIds = snapshot.documents.compactMap { doc -> String? in
            guard let toRef = doc.data()["toRef"] as? String else { return nil }
            // toRef format: "organizations/{orgId}"
            let parts = toRef.split(separator: "/")
            return parts.count == 2 ? String(parts[1]) : nil
        }

        guard !orgIds.isEmpty else {
            followedOrgs = []
            return
        }

        // Batch fetch — Firestore `in` supports up to 30 items
        let batchIds = Array(orgIds.prefix(30))
        let orgSnapshot = try await db
            .collection("organizations")
            .whereField(FieldPath.documentID(), in: batchIds)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        followedOrgs = orgSnapshot.documents.compactMap { doc in
            try? decodeOrg(from: doc.data(), id: doc.documentID)
        }
    }

    // MARK: - Update Profile (admin-only)

    /// Persists profile changes for an org.
    /// RBAC is enforced server-side — this call will fail at Firestore rules
    /// if the current user is not owner/executiveAdmin/pastor for this org.
    func updateOrgProfile(_ org: AmenOrganization) async throws {
        var data: [String: Any] = [
            "name": org.name,
            "bio": org.bio,
            "type": org.type.rawValue,
            "website": org.website as Any,
            "tagline": org.tagline as Any,
            "missionStatement": org.missionStatement as Any,
            "foundedYear": org.foundedYear as Any,
            "location": org.location as Any,
            "logoUrl": org.logoUrl as Any,
            "coverImageUrl": org.coverImageUrl as Any,
            "socialLinks": org.socialLinks,
            "givingEnabled": org.givingEnabled,
            "isActive": org.isActive,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        // Strip nil values so we don't overwrite existing Firestore fields with null
        data = data.compactMapValues { value -> Any? in
            if case Optional<Any>.none = value { return nil }
            return value
        }

        try await db
            .collection("organizations")
            .document(org.id)
            .updateData(data)
    }

    // MARK: - Search

    /// Full-text search is handled by the `searchOrgs` Cloud Function.
    /// Returns a list of matching AmenOrganizations.
    func searchOrgs(query: String, type: OrgType?) async throws -> [AmenOrganization] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        var payload: [String: Any] = ["query": query]
        if let orgType = type {
            payload["type"] = orgType.rawValue
        }

        let result = try await functions
            .httpsCallable("searchOrgs")
            .call(payload)

        guard let responseData = result.data as? [String: Any],
              let items = responseData["organizations"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { dict in
            guard let id = dict["id"] as? String else { return nil }
            return try? decodeOrg(from: dict, id: id)
        }
    }

    // MARK: - Verification Request

    /// Writes a verification request to Firestore `/verificationRequests/`.
    /// The admin panel reviews pending requests; iOS only submits the queue entry.
    func requestVerification(
        orgId: String,
        documentRef: String,
        requesterId: String
    ) async throws {
        let ref = db.collection("verificationRequests").document()

        let data: [String: Any] = [
            "id": ref.documentID,
            "orgId": orgId,
            "requesterId": requesterId,
            "documentRef": documentRef,
            "submittedAt": FieldValue.serverTimestamp(),
            "status": "pending"
        ]

        try await ref.setData(data)
    }

    // MARK: - Decoding Helpers

    private func decodeOrg(from data: [String: Any], id: String) throws -> AmenOrganization {
        guard let name = data["name"] as? String,
              let typeRaw = data["type"] as? String,
              let orgType = OrgType(rawValue: typeRaw) else {
            throw OrgServiceError.decodingFailed(id)
        }

        let verificationStatusRaw = data["verificationStatus"] as? String ?? "unverified"
        let verificationStatus = OrgVerificationStatus(rawValue: verificationStatusRaw) ?? .unverified

        return AmenOrganization(
            id: id,
            name: name,
            type: orgType,
            tagline: data["tagline"] as? String,
            bio: data["bio"] as? String ?? "",
            coverImageUrl: data["coverImageUrl"] as? String,
            logoUrl: data["logoUrl"] as? String,
            website: data["website"] as? String,
            contactEmail: nil,       // never decoded on client
            socialLinks: data["socialLinks"] as? [String: String] ?? [:],
            verificationStatus: verificationStatus,
            verificationBadge: data["verificationBadge"] as? String,
            isNonprofit: data["isNonprofit"] as? Bool ?? false,
            ein: nil,                // never decoded on client
            kycStatus: data["kycStatus"] as? String ?? "pending",
            missionStatement: data["missionStatement"] as? String,
            foundedYear: data["foundedYear"] as? Int,
            location: data["location"] as? String,
            memberCount: 0,          // never surfaced publicly
            givingEnabled: data["givingEnabled"] as? Bool ?? false,
            broadcastEnabled: data["broadcastEnabled"] as? Bool ?? false,
            orgAssistantEnabled: data["orgAssistantEnabled"] as? Bool ?? false,
            planTier: data["planTier"] as? String ?? "free",
            adminIds: data["adminIds"] as? [String] ?? [],
            createdBy: data["createdBy"] as? String ?? "",
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            isDeleted: data["isDeleted"] as? Bool ?? false,
            isActive: data["isActive"] as? Bool ?? true
        )
    }

    private func decodeAnnouncement(from data: [String: Any], id: String) throws -> AmenOrgAnnouncement {
        guard let orgId = data["orgId"] as? String,
              let title = data["title"] as? String,
              let body = data["body"] as? String,
              let authorId = data["authorId"] as? String else {
            throw OrgServiceError.decodingFailed(id)
        }

        return AmenOrgAnnouncement(
            id: id,
            orgId: orgId,
            title: title,
            body: body,
            authorId: authorId,
            audienceType: data["audienceType"] as? String ?? "all",
            isPinned: data["isPinned"] as? Bool ?? false,
            expiresAt: (data["expiresAt"] as? Timestamp)?.dateValue(),
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            isDeleted: data["isDeleted"] as? Bool ?? false
        )
    }
}

// MARK: - OrgServiceError

enum OrgServiceError: LocalizedError {
    case notFound(String)
    case decodingFailed(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notFound(let id):       return "Organization '\(id)' not found."
        case .decodingFailed(let id): return "Failed to decode organization '\(id)'."
        case .unauthorized:           return "You do not have permission to perform this action."
        }
    }
}
