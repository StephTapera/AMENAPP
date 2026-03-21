//
//  ProfileFeedViewModel.swift
//  AMENAPP
//
//  Manages the pinned post slot on a user profile.
//  Spring-animates pin/unpin transitions.
//

import SwiftUI
import Combine
import FirebaseFirestore

@MainActor
final class ProfileFeedViewModel: ObservableObject {

    @Published var pinnedPost: Post? = nil
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?

    // MARK: - Lifecycle

    func load(uid: String) {
        guard !uid.isEmpty else { return }
        userListener?.remove()
        isLoading = true

        userListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                guard error == nil, let data = snap?.data() else {
                    self.pinnedPost = nil
                    self.isLoading = false
                    return
                }

                guard let pinnedPostId = data["pinnedPostId"] as? String, !pinnedPostId.isEmpty else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                        self.pinnedPost = nil
                    }
                    self.isLoading = false
                    return
                }

                Task { await self.fetchPost(id: pinnedPostId) }
            }
    }

    func stopListening() {
        userListener?.remove()
        userListener = nil
    }

    // MARK: - Pin / Unpin

    func pinPost(_ post: Post) async {
        guard let postId = post.firebaseId else { return }
        do {
            try await PinnedPostService.shared.pinPost(postId: postId)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                pinnedPost = post
            }
        } catch {
            dlog("❌ ProfileFeedViewModel.pinPost: \(error)")
        }
    }

    func unpinCurrent() async {
        guard let post = pinnedPost, let postId = post.firebaseId else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            pinnedPost = nil
        }
        do {
            try? await Task.sleep(nanoseconds: 180_000_000)
            try await PinnedPostService.shared.unpinPost(postId: postId)
        } catch {
            dlog("❌ ProfileFeedViewModel.unpinCurrent: \(error)")
        }
    }

    // MARK: - Private

    private func fetchPost(id: String) async {
        do {
            let doc = try await db.collection("posts").document(id).getDocument()
            guard doc.exists else {
                pinnedPost = nil
                isLoading = false
                return
            }
            let post = try doc.data(as: Post.self)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                self.pinnedPost = post
            }
        } catch {
            dlog("❌ ProfileFeedViewModel.fetchPost: \(error)")
            pinnedPost = nil
        }
        isLoading = false
    }
}
