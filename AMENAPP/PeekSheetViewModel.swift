// PeekSheetViewModel.swift
// AMENAPP
//
// ViewModel for the mini profile peek sheet shown when tapping a suggestion card.
// Loads user doc, 2 recent posts, follow state, and mutual context from Firestore.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class PeekSheetViewModel: ObservableObject {

    // MARK: - Published State

    @Published var displayName: String = ""
    @Published var handle: String = ""
    @Published var avatarURL: String?
    @Published var bio: String?
    @Published var isVerified: Bool = false
    @Published var isPrivateAccount: Bool = false
    @Published var followerCount: Int = 0
    @Published var postCount: Int = 0
    @Published var sharedTopics: [String] = []
    @Published var prayerThemes: [String] = []
    @Published var accountType: SuggestionAccountType = .personal

    @Published var followState: FollowStateManager.FollowState = .notFollowing
    @Published var isLoadingFollow: Bool = false

    @Published var mutualSignals: [ContextSignal] = []
    /// Lightweight post preview for the peek sheet.
    struct PostPreview: Identifiable {
        let id: String
        let content: String
        let createdAt: Date
    }

    @Published var recentPosts: [PostPreview] = []

    @Published var isLoading: Bool = true
    @Published var hasError: Bool = false

    let userId: String
    let surface: SuggestionSurface

    private lazy var db = Firestore.firestore()

    // MARK: - Init

    init(userId: String, surface: SuggestionSurface) {
        self.userId = userId
        self.surface = surface
    }

    /// Pre-populate from the SuggestionItem to avoid a blank flash.
    func prepopulate(from item: SuggestionItem) {
        displayName = item.displayName
        handle = item.handle
        avatarURL = item.avatarURL
        isVerified = item.isVerified
        isPrivateAccount = item.isPrivate
        accountType = item.accountType
        bio = item.bio
        followerCount = item.followerCount
        postCount = item.postCount
        sharedTopics = item.sharedTopics
        prayerThemes = item.prayerThemes
    }

    // MARK: - Load Full Data

    func load() async {
        isLoading = true
        hasError = false

        async let userTask: () = loadUserProfile()
        async let followTask: () = loadFollowState()
        async let mutualTask: () = loadMutualContext()
        async let postsTask: () = loadRecentPosts()

        _ = await (userTask, followTask, mutualTask, postsTask)

        isLoading = false
    }

    private func loadUserProfile() async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard doc.exists, let data = doc.data() else {
                hasError = true
                return
            }

            displayName = data["displayName"] as? String ?? data["username"] as? String ?? displayName
            handle = data["username"] as? String ?? handle
            avatarURL = data["profileImageURL"] as? String ?? data["photoURL"] as? String ?? avatarURL
            bio = data["bio"] as? String ?? bio
            isVerified = data["isVerified"] as? Bool ?? isVerified
            isPrivateAccount = data["isPrivate"] as? Bool ?? isPrivateAccount
            followerCount = data["followersCount"] as? Int ?? followerCount
            postCount = data["postsCount"] as? Int ?? postCount
            accountType = SuggestionAccountType(rawValue: data["accountType"] as? String ?? "personal") ?? accountType
            sharedTopics = data["interests"] as? [String] ?? sharedTopics
            prayerThemes = data["prayerTopics"] as? [String] ?? prayerThemes
        } catch {
            dlog("⚠️ PeekSheet: user profile load failed: \(error.localizedDescription)")
            hasError = true
        }
    }

    private func loadFollowState() async {
        followState = await FollowStateManager.shared.getState(for: userId)
    }

    private func loadMutualContext() async {
        mutualSignals = await MutualContextService.shared.fetchContextSignals(profileUID: userId)
    }

    private func loadRecentPosts() async {
        guard !isPrivateAccount else { return }
        do {
            let snap = try await db.collection("posts")
                .whereField("authorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 2)
                .getDocuments()

            recentPosts = snap.documents.compactMap { doc -> PostPreview? in
                let data = doc.data()
                guard let content = data["content"] as? String, !content.isEmpty else { return nil }
                let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                return PostPreview(id: doc.documentID, content: content, createdAt: ts)
            }
        } catch {
            dlog("⚠️ PeekSheet: recent posts load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Follow Actions

    func follow() async {
        isLoadingFollow = true
        let isPrivate = isPrivateAccount
        followState = isPrivate ? .requested : .following

        do {
            try await FollowService.shared.followUser(userId: userId)
            let newState: FollowStateManager.FollowState = isPrivate ? .requested : .following
            FollowStateManager.shared.updateState(for: userId, state: newState)
            followState = newState
        } catch {
            followState = .notFollowing
            dlog("❌ PeekSheet follow failed: \(error.localizedDescription)")
        }

        isLoadingFollow = false
    }

    func cancelRequest() async {
        followState = .notFollowing
        guard let currentUID = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await db.collection("followRequests")
                .whereField("fromUserId", isEqualTo: currentUID)
                .whereField("toUserId", isEqualTo: userId)
                .whereField("status", isEqualTo: "pending")
                .limit(to: 1)
                .getDocuments()
            for doc in snap.documents {
                try await doc.reference.delete()
            }
            FollowStateManager.shared.updateState(for: userId, state: .notFollowing)
        } catch {
            followState = .requested
        }
    }

    func unfollow() async {
        let prev = followState
        followState = .notFollowing
        do {
            try await FollowService.shared.unfollowUser(userId: userId)
            FollowStateManager.shared.updateState(for: userId, state: .notFollowing)
        } catch {
            followState = prev
        }
    }
}
