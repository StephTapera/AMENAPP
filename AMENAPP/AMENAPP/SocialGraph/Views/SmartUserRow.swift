// SmartUserRow.swift
// AMENAPP
//
// A single row in followers/following/mutuals lists.
// Shows profile image, name, activity badge, and an unseen indicator dot.

import SwiftUI

struct SmartUserRow: View {
    let viewModel: SmartUserRowViewModel
    var onTap: (() -> Void)? = nil
    var onFollow: (() -> Void)? = nil
    var onMarkSeen: (() -> Void)? = nil

    @State private var isPressed = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                avatarView
                infoStack
                Spacer(minLength: 0)
                trailingActions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .onAppear {
            if viewModel.activityState.hasUnseen {
                onMarkSeen?()
            }
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = viewModel.profileImageURL, let imageURL = URL(string: url) {
                    CachedAsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarPlaceholder
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())

            if viewModel.activityState.hasUnseen {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                    .offset(x: 2, y: -2)
            }
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.15))
            Text(viewModel.displayName.prefix(1).uppercased())
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Info Stack

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(viewModel.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if viewModel.isMutual {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("@\(viewModel.username)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !viewModel.copy.headline.isEmpty {
                activityLine
                    .padding(.top, 2)
            }
        }
    }

    private var activityLine: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.activityState.activityType.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accentColor.opacity(viewModel.copy.accentColor.opacity))

            Text(viewModel.copy.headline)
                .font(.system(size: 12, weight: viewModel.activityState.hasUnseen ? .semibold : .regular))
                .foregroundStyle(accentColor.opacity(viewModel.copy.accentColor.opacity))
                .lineLimit(1)

            if let badge = viewModel.copy.badgeLabel {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.blue))
            }
        }
    }

    // MARK: - Trailing Actions

    private var trailingActions: some View {
        Group {
            if let onFollow {
                FollowButtonCompact(isFollowing: viewModel.isFollowing, action: onFollow)
            }
        }
    }

    // MARK: - Helpers

    private var accentColor: Color {
        switch viewModel.copy.accentColor {
        case .vibrant: return .blue
        case .moderate: return .primary
        case .muted: return .secondary
        }
    }
}

// MARK: - Compact Follow Button

private struct FollowButtonCompact: View {
    let isFollowing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isFollowing ? .primary : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isFollowing
                              ? Color.secondary.opacity(0.12)
                              : Color.blue)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isFollowing ? Color.secondary.opacity(0.2) : .clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
