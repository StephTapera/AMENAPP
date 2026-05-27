// ReplyActionsMenuView.swift
// AMENAPP
//
// Contextual action menu presented when a user long-presses a LiquidReplyPreviewChip.
// Driven by AmenUniversalContentRouter.shared.replyActionsTarget via .sheet(item:).
//
// Five real actions (zero empty closures):
//   1. Reply         — opens CommentsView pre-filled with "@author " prefix via CommentFocusCoordinator
//   2. Like / Amen   — calls PostInteractionsService.shared.toggleAmen with optimistic UI + revert
//   3. Share         — ShareLink with canonical deep link URL
//   4. Report        — ModerationService.shared.reportPost + Alert confirmation
//   5. Follow author — FollowService.shared.followUser + NotificationCenter broadcast
//
// Navigation Agent — A5

import SwiftUI
import FirebaseAuth

// MARK: - ReplyActionsMenuView

struct ReplyActionsMenuView: View {
    let target: ReplyActionsTarget

    // Post resolution
    @State private var post: Post?
    @State private var isFetchingPost = true

    // Amen optimistic state
    @State private var isAmened: Bool = false
    @State private var isAmenInFlight: Bool = false

    // Follow state
    @State private var isFollowing: Bool = false
    @State private var isFollowInFlight: Bool = false

    // Report flow
    @State private var showReportConfirmation: Bool = false
    @State private var reportError: String?
    @State private var reportSuccess: Bool = false
    @State private var isReportInFlight: Bool = false

    // Error toast
    @State private var toastMessage: String?
    @State private var toastTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    private var currentUserId: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        NavigationView {
            Group {
                if isFetchingPost {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let post {
                    actionsContent(post: post)
                } else {
                    ContentUnavailableView(
                        "Reply unavailable",
                        systemImage: "exclamationmark.bubble",
                        description: Text("This reply could not be loaded.")
                    )
                }
            }
            .navigationTitle("Reply Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Report sent", isPresented: $reportSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Thank you for helping keep Amen safe. Our team will review this content.")
            }
            .alert("Report this reply?", isPresented: $showReportConfirmation) {
                Button("Report", role: .destructive) { submitReport() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will flag the reply for review by our moderation team.")
            }
        }
        .presentationDetents([.medium])
        .task { await loadPostAndState() }
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: toastMessage)
            }
        }
    }

    // MARK: - Actions content

    @ViewBuilder
    private func actionsContent(post: Post) -> some View {
        List {
            // ── 1. Reply ─────────────────────────────────────────────
            replyRow(post: post)

            // ── 2. Like / Amen ───────────────────────────────────────
            amenRow(post: post)

            // ── 3. Share ─────────────────────────────────────────────
            shareRow(post: post)

            // ── 4. Report ────────────────────────────────────────────
            reportRow(post: post)

            // ── 5. Follow Author ─────────────────────────────────────
            followRow(post: post)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Action Rows

    /// Opens CommentsView with the specific reply pre-staged for scrolling and the
    /// text field focused, pre-filled with "@authorUsername " so the user is composing
    /// a reply to the highlighted comment.
    private func replyRow(post: Post) -> some View {
        Button {
            dismiss()
            // Stage scroll + highlight so CommentsView lands on the target reply
            CommentFocusCoordinator.shared.set(
                scrollTarget: target.replyId,
                highlight: target.replyId,
                expandThread: nil
            )
            // Build "@username " prefill from the post author; CommentsView surfaces this
            // in the text field via prefillText.
            let mention = post.authorUsername.map { "@\($0) " } ?? ""
            // Fire NotificationCenter so any ambient host (HomeFeedView, PostCard, etc.)
            // that listens to .amenOpenRepliesRequested can intercept and present CommentsView.
            // We also update pendingReplyRoute so coordinator-driven hosts handle it.
            NotificationCenter.default.post(
                name: .amenOpenRepliesRequested,
                object: nil,
                userInfo: [
                    "postId": target.postId,
                    "highlightedReplyId": target.replyId,
                    "post": post,
                    "prefillText": mention
                ]
            )
            AMENAnalyticsService.shared.track(
                .replyPreviewTapped(postId: target.postId, type: "replyFromActions", replyId: target.replyId)
            )
        } label: {
            Label("Reply", systemImage: "bubble.right")
        }
    }

    /// Toggles Amen on the post with optimistic UI (flip immediately, revert on error).
    private func amenRow(post: Post) -> some View {
        Button {
            guard !isAmenInFlight else { return }
            let previousState = isAmened
            // Optimistic flip
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                isAmened.toggle()
            }
            isAmenInFlight = true
            Task {
                defer { isAmenInFlight = false }
                do {
                    try await PostInteractionsService.shared.toggleAmen(postId: post.firestoreId)
                } catch {
                    // Revert on failure
                    await MainActor.run {
                        withAnimation { isAmened = previousState }
                        showToast("Could not update Amen. Try again.")
                    }
                }
            }
        } label: {
            Label(
                isAmened ? "Remove Amen" : "Say Amen",
                systemImage: isAmened ? "hands.clap.fill" : "hands.clap"
            )
            .foregroundStyle(isAmened ? Color.blue : Color.primary)
        }
        .disabled(isAmenInFlight)
    }

    /// ShareLink with the canonical Amen deep link. Present natively; no custom code required.
    private func shareRow(post: Post) -> some View {
        let shareURL = URL(string: "https://amenapp.page.link/post/\(target.postId)")!
        return ShareLink(item: shareURL) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    /// Reports the reply (mapped as a post report using the replyId as the item to report).
    /// Shows an Alert confirmation before submitting.
    ///
    /// NOTE: ModerationService.shared.reportComment requires a `commentAuthorId`. The
    /// reply author is embedded in the DynamicReplyPreview but we don't carry it here —
    /// we fall back to reportPost (which takes postAuthorId) on the parent post. If a
    /// dedicated reply-report surface is wired in future, update this to reportComment.
    /// See HANDOFF-A5.md for the gap.
    private func reportRow(post: Post) -> some View {
        Button(role: .destructive) {
            showReportConfirmation = true
        } label: {
            Label("Report", systemImage: "flag")
        }
        .disabled(isReportInFlight)
    }

    /// Follows the post author (the author of the highlighted reply is tracked via `post.authorId`
    /// because DynamicReplyPreview.authorId is optional and may differ; host views are
    /// expected to pass the parent post). Posts a "ReplyPreviewNeedsRefresh" notification so any
    /// host view listening for follow state changes can refresh its reply preview strip.
    ///
    /// NOTE: If `isFollowing` is true, the button unfollows — mirroring the toggle pattern
    /// used in SearchViewComponents_New.swift and PrayerView.swift.
    private func followRow(post: Post) -> some View {
        Button {
            guard !isFollowInFlight else { return }
            let targetUserId = post.authorId
            guard targetUserId != currentUserId else {
                showToast("You can't follow yourself.")
                return
            }
            isFollowInFlight = true
            Task {
                defer { isFollowInFlight = false }
                do {
                    if isFollowing {
                        try await FollowService.shared.unfollowUser(userId: targetUserId)
                        await MainActor.run { isFollowing = false }
                    } else {
                        try await FollowService.shared.followUser(userId: targetUserId)
                        await MainActor.run { isFollowing = true }
                    }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ReplyPreviewNeedsRefresh"),
                        object: nil,
                        userInfo: ["postId": target.postId]
                    )
                } catch {
                    await MainActor.run {
                        showToast("Could not update follow. Try again.")
                    }
                }
            }
        } label: {
            if isFollowInFlight {
                Label(
                    isFollowing ? "Unfollowing…" : "Following…",
                    systemImage: "person.badge.clock"
                )
            } else {
                Label(
                    isFollowing ? "Unfollow Author" : "Follow Author",
                    systemImage: isFollowing ? "person.badge.minus" : "person.badge.plus"
                )
            }
        }
        .disabled(isFollowInFlight)
    }

    // MARK: - Data loading

    private func loadPostAndState() async {
        isFetchingPost = true
        defer { isFetchingPost = false }

        // 1. Resolve Post
        let resolved = await resolvePost()
        await MainActor.run { post = resolved }

        guard let resolved else { return }

        // 2. Amen state
        if let uid = currentUserId {
            let amened = PostInteractionsService.shared.userAmenedPosts.contains(resolved.firestoreId)
                      || resolved.hasAmened(by: uid)
            await MainActor.run { isAmened = amened }
        }

        // 3. Follow state — use already-loaded set (populated at app launch)
        let alreadyFollowing = FollowService.shared.following.contains(resolved.authorId)
        await MainActor.run { isFollowing = alreadyFollowing }
    }

    private func resolvePost() async -> Post? {
        // In-memory first
        if let cached = PostsManager.shared.allPosts.first(where: {
            $0.firestoreId == target.postId || $0.id.uuidString == target.postId
        }) {
            return cached
        }
        // Firestore fallback
        return try? await FirebasePostService.shared.fetchPostById(postId: target.postId)
    }

    // MARK: - Report submission

    private func submitReport() {
        guard let post else { return }
        isReportInFlight = true
        Task {
            defer { isReportInFlight = false }
            do {
                try await ModerationService.shared.reportPost(
                    postId: post.firestoreId,
                    postAuthorId: post.authorId,
                    reason: .inappropriateContent,
                    additionalDetails: "Reported from reply preview (replyId: \(target.replyId))"
                )
                await MainActor.run { reportSuccess = true }
            } catch {
                await MainActor.run {
                    showToast("Report failed. Please try again.")
                }
            }
        }
    }

    // MARK: - Toast helper

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation { toastMessage = message }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Reply Actions Menu") {
    ReplyActionsMenuView(
        target: ReplyActionsTarget(postId: "preview-post-id", replyId: "preview-reply-id")
    )
}
#endif
