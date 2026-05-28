// TimestampedCommentRow.swift
// AMENAPP
//
// A row view rendering a single timestamped comment.
// Used in the comment list beneath media posts.
//
// Gated: AMENFeatureFlags.shared.mediaTimestampedCommentsEnabled

import SwiftUI

// MARK: - TimestampedComment Model

/// A comment anchored to a specific moment or element in a media post.
struct TimestampedComment: Identifiable, Equatable {
    let id: String
    let authorId: String
    let authorDisplayName: String
    /// Optional remote URL string for the author's avatar image.
    let authorAvatarURL: String?
    let text: String
    /// The media anchor this comment is tied to.
    let target: TimestampedCommentTarget
    let createdAt: Date
    var likeCount: Int
    var isLiked: Bool
}

// MARK: - TimestampedCommentRow

/// Horizontal layout: 32pt avatar | content | like button
///
/// - Tapping the timestamp chip invokes `onTimestampTap`, which should seek
///   the associated player to that position.
/// - Long-pressing reveals a context menu with a Report option.
struct TimestampedCommentRow: View {

    // MARK: Inputs

    let comment: TimestampedComment
    let onTimestampTap: (TimestampedCommentTarget) -> Void
    let onLike: () -> Void
    let onReport: () -> Void

    // MARK: Body

    var body: some View {
        guard AMENFeatureFlags.shared.mediaTimestampedCommentsEnabled else {
            return AnyView(EmptyView())
        }
        return AnyView(rowContent)
    }

    // MARK: Row Content

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                avatarView
                contentColumn
                likeColumn
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .contextMenu {
                Button(role: .destructive) {
                    onReport()
                } label: {
                    Label("Report comment", systemImage: "flag")
                }
            }

            Divider()
                .padding(.leading, 58) // inset past avatar + spacing
        }
    }

    // MARK: Avatar

    private var avatarView: some View {
        Group {
            if let urlString = comment.authorAvatarURL,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .overlay(
                Text(comment.authorDisplayName.prefix(1).uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: Content Column

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text(comment.authorDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                timestampChip
            }

            Text(comment.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(comment.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Timestamp Chip

    private var timestampChip: some View {
        Button {
            onTimestampTap(comment.target)
        } label: {
            Text(comment.target.displayLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Jump to \(comment.target.accessibilityLabel)")
        .accessibilityHint("Seeks the video or media to this position")
    }

    // MARK: Like Column

    private var likeColumn: some View {
        VStack(spacing: 2) {
            Button {
                onLike()
            } label: {
                Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(comment.isLiked ? Color.red : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: comment.isLiked)
            .accessibilityLabel(comment.isLiked ? "Unlike this comment" : "Like this comment")

            if comment.likeCount > 0 {
                Text("\(comment.likeCount)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(comment.likeCount) \(comment.likeCount == 1 ? "like" : "likes")")
            }
        }
        .frame(minWidth: 44)
    }
}
