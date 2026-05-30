// ReplyThreadView.swift
// AMENAPP — Replies/
//
// Full-screen threaded reply viewer.
// Shows the original (dimmed) post, a sort picker, then a depth-2 tree of
// ReplyRowView cells with leading connector lines.
//
// Types used: ReplyNode, ComposerDraft  (ComposerContract.swift)
// ViewModel:  ReplyThreadViewModel

import SwiftUI

// MARK: - ReplyThreadView

struct ReplyThreadView: View {

    let rootPostId: String
    let originalPostContent: String
    let originalAuthorName: String

    @State private var vm: ReplyThreadViewModel
    @State private var activeParentId: String? = nil
    @Environment(\.dismiss) private var dismiss

    init(rootPostId: String, originalPostContent: String, originalAuthorName: String) {
        self.rootPostId = rootPostId
        self.originalPostContent = originalPostContent
        self.originalAuthorName = originalAuthorName
        _vm = State(wrappedValue: ReplyThreadViewModel(rootPostId: rootPostId))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                scrollContent
                    .safeAreaInset(edge: .bottom) {
                        // Reserve space for the pinned composer
                        Color.clear.frame(height: vm.isReplyComposerPresented ? 140 : 64)
                    }

                // Pinned inline reply composer
                InlineReplyComposer(
                    draft: $vm.replyComposerDraft,
                    isPresented: $vm.isReplyComposerPresented,
                    parentId: activeParentId
                ) { content, parentId in
                    Task { await vm.submitReply(content: content, parentId: parentId) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await vm.loadReplies() }
            .onAppear { vm.startListening() }
            .onDisappear { vm.stopListening() }
        }
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                originalPostHeader
                sortPickerRow
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                if vm.isLoading && vm.replies.isEmpty {
                    loadingPlaceholder
                } else if vm.replies.isEmpty {
                    emptyState
                } else {
                    replyList
                }

                if vm.canLoadMore {
                    loadMoreButton
                }
            }
        }
    }

    // MARK: - Original post header (dimmed)

    private var originalPostHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarCircle(
                initials: String(originalAuthorName.prefix(2)).uppercased(),
                size: 40,
                color: AmenTheme.Colors.amenGold.opacity(0.5)
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(originalAuthorName)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                Text(originalPostContent)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(AmenTheme.Colors.textSecondary.opacity(0.7))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Vertical connector line below avatar
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(AmenTheme.Colors.separator.opacity(0.6))
                .frame(width: 2, height: 20)
                .offset(x: 16 + 19, y: 10) // 16 leading + avatar center (40/2 - 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Original post by \(originalAuthorName): \(originalPostContent)")
    }

    // MARK: - Sort picker

    private var sortPickerRow: some View {
        HStack {
            Menu {
                ForEach(ReplySortMode.allCases) { mode in
                    Button {
                        withAnimation(Motion.adaptive(Motion.tabGlide)) {
                            vm.sortMode = mode
                        }
                    } label: {
                        Label(mode.rawValue, systemImage: mode == .top ? "arrow.up" : "clock")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(vm.sortMode.rawValue)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(AmenTheme.Colors.surfaceChip)
                        .overlay(Capsule().strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5))
                )
            }
            .accessibilityLabel("Sort replies. Current: \(vm.sortMode.rawValue)")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Reply list (depth-aware)

    private var replyList: some View {
        ForEach(Array(vm.replies.enumerated()), id: \.element.id) { index, node in
            replyNodeView(node: node, depth: 0, index: index)
        }
    }

    private func replyNodeView(node: ReplyNode, depth: Int, index: Int) -> AnyView {
        guard depth <= 2 else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                ReplyRowView(
                    node: node,
                    onReply: { parentId in
                        activeParentId = parentId
                        withAnimation(Motion.adaptive(Motion.springPress)) {
                            vm.isReplyComposerPresented = true
                        }
                    },
                    onLike: { replyId in
                        Task { await vm.toggleLike(replyId: replyId) }
                    }
                )
                .padding(.leading, CGFloat(depth) * 28)
                .staggeredReveal(index: index)

                if !node.children.isEmpty {
                    connectorLine(leadingInset: CGFloat(depth) * 28 + 16 + 16)
                }

                ForEach(Array(node.children.enumerated()), id: \.element.id) { childIndex, child in
                    if depth + 1 <= 2 {
                        replyNodeView(node: child, depth: depth + 1, index: childIndex)
                    } else {
                        viewMoreRepliesButton(parentId: node.id)
                    }
                }

                Divider()
                    .padding(.leading, CGFloat(depth) * 28 + 16)
                    .padding(.trailing, 16)
            }
        )
    }

    private func connectorLine(leadingInset: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: leadingInset)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AmenTheme.Colors.separator.opacity(0.5), AmenTheme.Colors.separator.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 2, height: 16)
            Spacer()
        }
        .accessibilityHidden(true)
    }

    private func viewMoreRepliesButton(parentId: String) -> some View {
        Button {
            // Future: push a deeper thread view
        } label: {
            Text("View more replies")
                .font(AMENFont.semiBold(13))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
        }
        .padding(.leading, 28 * 2 + 16)
        .padding(.vertical, 8)
        .accessibilityLabel("View more replies")
    }

    // MARK: - Loading / empty states

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(AmenTheme.Colors.surfaceChip)
                    .frame(height: 68)
                    .padding(.horizontal, 16)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.top, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No replies yet")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Be the first to reply.")
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No replies yet. Be the first to reply.")
    }

    private var loadMoreButton: some View {
        Button {
            Task { await vm.loadMore() }
        } label: {
            Text("Load more replies")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .accessibilityLabel("Load more replies")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .accessibilityLabel("Back")
        }

        ToolbarItem(placement: .principal) {
            Text("Replies")
                .font(AMENFont.semiBold(17))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                // Share sheet — integration at call site
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .accessibilityLabel("Share")

            Button {
                // Notification bell toggle — integration at call site
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
            }
            .accessibilityLabel("Notifications for this thread")
        }
    }

    // MARK: - Helpers

    private func avatarCircle(initials: String, size: CGFloat, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(AMENFont.semiBold(size * 0.35))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            )
    }
}

// MARK: - ReplyRowView

struct ReplyRowView: View {

    let node: ReplyNode
    let onReply: (String) -> Void
    let onLike:  (String) -> Void

    @State private var isLiked = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                authorLine
                contentText
                actionBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Avatar

    private var avatarView: some View {
        Circle()
            .fill(avatarGradient)
            .frame(width: 32, height: 32)
            .overlay(
                Group {
                    if let urlString = node.authorProfileImageURL,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            } else {
                                initialsView
                            }
                        }
                    } else {
                        initialsView
                    }
                }
            )
    }

    private var initialsView: some View {
        Text(node.authorInitials)
            .font(AMENFont.semiBold(12))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
    }

    private var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [AmenTheme.Colors.amenPurple.opacity(0.3), AmenTheme.Colors.amenBlue.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Author line

    private var authorLine: some View {
        HStack(spacing: 5) {
            Text(node.authorName)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            if let username = node.authorUsername {
                Text("@\(username)")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Spacer()

            Text(node.createdAt.timeAgoDisplay())
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    // MARK: Content

    private var contentText: some View {
        Text(node.content)
            .font(.body)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 20) {
            // Like / Amen
            Button {
                withAnimation(Motion.adaptive(Motion.popToggle)) {
                    isLiked.toggle()
                }
                onLike(node.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isLiked ? "hands.sparkles.fill" : "hands.sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(isLiked ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textSecondary)
                        .reactionPop(isActive: isLiked)
                    if node.likeCount > 0 {
                        Text("\(node.likeCount)")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like, \(node.likeCount) \(node.likeCount == 1 ? "amen" : "amens")")

            // Reply
            Button {
                onReply(node.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 14))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    if node.replyCount > 0 {
                        Text("\(node.replyCount)")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reply, \(node.replyCount) \(node.replyCount == 1 ? "reply" : "replies")")

            // Repost
            Button {
                // Repost — integration at call site
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repost")

            // Share
            Button {
                // Share — integration at call site
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")

            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: Accessibility description

    private var accessibilityDescription: String {
        let ago = node.createdAt.timeAgoDisplay()
        return "\(node.authorName), \(ago): \(node.content). \(node.likeCount) amens, \(node.replyCount) replies."
    }
}

