// BereanSocialProjectService.swift
// AMENAPP — Berean OS
//
// Manages social publishing, contributors, and community actions
// for shared Berean OS projects.

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Errors

enum BereanSocialProjectError: LocalizedError {
    case featureDisabled
    case communityIntelligenceDisabled
    case notAuthenticated
    case projectNotFound

    var errorDescription: String? {
        switch self {
        case .featureDisabled:            return "Social Projects are not available yet."
        case .communityIntelligenceDisabled: return "Community Intelligence is not available yet."
        case .notAuthenticated:           return "You must be signed in to perform this action."
        case .projectNotFound:            return "The project could not be found."
        }
    }
}

// MARK: - Service

@MainActor
final class BereanSocialProjectService: ObservableObject {

    static let shared = BereanSocialProjectService()

    @Published private(set) var contributors: [BereanProjectContributor] = []
    @Published private(set) var communityActions: [BereanCommunityAction] = []

    private let db = Firestore.firestore()

    private init() {}

    // MARK: - Helpers

    private var currentUID: String {
        get throws {
            guard let uid = Auth.auth().currentUser?.uid else {
                throw BereanSocialProjectError.notAuthenticated
            }
            return uid
        }
    }

    private func requireSocialProjects() throws {
        guard AMENFeatureFlags.shared.bereanOSSocialProjectsEnabled else {
            throw BereanSocialProjectError.featureDisabled
        }
    }

    private func requireCommunityIntelligence() throws {
        guard AMENFeatureFlags.shared.bereanOSCommunityIntelligenceEnabled else {
            throw BereanSocialProjectError.communityIntelligenceDisabled
        }
    }

    // MARK: - Publish / Unpublish

    /// Copies the private project document to `bereanSocialProjects/{projectId}`
    /// and sets the requested visibility.
    func publishProject(_ projectId: String, visibility: BereanProjectVisibility) async throws {
        try requireSocialProjects()
        let uid = try currentUID

        let privatePath = BereanOSFirestore.project(uid: uid, projectId: projectId)
        let snapshot = try await db.document(privatePath).getDocument()

        guard snapshot.exists, var data = snapshot.data() else {
            throw BereanSocialProjectError.projectNotFound
        }

        data["visibility"] = visibility.rawValue
        data["publishedAt"] = FieldValue.serverTimestamp()
        data["publishedByUid"] = uid

        let publicPath = BereanOSFirestore.socialProject(projectId: projectId)
        try await db.document(publicPath).setData(data, merge: true)
    }

    /// Removes the document from `bereanSocialProjects/{projectId}`.
    func unpublishProject(_ projectId: String) async throws {
        try requireSocialProjects()

        let publicPath = BereanOSFirestore.socialProject(projectId: projectId)
        try await db.document(publicPath).delete()
    }

    // MARK: - Contributors

    func addContributor(
        projectId: String,
        userId: String,
        role: BereanContributorRole
    ) async throws {
        try requireSocialProjects()

        let contributor = BereanProjectContributor(
            id: userId,
            userId: userId,
            role: role,
            joinedAt: Date(),
            contributionCount: 0
        )
        let data = try Firestore.Encoder().encode(contributor)
        let path = BereanOSFirestore.socialProjectContributors(projectId: projectId)
        try await db.collection(path).document(userId).setData(data)
    }

    func removeContributor(projectId: String, userId: String) async throws {
        try requireSocialProjects()

        let path = BereanOSFirestore.socialProjectContributors(projectId: projectId)
        try await db.collection(path).document(userId).delete()
    }

    func fetchContributors(projectId: String) async throws {
        try requireSocialProjects()

        let path = BereanOSFirestore.socialProjectContributors(projectId: projectId)
        let snapshot = try await db.collection(path).getDocuments()
        contributors = try snapshot.documents.map { doc in
            try doc.data(as: BereanProjectContributor.self)
        }
    }

    // MARK: - Community Actions

    func recordCommunityAction(
        _ actionType: BereanCommunityActionType,
        content: String,
        projectId: String,
        targetEntryId: String
    ) async throws {
        try requireSocialProjects()
        try requireCommunityIntelligence()
        let uid = try currentUID

        let action = BereanCommunityAction(
            id: UUID().uuidString,
            actionType: actionType,
            userId: uid,
            content: content,
            targetEntryId: targetEntryId,
            timestamp: Date()
        )
        let data = try Firestore.Encoder().encode(action)
        let path = BereanOSFirestore.socialProjectCommunityActions(projectId: projectId)
        try await db.collection(path).addDocument(data: data)
    }

    func fetchCommunityActions(projectId: String, entryId: String) async throws {
        try requireSocialProjects()
        try requireCommunityIntelligence()

        let path = BereanOSFirestore.socialProjectCommunityActions(projectId: projectId)
        let snapshot = try await db.collection(path)
            .whereField("targetEntryId", isEqualTo: entryId)
            .order(by: "timestamp", descending: true)
            .getDocuments()
        communityActions = try snapshot.documents.map { doc in
            try doc.data(as: BereanCommunityAction.self)
        }
    }
}
