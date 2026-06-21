// SmartCommentsSheet.swift
// AMENAPP — Smart Comments Wave 1
//
// Entry point for comment display. When `smartCommentsEnabled` is OFF, delegates
// entirely to the existing CommentsView — zero regression for the current experience.
//
// When ON: floating bottom sheet with glass background, lazy comment list,
// pending-state awareness, and a sticky SmartCommentComposer at the bottom.
//
// INVARIANT: A blank screen is never shown. If the flag is OFF or if there is any
//            doubt about the ViewModel state, CommentsView is the fallback.

import SwiftUI
import Foundation
import FirebaseAuth

// MARK: - Entry Point

/// Drop-in replacement call site for the existing CommentsView.
/// Takes a postId (String) instead of a Post object — the sheet resolves data via
/// CommentService. When the flag is OFF, CommentsView(post:) is shown instead.
///
/// Usage at call site:
///   SmartCommentsSheet(postId: post.firestoreId, fallbackPost: post)
struct SmartCommentsSheet: View {

    let postId: String

    /// Passed through to CommentsView when the flag is OFF.
    /// Type-erased as AnyView to avoid importing Post at this layer.
    let fallbackView: AnyView

    // MARK: - Init Convenience

    /// Standard initializer. `fallbackPost` is the Post passed to CommentsView when
    /// smartCommentsEnabled is false — providing a clean fallback without blank screens.
    init<FallbackContent: View>(postId: String, @ViewBuilder fallback: () -> FallbackContent) {
        self.postId = postId
        self.fallbackView = AnyView(fallback())
    }

    // MARK: - Body

    var body: some View {
        if AMENFeatureFlags.shared.smartCommentsEnabled {
            SmartCommentsSheetContent(postId: postId)
        } else {
            fallbackView
        }
    }
}

// MARK: - Content (flag ON path)

private struct SmartCommentsSheetContent: View {

    let postId: String

    @StateObject private var viewModel: SmartCommentViewModel
    @Environment(\.dismiss) private var dismiss

    init(postId: String) {
        self.postId = postId
        _viewModel = StateObject(wrappedValue: SmartCommentViewModel(postId: postId))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Sheet background: ultraThinMaterial — correct for a floating sheet.
            sheetBackground

            VStack(spacing: 0) {
                // Drag indicator area + header
                headerView

                Divider()
                    .opacity(0.5)

                // Scrollable comment list
                commentScrollView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .opacity(0.3)

                // Sticky composer
                SmartCommentComposer(
                    onSubmit: { body in
                        await viewModel.submitComment(body: body)
                    },
                    isPosting: viewModel.isPosting
                )
                .padding(.bottom, safeAreaBottomPadding)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .task {
            await viewModel.loadComments()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        // Nudge sheet
        .sheet(isPresented: nudgeSheetBinding) {
            NudgeSheet(
                message: viewModel.nudgeSuggestion ?? "",
                onDismiss: { viewModel.dismissNudge() }
            )
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
        // Error alert
        .alert("Unable to post", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                viewModel.error = nil
            }
        } message: {
            Text(viewModel.error ?? "An error occurred. Please try again.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Comments")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                let count = visibleCount
                Text(count == 1 ? "1 comment" : "\(count) comments")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                            )
                    )
            }
            .accessibilityLabel("Close comments")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    // MARK: - Comment Scroll

    private var commentScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading {
                    skeletonView
                } else if allDisplayComments.isEmpty {
                    emptyStateView
                } else {
                    ForEach(allDisplayComments, id: \.id) { comment in
                        SmartCommentCard(
                            comment: comment,
                            isPending: comment.id == viewModel.pendingLocalComment?.id
                        )
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Skeleton

    private var skeletonView: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 110, height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.10))
                            .frame(maxWidth: .infinity)
                            .frame(height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.10))
                            .frame(width: 180, height: 12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .redacted(reason: .placeholder)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.speech.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Be the first to share a reflection")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Sheet Background

    @ViewBuilder
    private var sheetBackground: some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        } else {
            Color.clear
                .ignoresSafeArea()
        }
    }

    // MARK: - Computed Helpers

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    /// Visible server comments + the local pending comment (appended at the end if present).
    private var allDisplayComments: [SmartComment] {
        var result = viewModel.visibleComments(currentUserId: currentUserId)

        // Append the pending local comment if it isn't already in the visible list
        // (i.e., the RTDB listener hasn't replaced it yet).
        if let pending = viewModel.pendingLocalComment,
           !result.contains(where: { $0.id == pending.id }) {
            result.append(pending)
        }

        return result
    }

    private var visibleCount: Int {
        allDisplayComments.count
    }

    private var nudgeSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.nudgeSuggestion != nil },
            set: { if !$0 { viewModel.dismissNudge() } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )
    }

    private var safeAreaBottomPadding: CGFloat {
        // Provide a sensible bottom padding so the composer clears the home indicator.
        // UIWindowScene provides the safe area; fall back to a sensible constant.
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        return max(window?.safeAreaInsets.bottom ?? 0, 8)
    }
}

// MARK: - Nudge Sheet

/// Shown when the comment coach returns .nudge.
/// Presents the coaching message; the user can dismiss (post is NOT submitted).
/// To post anyway after a nudge the user must re-submit through the normal composer path.
private struct NudgeSheet: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Handle indicator
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Image(systemName: "lightbulb.fill")
                .font(.system(size: 32))
                .foregroundStyle(.yellow.opacity(0.85))

            Text("A gentle note")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            Text(message)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Button {
                onDismiss()
            } label: {
                Text("Got it")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }
}
