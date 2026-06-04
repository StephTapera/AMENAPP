// BereanProjectService.swift
// AMENAPP — Berean OS
//
// CRUD + Firestore syncing for the user's Berean OS projects.

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class BereanProjectService: ObservableObject {
    static let shared = BereanProjectService()

    @Published private(set) var projects: [BereanProject] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private init() {}

    // MARK: - Fetch

    func fetchProjects() async throws {
        guard AMENFeatureFlags.shared.bereanOSProjectsEnabled else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        isLoading = true
        defer { isLoading = false }

        let snapshot = try await db
            .collection(BereanOSFirestore.projects(uid: uid))
            .order(by: "updatedAt", descending: true)
            .getDocuments()

        projects = snapshot.documents.compactMap { doc in
            let data = doc.data()
            return BereanProject(
                id: doc.documentID,
                title: data["title"] as? String ?? "Untitled",
                description: data["description"] as? String ?? "",
                status: BereanProjectStatus(rawValue: data["status"] as? String ?? "") ?? .active,
                visibility: BereanProjectVisibility(rawValue: data["visibility"] as? String ?? "") ?? .private,
                ownerUid: data["ownerUid"] as? String ?? uid,
                tags: data["tags"] as? [String] ?? [],
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
            )
        }
    }

    // MARK: - Create

    @discardableResult
    func createProject(title: String, description: String) async throws -> BereanProject {
        guard AMENFeatureFlags.shared.bereanOSProjectsEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanOSError.unauthorized
        }

        let id = db.collection(BereanOSFirestore.projects(uid: uid)).document().documentID
        let now = Date()
        let project = BereanProject(
            id: id,
            title: title,
            description: description,
            status: .active,
            visibility: .private,
            ownerUid: uid,
            tags: [],
            createdAt: now,
            updatedAt: now
        )

        let data: [String: Any] = [
            "id": id,
            "title": title,
            "description": description,
            "status": BereanProjectStatus.active.rawValue,
            "visibility": BereanProjectVisibility.private.rawValue,
            "ownerUid": uid,
            "tags": [String](),
            "createdAt": Timestamp(date: now),
            "updatedAt": Timestamp(date: now)
        ]

        try await db
            .document(BereanOSFirestore.project(uid: uid, projectId: id))
            .setData(data)

        projects.insert(project, at: 0)
        return project
    }

    // MARK: - Delete

    func deleteProject(_ project: BereanProject) async throws {
        guard AMENFeatureFlags.shared.bereanOSProjectsEnabled else {
            throw BereanOSError.featureDisabled
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw BereanOSError.unauthorized
        }

        try await db
            .document(BereanOSFirestore.project(uid: uid, projectId: project.id))
            .delete()

        projects.removeAll { $0.id == project.id }
    }
}
