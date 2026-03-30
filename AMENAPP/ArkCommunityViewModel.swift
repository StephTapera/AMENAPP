// ArkCommunityViewModel.swift
// AMENAPP — Ark Protocol ViewModel

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - ArkCommunityViewModel

@MainActor
final class ArkCommunityViewModel: ObservableObject {

    // MARK: - Published State

    @Published var communities: [ArkCommunity] = []
    @Published var selectedCommunity: ArkCommunity?
    @Published var posts: [ArkPost] = []
    @Published var currentMember: ArkMember?
    @Published var isLoading = false
    @Published var isSubmittingPost = false
    @Published var moderationAlert: ModerationAlertInfo?
    @Published var errorMessage: String?

    // MARK: - Private

    private let service = ArkService.shared
    private var postsListener: ListenerRegistration?
    private var currentUserId: String? { Auth.auth().currentUser?.uid }

    deinit {
        postsListener?.remove()
    }

    // MARK: - Community List

    func loadCommunities() async {
        isLoading = true
        defer { isLoading = false }
        do {
            communities = try await service.fetchCommunities()
        } catch {
            errorMessage = "Couldn't load communities."
        }
    }

    // MARK: - Community Detail

    func selectCommunity(_ community: ArkCommunity) async {
        selectedCommunity = community
        guard let communityId = community.id,
              let uid = currentUserId else { return }

        async let memberResult = service.fetchMember(userId: uid, communityId: communityId)
        async let postsResult = service.fetchPosts(communityId: communityId)

        currentMember = try? await memberResult
        posts = (try? await postsResult) ?? []

        startPostsListener(communityId: communityId)
    }

    // MARK: - Real-time Posts Listener

    private func startPostsListener(communityId: String) {
        postsListener?.remove()
        postsListener = Firestore.firestore()
            .collection("arkCommunities")
            .document(communityId)
            .collection("posts")
            .whereField("aiModerationStatus", isEqualTo: "approved")
            .order(by: "createdAt", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                Task { @MainActor in
                    self.posts = snap.documents.compactMap { try? $0.data(as: ArkPost.self) }
                }
            }
    }

    // MARK: - Post Submission

    func submitPost(content: String, isAnonymous: Bool) async {
        guard let uid = currentUserId,
              let community = selectedCommunity,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        isSubmittingPost = true
        defer { isSubmittingPost = false }

        let post = ArkPost(
            id: nil,
            userId: uid,
            content: content,
            createdAt: Timestamp(date: Date()),
            aiModerationStatus: "pending_review",
            aiModerationReason: nil,
            aiCovenantViolations: nil,
            communityReports: 0,
            isAnonymous: isAnonymous
        )

        do {
            try await service.submitPost(post, community: community)
            // Posts listener will update the list automatically
        } catch {
            errorMessage = "Couldn't submit your post."
        }
    }

    // MARK: - Covenant Signing / Join

    func joinCommunity(_ community: ArkCommunity) async {
        guard let uid = currentUserId,
              let communityId = community.id else { return }

        let now = Timestamp(date: Date())
        let member = ArkMember(
            id: nil,
            userId: uid,
            joinedAt: now,
            covenantSignedAt: now,
            arkScore: 50.0,
            arkScoreBreakdown: .empty,
            warningCount: 0,
            lastWarningReason: nil,
            status: "active"
        )

        do {
            try await service.joinCommunity(member: member, communityId: communityId)
            currentMember = member
        } catch {
            errorMessage = "Couldn't join community. Please try again."
        }
    }

    // MARK: - Ark Score Events

    func recordEvent(_ event: ArkScoreEvent) {
        guard let uid = currentUserId,
              let communityId = selectedCommunity?.id else { return }
        Task {
            try? await service.updateArkScore(userId: uid, communityId: communityId, event: event)
            // Refresh member to show updated score
            currentMember = try? await service.fetchMember(userId: uid, communityId: communityId)
        }
    }
}

// MARK: - Moderation Alert Info

struct ModerationAlertInfo: Identifiable {
    var id = UUID()
    var status: String
    var graceNote: String
    var violations: [String]
}
