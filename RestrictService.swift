//
//  RestrictService.swift
//  AMENAPP
//
//  Restrict/Limit feature: restricted users' comments are only visible to themselves
//  (and the post author). Restricted users are NOT notified they've been restricted.
//
//  Storage: users/{currentUid} field "restrictedUsers: [String]"
//

import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

@MainActor
@Observable
final class RestrictService {

    static let shared = RestrictService()
    private init() {}

    // MARK: - State

    private(set) var restrictedUserIds: Set<String> = []
    private var isLoaded = false
    private let db = Firestore.firestore()

    // MARK: - Load

    func loadIfNeeded() async {
        guard !isLoaded, let uid = Auth.auth().currentUser?.uid else { return }
        isLoaded = true
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let ids = doc.data()?["restrictedUsers"] as? [String] ?? []
            restrictedUserIds = Set(ids)
        } catch {
            dlog("⚠️ [RestrictService] Load failed: \(error)")
        }
    }

    // MARK: - Public API

    func isRestricted(_ userId: String) -> Bool {
        restrictedUserIds.contains(userId)
    }

    func restrictUser(_ userId: String) async {
        guard !isRestricted(userId),
              let uid = Auth.auth().currentUser?.uid,
              uid != userId else { return }
        restrictedUserIds.insert(userId)
        await persist(uid: uid)
    }

    func unrestrictUser(_ userId: String) async {
        guard isRestricted(userId),
              let uid = Auth.auth().currentUser?.uid else { return }
        restrictedUserIds.remove(userId)
        await persist(uid: uid)
    }

    func toggleRestrict(_ userId: String) async {
        if isRestricted(userId) {
            await unrestrictUser(userId)
        } else {
            await restrictUser(userId)
        }
    }

    // MARK: - Comment Visibility

    /// Returns true if a comment from `authorId` should be visible to `viewerId`.
    /// A restricted user's comment is hidden from everyone EXCEPT themselves and the post author.
    func commentIsVisible(authorId: String, viewerId: String, postAuthorId: String) -> Bool {
        guard isRestricted(authorId) else { return true }
        // The comment is only visible to the commenter themselves and the post author
        return viewerId == authorId || viewerId == postAuthorId
    }

    // MARK: - Private

    private func persist(uid: String) async {
        do {
            try await db.collection("users").document(uid).updateData([
                "restrictedUsers": Array(restrictedUserIds)
            ])
        } catch {
            dlog("⚠️ [RestrictService] Save failed: \(error)")
        }
    }
}
