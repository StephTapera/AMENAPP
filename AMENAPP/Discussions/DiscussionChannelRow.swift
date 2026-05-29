// DiscussionChannelRow.swift
// AMENAPP — Discussions
//
// Apple Music "track row" analog for a channel inside a group.
// Layout: [index/icon] | [name + description] | [unread badge + "..."]
//
// Tap → onSelect(channel)
// Long-press / "..." tap → context menu (mute, copy link, mark read, leave)

import SwiftUI

// MARK: - Channel display model

struct DiscussionChannel: Identifiable {
    var id: String
    var name: String
    var description: String
    var icon: String          // SF Symbol name
    var unreadCount: Int
    var isPinned: Bool
    var isLocked: Bool        // requires entitlement
    var lastActivityAt: Date?
}

// MARK: - Row

struct DiscussionChannelRow: View {
    let channel: DiscussionChannel
    let index: Int
    var onSelect: (DiscussionChannel) -> Void = { _ in }
    var onMute: (DiscussionChannel) -> Void = { _ in }
    var onCopyLink: (DiscussionChannel) -> Void = { _ in }
    var onMarkRead: (DiscussionChannel) -> Void = { _ in }

    @State private var isPressed = false

    var body: some View {
        Button {
            guard !channel.isLocked else { return }
            onSelect(channel)
        } label: {
            HStack(spacing: 14) {
                // Leading: index number or icon
                leadingBadge

                // Center: name + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(channel.isLocked ? .secondary : .primary)
                        .lineLimit(1)

                    if !channel.description.isEmpty {
                        Text(channel.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Trailing: unread badge + overflow
                HStack(spacing: 10) {
                    if channel.unreadCount > 0 && !channel.isLocked {
                        Text(channel.unreadCount > 99 ? "99+" : "\(channel.unreadCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.44, green: 0.26, blue: 0.80)) // amenPurple
                            )
                    }

                    if channel.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    overflowMenu
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPressed ? AnyShapeStyle(Color(.systemFill)) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(AmenPressStyle(scale: 0.985))
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Leading badge

    private var leadingBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)

            Image(systemName: channel.isPinned ? "pin.fill" : channel.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(channel.isPinned
                    ? Color(red: 0.83, green: 0.69, blue: 0.22) // amenGold
                    : Color.secondary)
        }
    }

    // MARK: - Overflow "..."

    private var overflowMenu: some View {
        Menu {
            contextMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.automatic)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if !channel.isLocked {
            Button {
                onMarkRead(channel)
            } label: {
                Label("Mark as Read", systemImage: "checkmark.circle")
            }
            Button {
                onMute(channel)
            } label: {
                Label("Mute Channel", systemImage: "bell.slash")
            }
            Divider()
        }
        Button {
            onCopyLink(channel)
        } label: {
            Label("Copy Link", systemImage: "link")
        }
    }
}

// MARK: - Preview

#Preview("Channel Rows") {
    let channels = [
        DiscussionChannel(id: "1", name: "General", description: "Welcome & announcements", icon: "house.fill", unreadCount: 3, isPinned: true, isLocked: false, lastActivityAt: Date()),
        DiscussionChannel(id: "2", name: "Prayer Requests", description: "Share your requests here", icon: "hands.sparkles.fill", unreadCount: 0, isPinned: false, isLocked: false, lastActivityAt: Date()),
        DiscussionChannel(id: "3", name: "Study Notes", description: "This week's passages", icon: "book.fill", unreadCount: 12, isPinned: false, isLocked: false, lastActivityAt: Date()),
        DiscussionChannel(id: "4", name: "Leadership Lounge", description: "Admins only", icon: "person.badge.shield.checkmark.fill", unreadCount: 0, isPinned: false, isLocked: true, lastActivityAt: nil),
    ]
    LazyVStack(spacing: 0) {
        ForEach(Array(channels.enumerated()), id: \.element.id) { i, ch in
            DiscussionChannelRow(channel: ch, index: i)
            if i < channels.count - 1 {
                Divider().padding(.leading, 64)
            }
        }
    }
    .padding(.vertical, 8)
    .background(Color(.systemBackground))
}
