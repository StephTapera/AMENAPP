// ThreadedRepliesView.swift
// AMENAPP — SocialLayer/
//
// Threaded reply tree rooted at a Firestore post.
// Loads replies from posts/{rootPostId}/comments, builds a depth-2 tree,
// and drives InlineReplyComposer for new replies.
//
// Types: ReplyNode, ComposerAttachment (ComposerContract.swift — do NOT redeclare)
// Pattern mirrors ReplyThreadViewModel (AMENAPP/Replies/) but uses ObservableObject
// so it can be injected with @StateObject per the task contract.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - ReplySortOrder

enum ReplySortOrder: String, CaseIterable, Identifiable {
    case top    = "Top"
    case newest = "Newest"
    var id: String { rawValue }
}

// MARK: - ThreadedRepliesViewModel

@MainActor
final class ThreadedRepliesViewModel: ObservableObject {

    // MARK: Published state

    @Published var nodes: [ReplyNode] = []
    @Published var isLoading = false
    @Published var sortOrder: ReplySortOrder = .top {
        didSet {
            guard sortOrder != oldValue else { return }
            stopListening()
            startListening()
        }
    }
    @Published var errorMessage: String?
    @Published var hasMoreReplies = false
    @Published var likedNodeIds: Set<String> = []

    // MARK: Private state

    private let rootPostId: String
    private var listenerRegistration: ListenerRegistration?
    private var submittedKeys: Set<String> = []     // idempotency guard

    private var commentsRef: CollectionReference {
        Firestore.firestore()
            .collection("posts")
            .document(rootPostId)
            .collection("comments")
    }

    private var sortedQuery: Query {
        switch sortOrder {
        case .newest:
            return commentsRef.order(by: "createdAt", descending: true).limit(to: 50)
        case .top:
            return commentsRef.order(by: "amenCount", descending: true).limit(to: 50)
        }
    }

    // MARK: Init / deinit

    init(rootPostId: String) {
        self.rootPostId = rootPostId
    }

    deinit {
        let reg = listenerRegistration
        Task { reg?.remove() }
    }

    // MARK: - Load (one-shot fetch)

    func loadReplies(postId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await sortedQuery.getDocuments()
            nodes = buildTree(from: snapshot.documents)
            hasMoreReplies = snapshot.documents.count == 50
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Real-time listener

    func startListening() {
        listenerRegistration?.remove()
        listenerRegistration = sortedQuery.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot else { return }
            Task { @MainActor in
                self.nodes = self.buildTree(from: snapshot.documents)
                self.hasMoreReplies = snapshot.documents.count == 50
            }
        }
    }

    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    // MARK: - Tree builder

    private func buildTree(from docs: [QueryDocumentSnapshot]) -> [ReplyNode] {
        let flat: [ReplyNode] = docs.compactMap { doc in
            let d = doc.data()
            guard
                let authorId   = d["authorId"]   as? String,
                let authorName = d["authorName"] as? String,
                let content    = d["content"]    as? String
            else { return nil }

            let createdAt: Date
            if let ts = d["createdAt"] as? Timestamp {
                createdAt = ts.dateValue()
            } else {
                createdAt = Date()
            }

            let initials = authorName
                .split(separator: " ")
                .prefix(2)
                .compactMap { $0.first.map { String($0) } }
                .joined()
                .uppercased()

            // Support both "parentId" (ReplyThreadViewModel style) and
            // "parentCommentId" (Comment model style).
            let parentId = (d["parentId"] as? String) ?? (d["parentCommentId"] as? String)

            return ReplyNode(
                id:                    doc.documentID,
                postId:                rootPostId,
                parentId:              parentId,
                rootPostId:            rootPostId,
                authorId:              authorId,
                authorName:            authorName,
                authorUsername:        d["authorUsername"] as? String,
                authorProfileImageURL: d["authorProfileImageURL"] as? String,
                authorInitials:        initials.isEmpty ? "?" : initials,
                content:               content,
                createdAt:             createdAt,
                likeCount:             d["amenCount"]  as? Int ?? 0,
                replyCount:            d["replyCount"] as? Int ?? 0,
                depth:                 0,
                children:              [],
                sortKey:               d["amenCount"]  as? Double ?? 0
            )
        }

        // Build lookup table
        var byId = Dictionary(uniqueKeysWithValues: flat.map { ($0.id, $0) })

        // Attach children
        for node in flat {
            guard let pid = node.parentId, byId[pid] != nil else { continue }
            byId[pid]!.children.append(node)
        }

        // Depth assignment (cap at 2 for render; deeper nodes collapse to "View more replies")
        func setDepth(_ node: inout ReplyNode, depth: Int) {
            node.depth = min(depth, 2)
            for i in node.children.indices {
                setDepth(&node.children[i], depth: depth + 1)
            }
        }

        let knownIds = Set(flat.map { $0.id })
        var roots = byId.values.filter { node in
            guard let pid = node.parentId else { return true }
            return !knownIds.contains(pid)
        }
        .sorted {
            sortOrder == .newest
                ? $0.createdAt > $1.createdAt
                : $0.likeCount > $1.likeCount
        }

        for i in roots.indices {
            setDepth(&roots[i], depth: 0)
        }
        return roots
    }

    // MARK: - Like / amen

    func likeReply(nodeId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let amenRef = commentsRef.document(nodeId).collection("amens").document(uid)
        let isLiked = likedNodeIds.contains(nodeId)

        // Optimistic toggle
        if isLiked {
            likedNodeIds.remove(nodeId)
            updateNodeLikeCount(nodeId: nodeId, delta: -1)
        } else {
            likedNodeIds.insert(nodeId)
            updateNodeLikeCount(nodeId: nodeId, delta: 1)
        }

        do {
            if isLiked {
                try await amenRef.delete()
                try await commentsRef.document(nodeId).updateData([
                    "amenCount": FieldValue.increment(Int64(-1))
                ])
            } else {
                try await amenRef.setData(["likedAt": FieldValue.serverTimestamp()])
                try await commentsRef.document(nodeId).updateData([
                    "amenCount": FieldValue.increment(Int64(1))
                ])
            }
        } catch {
            // Rollback optimistic update
            if isLiked {
                likedNodeIds.insert(nodeId)
                updateNodeLikeCount(nodeId: nodeId, delta: 1)
            } else {
                likedNodeIds.remove(nodeId)
                updateNodeLikeCount(nodeId: nodeId, delta: -1)
            }
            errorMessage = error.localizedDescription
        }
    }

    private func updateNodeLikeCount(nodeId: String, delta: Int) {
        func applyDelta(_ nodes: inout [ReplyNode]) {
            for i in nodes.indices {
                if nodes[i].id == nodeId {
                    nodes[i].likeCount += delta
                    return
                }
                applyDelta(&nodes[i].children)
            }
        }
        applyDelta(&nodes)
    }

    // MARK: - Delete reply

    func deleteReply(nodeId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // Only delete if this user is the author — enforced by Firestore rules too
        guard let node = findNode(id: nodeId, in: nodes), node.authorId == uid else { return }

        do {
            try await commentsRef.document(nodeId).delete()
            removeNode(id: nodeId, from: &nodes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func findNode(id: String, in nodes: [ReplyNode]) -> ReplyNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = findNode(id: id, in: node.children) { return found }
        }
        return nil
    }

    private func removeNode(id: String, from nodes: inout [ReplyNode]) {
        nodes.removeAll { $0.id == id }
        for i in nodes.indices {
            removeNode(id: id, from: &nodes[i].children)
        }
    }

    // MARK: - Submit reply (called by InlineReplyComposer onSend)

    func submitReply(content: String, parentId: String?, attachments: [ComposerAttachment]) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let currentUser = Auth.auth().currentUser
        let authorId   = currentUser?.uid ?? "anonymous"
        let authorName = currentUser?.displayName ?? "Anonymous"

        let prefix = String(trimmed.prefix(40))
        let key    = "\(authorId):\(rootPostId):\(parentId ?? "root"):\(prefix)"
        guard !submittedKeys.contains(key) else { return }
        submittedKeys.insert(key)

        let initials = authorName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()

        var payload: [String: Any] = [
            "authorId":       authorId,
            "authorName":     authorName,
            "authorInitials": initials.isEmpty ? "?" : initials,
            "content":        trimmed,
            "rootPostId":     rootPostId,
            "postId":         rootPostId,
            "createdAt":      FieldValue.serverTimestamp(),
            "amenCount":      0,
            "replyCount":     0
        ]
        if let pid = parentId {
            payload["parentId"]      = pid
            payload["parentCommentId"] = pid
        }
        if let profile = currentUser?.photoURL?.absoluteString {
            payload["authorProfileImageURL"] = profile
        }

        do {
            _ = try await commentsRef.addDocument(data: payload)
            if let pid = parentId {
                try await commentsRef.document(pid).updateData([
                    "replyCount": FieldValue.increment(Int64(1))
                ])
            }
        } catch {
            submittedKeys.remove(key)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ThreadedRepliesView

struct ThreadedRepliesView: View {

    let rootPostId: String
    let rootPostAuthorName: String

    @StateObject private var viewModel: ThreadedRepliesViewModel
    @State private var replyingToNode: ReplyNode?
    @State private var showLoadMore = false

    init(rootPostId: String, rootPostAuthorName: String) {
        self.rootPostId = rootPostId
        self.rootPostAuthorName = rootPostAuthorName
        _viewModel = StateObject(wrappedValue: ThreadedRepliesViewModel(rootPostId: rootPostId))
    }

    var body: some View {
        VStack(spacing: 0) {
            sortToggleBar

            if viewModel.isLoading && viewModel.nodes.isEmpty {
                loadingView
            } else if viewModel.nodes.isEmpty {
                emptyStateView
            } else {
                repliesScrollView
            }

            // Inline composer pinned at bottom when replying
            if replyingToNode != nil || viewModel.nodes.isEmpty {
                InlineReplyComposer(
                    replyingToNode: replyingToNode,
                    rootPostId: rootPostId,
                    onSend: { text, attachments in
                        Task {
                            await viewModel.submitReply(
                                content: text,
                                parentId: replyingToNode?.id,
                                attachments: attachments
                            )
                            withAnimation(Motion.adaptive(Motion.appearEase)) {
                                replyingToNode = nil
                            }
                        }
                    },
                    onDismiss: {
                        withAnimation(Motion.adaptive(Motion.appearEase)) {
                            replyingToNode = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await viewModel.loadReplies(postId: rootPostId)
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    // MARK: - Sort Toggle Bar

    private var sortToggleBar: some View {
        HStack(spacing: 8) {
            ForEach(ReplySortOrder.allCases) { order in
                Button {
                    HapticManager.impact(style: .light)
                    withAnimation(Motion.adaptive(Motion.popToggle)) {
                        viewModel.sortOrder = order
                    }
                } label: {
                    Text(order.rawValue)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(
                            viewModel.sortOrder == order
                                ? AmenTheme.Colors.amenBlue
                                : AmenTheme.Colors.textSecondary
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(
                                    viewModel.sortOrder == order
                                        ? AmenTheme.Colors.amenBlue.opacity(0.12)
                                        : Color.clear
                                )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    viewModel.sortOrder == order
                                        ? AmenTheme.Colors.amenBlue.opacity(0.35)
                                        : AmenTheme.Colors.separatorSubtle,
                                    lineWidth: 0.75
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.sortOrder == order ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Replies scroll view

    private var repliesScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.nodes.enumerated()), id: \.element.id) { index, node in
                    replyNodeSection(node: node, index: index)
                }

                if viewModel.hasMoreReplies {
                    loadMoreButton
                        .padding(.vertical, 12)
                }
            }
            .padding(.bottom, 80)  // space for pinned composer
        }
    }

    @ViewBuilder
    private func replyNodeSection(node: ReplyNode, index: Int) -> some View {
        VStack(spacing: 0) {
            ReplyNodeRow(
                node: node,
                isLiked: viewModel.likedNodeIds.contains(node.id),
                currentUserId: Auth.auth().currentUser?.uid ?? "",
                onLike: { Task { await viewModel.likeReply(nodeId: node.id) } },
                onReply: {
                    withAnimation(Motion.adaptive(Motion.appearEase)) {
                        replyingToNode = node
                    }
                },
                onDelete: { Task { await viewModel.deleteReply(nodeId: node.id) } }
            )
            .staggeredReveal(index: index, baseDelay: 0.035, maxDelay: 0.18)

            // Nested children (depth 1)
            if !node.children.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(node.children.enumerated()), id: \.element.id) { childIdx, child in
                        childSection(child: child, parentIndex: index, childIndex: childIdx)
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func childSection(child: ReplyNode, parentIndex: Int, childIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Depth rail line
            HStack(spacing: 0) {
                Rectangle()
                    .fill(AmenTheme.Colors.amenPurple.opacity(0.3))
                    .frame(width: 2)
                    .padding(.leading, 16)

                VStack(spacing: 0) {
                    if child.depth <= 2 {
                        ReplyNodeRow(
                            node: child,
                            isLiked: viewModel.likedNodeIds.contains(child.id),
                            currentUserId: Auth.auth().currentUser?.uid ?? "",
                            onLike: { Task { await viewModel.likeReply(nodeId: child.id) } },
                            onReply: {
                                withAnimation(Motion.adaptive(Motion.appearEase)) {
                                    replyingToNode = child
                                }
                            },
                            onDelete: { Task { await viewModel.deleteReply(nodeId: child.id) } }
                        )
                        .staggeredReveal(
                            index: parentIndex * 10 + childIndex,
                            baseDelay: 0.035,
                            maxDelay: 0.20
                        )
                    }

                    // Collapse deeper nesting: "View more replies"
                    let deeperChildren = child.children.filter { $0.depth > 2 }
                    if !deeperChildren.isEmpty {
                        Button {
                            withAnimation(Motion.adaptive(Motion.appearEase)) {
                                replyingToNode = child
                            }
                        } label: {
                            Text("View \(deeperChildren.count) more \(deeperChildren.count == 1 ? "reply" : "replies")")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(AmenTheme.Colors.amenBlue)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    // MARK: - Load more

    private var loadMoreButton: some View {
        Button {
            Task { await viewModel.loadReplies(postId: rootPostId) }
        } label: {
            Text("Load more replies")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.amenBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.small)
                        .fill(AmenTheme.Colors.amenBlue.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(AmenTheme.Colors.shimmerBase)
                        .frame(width: 36, height: 36)
                        .amenSkeleton()
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AmenTheme.Colors.shimmerBase)
                            .frame(height: 12)
                            .amenSkeleton()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AmenTheme.Colors.shimmerBase)
                            .frame(height: 32)
                            .amenSkeleton()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("Be the first to reply")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            Text("Share what this means to you")
                .font(AMENFont.regular(14))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - ReplyNodeRow

struct ReplyNodeRow: View {

    let node: ReplyNode
    let isLiked: Bool
    let currentUserId: String
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var isOwn: Bool { node.authorId == currentUserId }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarView

            VStack(alignment: .leading, spacing: 6) {
                // Author header
                authorHeaderView

                // Content
                Text(node.content)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(node.content)

                // Action row
                actionRow
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(node.authorName), @\(node.authorUsername ?? ""), \(node.content), \(node.likeCount) likes, \(node.replyCount) replies"
        )
        .confirmationDialog(
            "Delete this reply?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Avatar

    private var avatarView: some View {
        Group {
            if let urlStr = node.authorProfileImageURL,
               !urlStr.isEmpty,
               let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { img in
                    img.resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } placeholder: {
                    initialsCircle
                }
            } else {
                initialsCircle
            }
        }
        .frame(width: 36, height: 36)
    }

    private var initialsCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [AmenTheme.Colors.amenPurple.opacity(0.7), AmenTheme.Colors.amenBlue.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 36, height: 36)
            .overlay(
                Text(node.authorInitials)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(.white)
            )
    }

    // MARK: Author header

    private var authorHeaderView: some View {
        HStack(spacing: 6) {
            Text(node.authorName)
                .font(AMENFont.semiBold(14))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            if let username = node.authorUsername {
                Text("@\(username)")
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)

            Text(node.createdAt.timeAgoDisplay())
                .font(AMENFont.regular(12))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
        }
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: 20) {
            // Like button
            Button {
                HapticManager.impact(style: .light)
                withAnimation(Motion.adaptive(Motion.popToggle)) {
                    onLike()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isLiked ? "hands.sparkles.fill" : "hands.sparkles")
                        .font(.system(size: 13))
                        .reactionPop(isActive: isLiked)
                    if node.likeCount > 0 {
                        Text("\(node.likeCount)")
                            .font(AMENFont.semiBold(12))
                    }
                }
                .foregroundStyle(isLiked ? AmenTheme.Colors.amenGold : AmenTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "Remove amen" : "Amen")
            .accessibilityValue("\(node.likeCount) amens")

            // Reply button
            Button {
                HapticManager.impact(style: .light)
                onReply()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 12))
                    Text("Reply")
                        .font(AMENFont.semiBold(12))
                }
                .foregroundStyle(AmenTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reply to \(node.authorName)")

            // Delete button (own replies only)
            if isOwn {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(AmenTheme.Colors.statusError.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete reply")
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

// Date.timeAgoDisplay() is declared in PostComment.swift — no redeclaration needed.
