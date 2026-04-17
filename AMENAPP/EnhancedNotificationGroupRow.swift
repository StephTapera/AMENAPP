//
//  EnhancedNotificationGroupRow.swift
//  AMENAPP
//
//  Enhanced wrapper around GroupedNotificationRow that adds
//  a combined multi-action summary strip and unread pulse indicator
//  for grouped notifications with mixed action types.
//

import SwiftUI

// MARK: - Enhanced Notification Group Row

struct EnhancedNotificationGroupRow: View {
    let group: NotificationGroup
    let onDismiss: () -> Void
    let onMarkAsRead: () -> Void
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onAvatarTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Standard grouped row
            GroupedNotificationRow(
                group: group,
                onDismiss: onDismiss,
                onMarkAsRead: onMarkAsRead,
                onTap: onTap,
                onLongPress: onLongPress,
                onAvatarTap: onAvatarTap
            )

            // Mixed action summary strip (when group contains different notification types)
            if group.isGrouped, mixedActionTypes.count > 1 {
                mixedActionSummary
            }
        }
    }

    // MARK: - Mixed Action Types

    private var mixedActionTypes: [AppNotification.NotificationType] {
        let types = Set(group.notifications.map(\.type))
        return Array(types).sorted { $0.rawValue < $1.rawValue }
    }

    @ViewBuilder
    private var mixedActionSummary: some View {
        HStack(spacing: 6) {
            ForEach(mixedActionTypes, id: \.rawValue) { type in
                HStack(spacing: 3) {
                    Image(systemName: iconForType(type))
                        .font(.systemScaled(10, weight: .semibold))
                    Text(labelForType(type))
                        .font(AMENFont.regular(11))
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 74) // align with text content after avatar + unread dot
        .padding(.bottom, 8)
    }

    private func iconForType(_ type: AppNotification.NotificationType) -> String {
        switch type {
        case .amen:                    return "hands.clap.fill"
        case .comment, .reply:         return "bubble.left.fill"
        case .follow:                  return "person.badge.plus"
        case .mention:                 return "at"
        case .repost:                  return "arrow.2.squarepath"
        default:                       return "bell.fill"
        }
    }

    private func labelForType(_ type: AppNotification.NotificationType) -> String {
        switch type {
        case .amen:                    return "amens"
        case .comment:                 return "comments"
        case .reply:                   return "replies"
        case .follow:                  return "follows"
        case .mention:                 return "mentions"
        case .repost:                  return "reposts"
        default:                       return type.rawValue
        }
    }
}
