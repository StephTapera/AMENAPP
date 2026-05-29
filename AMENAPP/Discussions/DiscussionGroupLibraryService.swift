// DiscussionGroupLibraryService.swift
// AMENAPP — Discussions
//
// Manages a user's "added groups" library: groups saved for later without joining.
// Firestore path: userGroupLibrary/{uid}/addedGroups/{groupId}
//
// This is the "+" button concept from Apple Music — add to your library
// without playing/joining immediately.

import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct AddedGroup: Identifiable, Codable {
    var id: String            // groupId
    var groupName: String
    var groupCategory: String
    var coverImageURL: String?
    var memberCount: Int
    var isPrivate: Bool
    var addedAt: Date
    var notificationsEnabled: Bool
    var isJoined: Bool        // true if the user also participates in the group
}

// MARK: - Service

@MainActor
final class DiscussionGroupLibraryService: ObservableObject {

    static let shared = DiscussionGroupLibraryService()

    @Published private(set) var addedGroups: [AddedGroup] = []
    @Published private(set) var isLoading = false

    private var db: Firestore { Firestore.firestore() }
    private var currentUid: String? { Auth.auth().currentUser?.uid }
    private var listener: ListenerRegistration?

    private init() {}

    // MARK: - Real-time listener

    func startListening() {
        guard let uid = currentUid else { return }
        let ref = db.collection("userGroupLibrary").document(uid).collection("addedGroups")
        listener = ref
            .order(by: "addedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let docs = snapshot?.documents else { return }
                self.addedGroups = docs.compactMap { try? $0.data(as: AddedGroup.self) }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Mutations

    func addGroup(_ group: CommunityGroup) async throws {
        guard let uid = currentUid else { return }
        let entry = AddedGroup(
            id: group.id,
            groupName: group.name,
            groupCategory: group.category.rawValue,
            coverImageURL: group.coverImageURL,
            memberCount: group.memberCount,
            isPrivate: group.isPrivate,
            addedAt: Date(),
            notificationsEnabled: true,
            isJoined: false
        )
        let ref = db.collection("userGroupLibrary").document(uid)
            .collection("addedGroups").document(group.id)
        try ref.setData(from: entry)
    }

    func removeGroup(groupId: String) async throws {
        guard let uid = currentUid else { return }
        try await db.collection("userGroupLibrary").document(uid)
            .collection("addedGroups").document(groupId).delete()
    }

    func setNotifications(groupId: String, enabled: Bool) async throws {
        guard let uid = currentUid else { return }
        try await db.collection("userGroupLibrary").document(uid)
            .collection("addedGroups").document(groupId)
            .updateData(["notificationsEnabled": enabled])
    }

    func markJoined(groupId: String) async throws {
        guard let uid = currentUid else { return }
        try await db.collection("userGroupLibrary").document(uid)
            .collection("addedGroups").document(groupId)
            .updateData(["isJoined": true])
    }

    // MARK: - Convenience

    func isAdded(groupId: String) -> Bool {
        addedGroups.contains { $0.id == groupId }
    }

    func notificationsEnabled(for groupId: String) -> Bool {
        addedGroups.first { $0.id == groupId }?.notificationsEnabled ?? false
    }
}
