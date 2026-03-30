// ConversationThreadView.swift
// AMENAPP
//
// Threads-style conversation system for AMEN.
// Design philosophy: Wisdom-first ranking, branching sub-threads,
// gentle de-escalation, spiritually intentional — not doom-scroll.
//
// Architecture:
//   ConversationThreadView          — root scroll container (replaces commentsSection)
//   ThreadReplyRow                  — single reply with Threads-style connector line
//   ThreadBranchCluster             — expandable sub-thread ("View 5 replies")
//   ThreadComposerView              — glass reply input bar with de-escalation
//   ThreadReflectionCard            — periodic reflection pause card
//   ThreadWisdomBadge               — AI-detected quality badge (Thoughtful, Scripture, etc.)
//   ThreadDeescalationCard          — pre-post gentle rewrite prompt
//   ThreadSortPicker                — Most Thoughtful / Recent / Most Helpful sort
//   WisdomRankingService            — lightweight offline scoring; AI hook for cloud scoring

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Wisdom Quality Badge

enum ThreadWisdomBadge: String, CaseIterable {
    case thoughtful   = "Thoughtful"
    case scriptural   = "Scripture-Based"
    case encouraging  = "Encouraging"
    case helpful      = "Helpful"
    case peacemaking  = "Peacemaking"

    var icon: String {
        switch self {
        case .thoughtful:  return "lightbulb"
        case .scriptural:  return "book.closed"
        case .encouraging: return "heart"
        case .helpful:     return "checkmark.circle"
        case .peacemaking: return "dove"
        }
    }

    var color: Color {
        switch self {
        case .thoughtful:  return Color(red: 0.40, green: 0.55, blue: 0.90)
        case .scriptural:  return Color(red: 0.55, green: 0.40, blue: 0.75)
        case .encouraging: return Color(red: 0.90, green: 0.45, blue: 0.45)
        case .helpful:     return Color(red: 0.25, green: 0.65, blue: 0.45)
        case .peacemaking: return Color(red: 0.45, green: 0.75, blue: 0.85)
        }
    }
}

// MARK: - Thread Sort

enum ThreadSort: String, CaseIterable {
    case thoughtful = "Most Thoughtful"
    case recent     = "Recent"
    case helpful    = "Most Helpful"

    var icon: String {
        switch self {
        case .thoughtful: return "lightbulb"
        case .recent:     return "clock"
        case .helpful:    return "hand.thumbsup"
        }
    }
}

// MARK: - Wisdom Ranking Service

/// Offline wisdom scorer. Scores 0–1 based on heuristic signals.
/// In production, replace `computeOfflineScore` with a Cloud Function
/// that uses Claude / Vertex for semantic scoring and stores result
/// in Firestore as `replies/{id}/wisdomScore`.
struct WisdomRankingService {

    /// Heuristic signals (all offline — no network call required).
    static func score(for comment: Comment) -> Double {
        var score = 0.5 // Baseline

        let text = comment.content.lowercased()
        let wordCount = text.split(separator: " ").count

        // Depth signal: thoughtful replies tend to be 15–120 words
        if wordCount >= 15 && wordCount <= 120 { score += 0.15 }
        if wordCount > 200 { score -= 0.05 } // Very long = possibly ranting

        // Scripture citation
        let scriptureKeywords = ["matthew", "john", "psalm", "proverbs", "romans",
                                 "corinthians", "genesis", "revelation", "luke",
                                 "isaiah", "ephesians", "philippians", "acts",
                                 "hebrews", "galatians", "james", "peter"]
        let citesScripture = scriptureKeywords.contains { text.contains($0) }
        if citesScripture { score += 0.20 }

        // Question = curious / engaging
        if text.contains("?") { score += 0.05 }

        // Encouragement signals
        let encouragingWords = ["encourage", "pray", "grace", "love", "hope",
                                "peace", "bless", "amen", "faith", "strength"]
        let encouragingCount = encouragingWords.filter { text.contains($0) }.count
        score += min(Double(encouragingCount) * 0.04, 0.15)

        // Hostility signals (reduces score — not a hard block)
        let hostileWords = ["stupid", "idiot", "hate", "wrong", "shut up",
                            "dumb", "fool", "ridiculous", "pathetic"]
        let hostileCount = hostileWords.filter { text.contains($0) }.count
        score -= Double(hostileCount) * 0.12

        // Engagement: amenCount / replyCount
        score += min(Double(comment.amenCount) * 0.02, 0.10)
        score += min(Double(comment.replyCount) * 0.01, 0.05)

        return max(0, min(1, score))
    }

    /// Detect quality badges for a comment (offline heuristics).
    static func badges(for comment: Comment) -> [ThreadWisdomBadge] {
        var badges: [ThreadWisdomBadge] = []
        let text = comment.content.lowercased()

        let scriptureKeywords = ["matthew", "john", "psalm", "proverbs", "romans",
                                 "corinthians", "genesis", "revelation", "luke",
                                 "isaiah", "ephesians", "philippians", "acts",
                                 "hebrews", "galatians", "james", "peter",
                                 "\"he who", "\"for god", "the lord"]
        if scriptureKeywords.contains(where: { text.contains($0) }) {
            badges.append(.scriptural)
        }

        let encouragingWords = ["encourage", "pray for", "praying", "bless", "hope",
                                "peace", "love you", "grace", "strength", "beautiful"]
        if encouragingWords.contains(where: { text.contains($0) }) {
            badges.append(.encouraging)
        }

        let peacemakingWords = ["both sides", "understand", "hear you", "valid",
                                "perspective", "bridge", "together", "peace"]
        if peacemakingWords.contains(where: { text.contains($0) }) {
            badges.append(.peacemaking)
        }

        let helpfulWords = ["suggest", "try", "recommend", "helpful", "resource",
                            "here's", "step", "practical", "advice", "tip"]
        if helpfulWords.contains(where: { text.contains($0) }) {
            badges.append(.helpful)
        }

        let wordCount = text.split(separator: " ").count
        if wordCount >= 25 && comment.amenCount >= 3 && badges.isEmpty {
            badges.append(.thoughtful)
        }

        return Array(badges.prefix(2)) // Max 2 badges per reply
    }

    /// Detect if a reply text is potentially hostile/reactive.
    /// Returns a de-escalation prompt if intervention is warranted.
    static func deescalationPrompt(for text: String) -> String? {
        let lowered = text.lowercased()
        let hostile = ["stupid", "idiot", "hate you", "wrong", "shut up",
                       "dumb", "fool", "ridiculous", "pathetic", "disgusting",
                       "trash", "worthless", "awful", "terrible person"]
        let hasHostile = hostile.contains { lowered.contains($0) }
        guard hasHostile else { return nil }

        let prompts = [
            "This reply may come across as harsh. Would you like to reword it with grace?",
            "Before posting, consider: would this build up or tear down?",
            "This seems heated. Take a breath — your voice matters here.",
        ]
        return prompts[abs(text.hashValue) % prompts.count]
    }
}

// MARK: - Main Conversation Thread View

struct ConversationThreadView: View {
    let post: Post
    let postId: String
    let commentsWithReplies: [CommentWithReplies]
    let isLoading: Bool
    let savedBookIds: Set<String>

    var onReply: (Comment?) -> Void       // nil = reply to post
    var onAmen: (Comment) -> Void
    var onDelete: (Comment) -> Void
    var onProfileTap: (String) -> Void
    var onBerean: (String) -> Void

    @State private var sort: ThreadSort = .thoughtful
    @State private var expandedClusters: Set<String> = []
    @State private var reflectionCounter = 0
    @State private var showReflectionCard = false
    @State private var reflectionTriggerIds: Set<String> = []
    @State private var showSortPicker = false

    @Environment(\.colorScheme) private var colorScheme

    // Sorted replies based on current sort mode
    private var sortedComments: [CommentWithReplies] {
        switch sort {
        case .thoughtful:
            return commentsWithReplies.sorted {
                WisdomRankingService.score(for: $0.comment) >
                WisdomRankingService.score(for: $1.comment)
            }
        case .recent:
            return commentsWithReplies.sorted {
                $0.comment.createdAt > $1.comment.createdAt
            }
        case .helpful:
            return commentsWithReplies.sorted {
                ($0.comment.amenCount + $0.comment.replyCount) >
                ($1.comment.amenCount + $1.comment.replyCount)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Section header with sort picker ───────────────────────────────
            threadHeader

            if isLoading {
                threadSkeletonView
            } else if commentsWithReplies.isEmpty {
                emptyThreadView
            } else {
                // ── Thread list ───────────────────────────────────────────────
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedComments.enumerated()), id: \.element.id) { idx, item in
                        VStack(spacing: 0) {
                            ThreadReplyRow(
                                comment: item.comment,
                                replies: item.replies,
                                isClusterExpanded: expandedClusters.contains(item.comment.id ?? ""),
                                onExpandCluster: {
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                                        let id = item.comment.id ?? ""
                                        if expandedClusters.contains(id) {
                                            expandedClusters.remove(id)
                                        } else {
                                            expandedClusters.insert(id)
                                        }
                                    }
                                    // Count interactions for reflection pacing
                                    reflectionCounter += 1
                                    maybeShowReflection(after: item.comment.id ?? "")
                                },
                                onReply: { onReply(item.comment) },
                                onAmen: { onAmen(item.comment) },
                                onDelete: { onDelete(item.comment) },
                                onProfileTap: { onProfileTap(item.comment.authorId) },
                                onBerean: { onBerean(item.comment.content) },
                                onReplyAmen: { reply in onAmen(reply) },
                                onReplyDelete: { reply in onDelete(reply) },
                                onReplyProfile: { reply in onProfileTap(reply.authorId) }
                            )

                            // ── Reflection card (after every ~8 interactions) ───
                            if reflectionTriggerIds.contains(item.comment.id ?? "") {
                                ThreadReflectionCard(
                                    onContinue: {
                                        let cid = item.comment.id ?? ""
                                        withAnimation(Animation.linear(duration: 0.2)) {
                                            _ = reflectionTriggerIds.remove(cid)
                                        }
                                    },
                                    onPray: {
                                        onBerean("Lead me in a brief prayer of reflection.")
                                        let cid = item.comment.id ?? ""
                                        withAnimation(Animation.linear(duration: 0.2)) {
                                            _ = reflectionTriggerIds.remove(cid)
                                        }
                                    }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Thread Header

    private var threadHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Conversation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                if !commentsWithReplies.isEmpty {
                    Text("\(commentsWithReplies.count) \(commentsWithReplies.count == 1 ? "reply" : "replies")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Sort picker button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    showSortPicker.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sort.icon)
                        .font(.system(size: 11, weight: .medium))
                    Text(sort.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(showSortPicker ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        // Sort picker dropdown
        .overlay(alignment: .topTrailing) {
            if showSortPicker {
                ThreadSortPicker(selected: $sort, isShowing: $showSortPicker)
                    .padding(.top, 52)
                    .padding(.trailing, 16)
                    .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    // MARK: - Empty State

    private var emptyThreadView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary.opacity(0.45))
            Text("Start the conversation")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Be the first to reply with wisdom and grace.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                onReply(nil)
            } label: {
                Text("Add a thoughtful reply")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.78, green: 0.50, blue: 0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 40)
    }

    // MARK: - Skeleton

    private var threadSkeletonView: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in
                ThreadSkeletonRow(depth: i % 2 == 1 ? 1 : 0)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Reflection Pacing

    private func maybeShowReflection(after commentId: String) {
        // Show a reflection card every ~8 user interactions
        guard reflectionCounter > 0 && reflectionCounter % 8 == 0 else { return }
        guard !reflectionTriggerIds.contains(commentId) else { return }
        _ = withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            reflectionTriggerIds.insert(commentId)
        }
    }
}

// MARK: - Sort Picker Overlay

private struct ThreadSortPicker: View {
    @Binding var selected: ThreadSort
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ThreadSort.allCases, id: \.self) { option in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        selected = option
                        isShowing = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: option.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(option == selected ? Color(red: 0.78, green: 0.50, blue: 0.18) : .secondary)
                            .frame(width: 18)
                        Text(option.rawValue)
                            .font(.system(size: 14, weight: option == selected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        Spacer()
                        if option == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.78, green: 0.50, blue: 0.18))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if option != ThreadSort.allCases.last {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        .frame(width: 200)
    }
}

// MARK: - Thread Reply Row (Threads-style layout)

struct ThreadReplyRow: View {
    let comment: Comment
    let replies: [Comment]
    let isClusterExpanded: Bool
    let onExpandCluster: () -> Void
    let onReply: () -> Void
    let onAmen: () -> Void
    let onDelete: () -> Void
    let onProfileTap: () -> Void
    let onBerean: () -> Void
    let onReplyAmen: (Comment) -> Void
    let onReplyDelete: (Comment) -> Void
    let onReplyProfile: (Comment) -> Void

    @State private var isPressed = false
    @State private var hasAmened = false
    @State private var localAmenCount: Int = 0
    @Environment(\.colorScheme) private var colorScheme

    private var badges: [ThreadWisdomBadge] { WisdomRankingService.badges(for: comment) }
    private var isOwn: Bool { comment.authorId == Auth.auth().currentUser?.uid }

    var body: some View {
        VStack(spacing: 0) {
            // ── Root reply ────────────────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                // ── Left gutter: avatar + vertical connector ──────────────────
                VStack(spacing: 0) {
                    // Avatar
                    Button(action: onProfileTap) {
                        ThreadAvatar(
                            imageURL: comment.authorProfileImageURL,
                            initials: comment.authorInitials,
                            size: 36
                        )
                    }
                    .buttonStyle(.plain)

                    // Vertical connector line (if replies exist)
                    if !replies.isEmpty {
                        ThreadConnectorLine(isExpanded: isClusterExpanded)
                            .frame(width: 2)
                            .padding(.top, 4)
                    }
                }
                .frame(width: 52, alignment: .top)
                .padding(.leading, 16)

                // ── Reply content ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    // Author + timestamp header
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(comment.authorName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("@\(comment.authorUsername)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(timeAgoShort(from: comment.createdAt))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        // Options menu (own comment)
                        if isOwn {
                            Menu {
                                Button(role: .destructive, action: onDelete) {
                                    Label("Delete", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }

                    // Content
                    Text(comment.content)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    // Wisdom badges
                    if !badges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(badges, id: \.rawValue) { badge in
                                ThreadWisdomBadgeView(badge: badge)
                            }
                        }
                        .padding(.top, 2)
                    }

                    // ── Action bar ────────────────────────────────────────────
                    HStack(spacing: 20) {
                        // Amen
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                hasAmened.toggle()
                                localAmenCount += hasAmened ? 1 : -1
                            }
                            onAmen()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                                    .font(.system(size: 14))
                                    .scaleEffect(hasAmened ? 1.15 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: hasAmened)
                                if localAmenCount > 0 {
                                    Text("\(localAmenCount)")
                                        .font(.system(size: 13))
                                        .contentTransition(.numericText())
                                }
                            }
                            .foregroundStyle(hasAmened ? Color(red: 0.85, green: 0.55, blue: 0.15) : .secondary)
                        }
                        .buttonStyle(.plain)

                        // Reply
                        Button(action: onReply) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 14))
                                Text("Reply")
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        // Berean AI
                        Button(action: onBerean) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Expand/collapse cluster
                        if !replies.isEmpty {
                            Button(action: onExpandCluster) {
                                HStack(spacing: 4) {
                                    // Mini reply avatars
                                    replyAvatarStack
                                    Text(isClusterExpanded
                                         ? "Hide replies"
                                         : "View \(replies.count) \(replies.count == 1 ? "reply" : "replies")")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color(red: 0.78, green: 0.50, blue: 0.18))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.trailing, 16)
                .padding(.vertical, 12)
            }

            // ── Expanded sub-thread (branching cluster) ───────────────────────
            if isClusterExpanded && !replies.isEmpty {
                ThreadBranchCluster(
                    replies: replies,
                    parentComment: comment,
                    onReplyAmen: onReplyAmen,
                    onReplyDelete: onReplyDelete,
                    onReplyProfile: onReplyProfile,
                    onReplyToReply: { _ in onReply() }
                )
                .padding(.leading, 52) // indent to align with parent content
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── Subtle separator ──────────────────────────────────────────────
            Divider()
                .padding(.leading, 52)
                .opacity(0.5)
        }
        .onAppear {
            let uid = Auth.auth().currentUser?.uid ?? ""
            hasAmened = !uid.isEmpty && comment.amenUserIds.contains(uid)
            localAmenCount = comment.amenCount
        }
        .onChange(of: comment.amenUserIds) { _, newIds in
            let uid = Auth.auth().currentUser?.uid ?? ""
            hasAmened = !uid.isEmpty && newIds.contains(uid)
        }
        .onChange(of: comment.amenCount) { _, newCount in
            localAmenCount = newCount
        }
    }

    // Stacked mini-avatars for cluster preview
    private var replyAvatarStack: some View {
        ZStack {
            ForEach(Array(replies.prefix(3).enumerated()), id: \.offset) { idx, reply in
                ThreadAvatar(
                    imageURL: reply.authorProfileImageURL,
                    initials: reply.authorInitials,
                    size: 18
                )
                .offset(x: CGFloat(idx) * 10)
                .zIndex(Double(3 - idx))
            }
        }
        .frame(width: CGFloat(min(replies.count, 3)) * 10 + 18)
    }
}

// MARK: - Thread Branch Cluster (nested replies)

private struct ThreadBranchCluster: View {
    let replies: [Comment]
    let parentComment: Comment
    let onReplyAmen: (Comment) -> Void
    let onReplyDelete: (Comment) -> Void
    let onReplyProfile: (Comment) -> Void
    let onReplyToReply: (Comment) -> Void

    // Collapse very deep threads beyond 5 visible replies
    @State private var showAll = false
    private let visibleLimit = 5

    private var visibleReplies: [Comment] {
        showAll ? replies : Array(replies.prefix(visibleLimit))
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleReplies.enumerated()), id: \.element.stableId) { idx, reply in
                ThreadReplyBranchRow(
                    reply: reply,
                    isFirst: idx == 0,
                    hasMoreBelow: idx < visibleReplies.count - 1,
                    onAmen: { onReplyAmen(reply) },
                    onReply: { onReplyToReply(reply) },
                    onProfileTap: { onReplyProfile(reply) }
                )
            }

            // "Show more replies" collapse button
            if !showAll && replies.count > visibleLimit {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        showAll = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(Color(.separator).opacity(0.3))
                            .frame(width: 1.5, height: 20)
                            .padding(.leading, 14)

                        Text("View \(replies.count - visibleLimit) more \(replies.count - visibleLimit == 1 ? "reply" : "replies") in this thread")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.78, green: 0.50, blue: 0.18))
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Thread Reply Branch Row (nested reply with amen state)

private struct ThreadReplyBranchRow: View {
    let reply: Comment
    let isFirst: Bool
    let hasMoreBelow: Bool
    let onAmen: () -> Void
    let onReply: () -> Void
    let onProfileTap: () -> Void

    @State private var hasAmened = false
    @State private var localAmenCount: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // ── Connector gutter ──────────────────────────────────────
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.35))
                        .frame(width: 1.5)
                        .frame(height: isFirst ? 20 : 0)
                    Spacer()
                }
                .frame(width: 20)

                ThreadAvatar(
                    imageURL: reply.authorProfileImageURL,
                    initials: reply.authorInitials,
                    size: 28
                )
                .onTapGesture { onProfileTap() }

                if hasMoreBelow {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.25))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 44, alignment: .center)

            // ── Reply content ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(reply.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(timeAgoShort(from: reply.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Text(reply.content)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                // Mini wisdom badges
                let nestedBadges = WisdomRankingService.badges(for: reply)
                if !nestedBadges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(nestedBadges.prefix(1), id: \.rawValue) { badge in
                            ThreadWisdomBadgeView(badge: badge, compact: true)
                        }
                    }
                }

                // Mini action bar
                HStack(spacing: 16) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            hasAmened.toggle()
                            localAmenCount += hasAmened ? 1 : -1
                        }
                        onAmen()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: hasAmened ? "hands.clap.fill" : "hands.clap")
                                .font(.system(size: 12))
                                .scaleEffect(hasAmened ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: hasAmened)
                            if localAmenCount > 0 {
                                Text("\(localAmenCount)")
                                    .font(.system(size: 11))
                                    .contentTransition(.numericText())
                            }
                        }
                        .foregroundStyle(hasAmened ? Color(red: 0.85, green: 0.55, blue: 0.15) : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button(action: onReply) {
                        Text("Reply")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(.trailing, 16)
            .padding(.vertical, 10)
        }
        .onAppear {
            let uid = Auth.auth().currentUser?.uid ?? ""
            hasAmened = !uid.isEmpty && reply.amenUserIds.contains(uid)
            localAmenCount = reply.amenCount
        }
        .onChange(of: reply.amenUserIds) { _, newIds in
            let uid = Auth.auth().currentUser?.uid ?? ""
            hasAmened = !uid.isEmpty && newIds.contains(uid)
        }
        .onChange(of: reply.amenCount) { _, newCount in
            localAmenCount = newCount
        }
    }
}

// MARK: - Thread Connector Line

/// Animated vertical glass line connecting a parent reply to its sub-thread cluster.
private struct ThreadConnectorLine: View {
    let isExpanded: Bool

    @State private var lineHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Background track
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(.separator).opacity(0.2))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)

                // Animated fill
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.78, green: 0.50, blue: 0.18).opacity(0.5),
                                Color(.separator).opacity(0.25)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 2)
                    .frame(height: isExpanded ? max(lineHeight, geo.size.height) : 24)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isExpanded)
            }
            .onAppear { lineHeight = geo.size.height }
        }
        .frame(width: 2)
    }
}

// MARK: - Thread Avatar

struct ThreadAvatar: View {
    let imageURL: String?
    let initials: String
    let size: CGFloat

    var body: some View {
        Group {
            if let urlStr = imageURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } placeholder: {
                    initialsCircle
                }
            } else {
                initialsCircle
            }
        }
        .overlay(Circle().strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5))
    }

    private var initialsCircle: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.22)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .overlay(
                Text(initials.prefix(1))
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Wisdom Badge View

struct ThreadWisdomBadgeView: View {
    let badge: ThreadWisdomBadge
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: badge.icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            if !compact {
                Text(badge.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(badge.color)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(badge.color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(badge.color.opacity(0.20), lineWidth: 0.5))
    }
}

// MARK: - Reflection Card

struct ThreadReflectionCard: View {
    let onContinue: () -> Void
    let onPray: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let messages = [
        "You've been reading for a while. Take a moment before continuing.",
        "Pause and reflect before the next reply.",
        "Quality over quantity — wisdom takes time.",
    ]
    private let message = [
        "You've been reading for a while. Take a moment before continuing.",
        "Pause and reflect before the next reply.",
        "Quality over quantity — wisdom takes time.",
    ][Int.random(in: 0..<3)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "leaf")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.30, green: 0.65, blue: 0.40))
                Text("Take a moment")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)

            HStack(spacing: 10) {
                Button(action: onPray) {
                    HStack(spacing: 5) {
                        Image(systemName: "hands.sparkles")
                            .font(.system(size: 12))
                        Text("Pray")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.30, green: 0.65, blue: 0.40))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.30, green: 0.65, blue: 0.40).opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(red: 0.30, green: 0.65, blue: 0.40).opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Button(action: onContinue) {
                    Text("Continue reading")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.30, green: 0.65, blue: 0.40).opacity(0.20), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

// MARK: - De-escalation Card

/// Shown in the reply composer when a hostile/reactive reply is detected.
struct ThreadDeescalationCard: View {
    let prompt: String
    let onRewrite: () -> Void
    let onPostAnyway: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.orange)
                Text("A moment of grace")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(prompt)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onRewrite) {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil.and.sparkles")
                            .font(.system(size: 12))
                        Text("Rewrite with grace")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.78, green: 0.50, blue: 0.18), in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onPostAnyway) {
                    Text("Post anyway")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Thread Reply Composer (glass input bar with de-escalation)

struct ThreadComposerView: View {
    @Binding var text: String
    @Binding var replyingToUsername: String?
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onBerean: (String) -> Void

    @State private var deescalationPrompt: String? = nil
    @State private var deescalationOverride = false
    @State private var analysisTask: Task<Void, Never>? = nil
    @State private var isSubmitting = false

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        VStack(spacing: 0) {
            // De-escalation card (shown above composer when triggered)
            if let prompt = deescalationPrompt, !deescalationOverride {
                ThreadDeescalationCard(
                    prompt: prompt,
                    onRewrite: {
                        // Ask Berean to rewrite the text gracefully
                        let original = text
                        onBerean("Please help me rewrite this reply with grace and clarity, without losing my main point: \"\(original)\"")
                        deescalationPrompt = nil
                    },
                    onPostAnyway: {
                        deescalationOverride = true
                        deescalationPrompt = nil
                        submitReply()
                    },
                    onDismiss: {
                        deescalationPrompt = nil
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // ── Replying-to banner ────────────────────────────────────────────
            if let username = replyingToUsername {
                HStack {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.78, green: 0.50, blue: 0.18))
                    Text("Replying to @\(username)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation {
                            replyingToUsername = nil
                            text = text.hasPrefix("@\(username) ")
                                ? String(text.dropFirst("@\(username) ".count))
                                : text
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(red: 0.78, green: 0.50, blue: 0.18).opacity(0.06))
            }

            // ── Input row ─────────────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 10) {
                // Text field
                TextField("Reply with wisdom…", text: $text, axis: .vertical)
                    .focused(isFocused)
                    .font(.system(size: 15))
                    .lineLimit(1...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                    )
                    .onChange(of: text) { _, newValue in
                        // Debounced de-escalation analysis
                        analysisTask?.cancel()
                        deescalationOverride = false
                        analysisTask = Task {
                            try? await Task.sleep(nanoseconds: 900_000_000) // 0.9s debounce
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                deescalationPrompt = WisdomRankingService.deescalationPrompt(for: newValue)
                            }
                        }
                    }

                // Send button
                Button {
                    guard canPost else { return }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let prompt = WisdomRankingService.deescalationPrompt(for: trimmed),
                       !deescalationOverride {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            deescalationPrompt = prompt
                        }
                    } else {
                        submitReply()
                    }
                } label: {
                    Image(systemName: isSubmitting ? "hourglass" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(canPost ? Color(red: 0.78, green: 0.50, blue: 0.18) : Color(.systemGray4),
                                    in: Circle())
                        .animation(.easeInOut(duration: 0.15), value: canPost)
                }
                .buttonStyle(.plain)
                .disabled(!canPost)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private func submitReply() {
        isSubmitting = true
        onSubmit()
        // Reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            text = ""
            replyingToUsername = nil
            deescalationPrompt = nil
            deescalationOverride = false
            isSubmitting = false
        }
    }
}

// MARK: - Skeleton Row

private struct ThreadSkeletonRow: View {
    let depth: Int // 0 = root, 1 = nested

    @State private var phase: CGFloat = -1

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: depth == 0 ? 36 : 28, height: depth == 0 ? 36 : 28)
                .shimmer(phase: phase)
                .padding(.leading, CGFloat(depth) * 16)

            VStack(alignment: .leading, spacing: 6) {
                // Name line
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 100, height: 12)
                    .shimmer(phase: phase)
                // Content line 1
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 12)
                    .shimmer(phase: phase)
                // Content line 2 (shorter)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 160, height: 12)
                    .shimmer(phase: phase)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
    }
}

private extension View {
    func shimmer(phase: CGFloat) -> some View {
        self.overlay(
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.4), .clear],
                startPoint: .init(x: phase, y: 0.5),
                endPoint: .init(x: phase + 0.5, y: 0.5)
            )
            .allowsHitTesting(false)
        )
        .clipped()
    }
}

// MARK: - Helpers

private func timeAgoShort(from date: Date?) -> String {
    guard let date else { return "" }
    let interval = Date().timeIntervalSince(date)
    switch interval {
    case ..<60:         return "now"
    case ..<3600:       return "\(Int(interval / 60))m"
    case ..<86400:      return "\(Int(interval / 3600))h"
    case ..<604800:     return "\(Int(interval / 86400))d"
    default:
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}
