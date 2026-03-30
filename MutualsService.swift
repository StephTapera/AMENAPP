//
//  MutualsService.swift
//  AMENAPP
//
//  Computes mutual connections between the current viewer and a profile owner.
//  "Mutuals" = people that BOTH the viewer and the profile owner follow.
//
//  Strategy (avoids double query for viewer):
//  1. Viewer's following comes from FollowService.shared.following (already in memory).
//  2. Profile owner's following is queried from Firestore.
//  3. Intersect both sets client-side.
//  4. Fetch display profiles for the top 20 intersected UIDs, return max 8.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

final class MutualsService {

    static let shared = MutualsService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Public

    /// Fetch up to `limit` mutual connections between the viewer and `profileUID`.
    /// Returns an empty array when: viewer is unauthenticated, viewing own profile,
    /// or no mutuals exist.
    func fetchMutuals(profileUID: String, limit: Int = 8) async -> [MutualConnection] {
        guard let viewerUID = Auth.auth().currentUser?.uid,
              viewerUID != profileUID else { return [] }

        // 1. Viewer's following (already cached by FollowService)
        let viewerFollowing = await MainActor.run { FollowService.shared.following }
        guard !viewerFollowing.isEmpty else { return [] }

        // 2. Profile owner's following via Firestore
        let ownerFollowing = await fetchFollowingIds(uid: profileUID)
        guard !ownerFollowing.isEmpty else { return [] }

        // 3. Intersect — cap fetch at 20 to keep Firestore reads bounded
        let intersection = Array(viewerFollowing.intersection(ownerFollowing)).prefix(20)
        guard !intersection.isEmpty else { return [] }

        // 4. Fetch display profiles and return top `limit`
        let profiles = await fetchProfiles(uids: Array(intersection))
        return Array(profiles.prefix(limit))
    }

    // MARK: - Private helpers

    private func fetchFollowingIds(uid: String) async -> Set<String> {
        do {
            let snapshot = try await db
                .collection(FirebaseManager.CollectionPath.follows)
                .whereField("followerId", isEqualTo: uid)
                .getDocuments()

            let ids = snapshot.documents.compactMap { $0.data()["followingId"] as? String }
            return Set(ids)
        } catch {
            dlog("⚠️ MutualsService: failed to fetch following for \(uid): \(error)")
            return []
        }
    }

    private func fetchProfiles(uids: [String]) async -> [MutualConnection] {
        guard !uids.isEmpty else { return [] }

        // Firestore `whereField in:` supports up to 30 items
        do {
            let snapshot = try await db
                .collection(FirebaseManager.CollectionPath.users)
                .whereField(FieldPath.documentID(), in: uids)
                .getDocuments()

            return snapshot.documents.compactMap { doc -> MutualConnection? in
                let data = doc.data()
                guard let displayName = data["displayName"] as? String else { return nil }
                let username = data["username"] as? String ?? ""
                let photoURLString = data["profileImageURL"] as? String
                let photoURL = photoURLString.flatMap { URL(string: $0) }
                return MutualConnection(
                    id: doc.documentID,
                    displayName: displayName,
                    username: username,
                    profilePhotoURL: photoURL
                )
            }
        } catch {
            dlog("⚠️ MutualsService: failed to fetch profiles: \(error)")
            return []
        }
    }
}
