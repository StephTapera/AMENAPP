// WorkspaceViewModel.swift
// AMENAPP — Cadence Workspace view model

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - WorkspaceActivity (view-model only — not Firestore-backed)
// TODO: Replace hardcoded sample items with real-time reads from
//       per-workspace activity subcollections once those are wired up.

struct WorkspaceActivity: Identifiable {
    let id: String
    let platform: String   // "kora" | "verge" | "helix"
    let icon: String       // SF Symbol name
    let description: String
    let timestamp: Date
}

// MARK: - WorkspaceViewModel

@MainActor
class WorkspaceViewModel: ObservableObject {

    // MARK: Published state

    @Published var workspaces: [Workspace] = []
    @Published var currentWorkspace: Workspace?
    @Published var isLoading: Bool = false
    @Published var recentActivity: [WorkspaceActivity] = []

    // MARK: Private

    private let db = Firestore.firestore()
    private let currentWorkspaceKey = "cadence_current_workspace_id"

    // MARK: Init

    init() {
        loadSampleActivity()
    }

    // MARK: - Load workspaces

    func loadWorkspaces() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await db
                .collection("workspaces")
                .whereField("memberIds", arrayContains: uid)
                .getDocuments()

            let fetched = snapshot.documents.compactMap {
                try? $0.data(as: Workspace.self)
            }
            workspaces = fetched

            // Restore previously selected workspace from UserDefaults
            let savedId = UserDefaults.standard.string(forKey: currentWorkspaceKey)
            if let savedId, let match = fetched.first(where: { $0.id == savedId }) {
                currentWorkspace = match
            } else {
                currentWorkspace = fetched.first
            }
        } catch {
            print("[WorkspaceViewModel] loadWorkspaces error: \(error.localizedDescription)")
        }
    }

    // MARK: - Create workspace

    @discardableResult
    func createWorkspace(name: String, description: String) async throws -> Workspace {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw URLError(.userAuthenticationRequired)
        }

        let newWorkspace = Workspace(
            id: nil,
            name: name,
            description: description,
            logoURL: nil,
            ownerId: uid,
            memberIds: [uid],
            enabledPlatforms: ["kora", "verge", "helix"],
            plan: "free",
            createdAt: Date(),
            memberCount: 1
        )

        let ref = try db.collection("workspaces").addDocument(from: newWorkspace)

        // Build the saved copy with the newly assigned Firestore id
        var saved = newWorkspace
        // Re-fetch so @DocumentID is populated
        let doc = try await ref.getDocument(as: Workspace.self)
        workspaces.append(doc)
        selectWorkspace(doc)
        return doc
    }

    // MARK: - Select workspace

    func selectWorkspace(_ workspace: Workspace) {
        currentWorkspace = workspace
        if let id = workspace.id {
            UserDefaults.standard.set(id, forKey: currentWorkspaceKey)
        }
    }

    // MARK: - Sample activity (hardcoded until subcollection listener is wired)

    private func loadSampleActivity() {
        let now = Date()
        recentActivity = [
            WorkspaceActivity(
                id: "act-1",
                platform: "kora",
                icon: "hands.sparkles.fill",
                description: "Morning Check-In completed by 6 members",
                timestamp: now.addingTimeInterval(-300)        // 5 min ago
            ),
            WorkspaceActivity(
                id: "act-2",
                platform: "verge",
                icon: "video.fill",
                description: "\"Faith & Work\" room went live",
                timestamp: now.addingTimeInterval(-900)        // 15 min ago
            ),
            WorkspaceActivity(
                id: "act-3",
                platform: "helix",
                icon: "wand.and.stars.inverse",
                description: "Weekly prayer digest workflow ran successfully",
                timestamp: now.addingTimeInterval(-3600)       // 1 hr ago
            ),
            WorkspaceActivity(
                id: "act-4",
                platform: "kora",
                icon: "book.fill",
                description: "Sarah shared a journal entry with the Circle",
                timestamp: now.addingTimeInterval(-7200)       // 2 hrs ago
            ),
            WorkspaceActivity(
                id: "act-5",
                platform: "verge",
                icon: "star.fill",
                description: "3 new subscribers joined Marcus's channel",
                timestamp: now.addingTimeInterval(-14400)      // 4 hrs ago
            )
        ]
    }
}
