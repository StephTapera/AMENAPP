//
//  AMENNotificationsView.swift
//  AMENAPP
//
//  Premium Liquid Glass notifications screen.
//  Pure UI + local state — Firebase wiring can be added later.
//

import SwiftUI
import Combine

// MARK: - Notification Type

enum NotificationType: String, CaseIterable, Hashable {
    case bereanInsight  = "bereanInsight"
    case mention        = "mention"
    case reaction       = "reaction"
    case comment        = "comment"
    case communityInvite = "communityInvite"
    case system         = "system"

    var label: String {
        switch self {
        case .bereanInsight:  return "Berean AI"
        case .mention:        return "Mentions"
        case .reaction:       return "Reactions"
        case .comment:        return "Comments"
        case .communityInvite: return "Community"
        case .system:         return "System"
        }
    }

    var iconName: String {
        switch self {
        case .bereanInsight:  return "sparkles"
        case .mention:        return "at"
        case .reaction:       return "heart.fill"
        case .comment:        return "bubble.left.fill"
        case .communityInvite: return "person.2.fill"
        case .system:         return "bell.fill"
        }
    }

    /// Display order — lower index = higher priority in list
    var sortOrder: Int {
        switch self {
        case .bereanInsight:  return 0
        case .mention:        return 1
        case .reaction:       return 2
        case .comment:        return 3
        case .communityInvite: return 4
        case .system:         return 5
        }
    }
}

// MARK: - Data Model

struct AMENNotification: Identifiable {
    let id: String
    let type: NotificationType
    let actorName: String
    let actorInitials: String
    let body: String
    let timestamp: Date
    var isRead: Bool
    var isGrouped: Bool = false
}

// MARK: - ViewModel

@MainActor
final class AMENNotificationsViewModel: ObservableObject {

    @Published var notifications: [AMENNotification]
    @Published var focusModeOn: Bool = false
    @Published var collapsedGroups: Set<NotificationType> = []

    // MARK: Derived

    var filteredNotifications: [AMENNotification] {
        if focusModeOn {
            return notifications.filter { $0.type == .mention || $0.type == .bereanInsight }
        }
        return notifications
    }

    /// All types that have at least one notification in the filtered set, sorted by priority.
    var visibleGroups: [NotificationType] {
        let presentTypes = Set(filteredNotifications.map { $0.type })
        return NotificationType.allCases
            .filter { presentTypes.contains($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func notifications(for type: NotificationType) -> [AMENNotification] {
        filteredNotifications
            .filter { $0.type == type }
            .sorted { (!$0.isRead && $1.isRead) || ($0.isRead == $1.isRead && $0.timestamp > $1.timestamp) }
    }

    var unreadCount: Int {
        filteredNotifications.filter { !$0.isRead }.count
    }

    // MARK: Mutations

    func markAllRead() {
        for index in notifications.indices {
            notifications[index].isRead = true
        }
    }

    func markRead(_ id: String) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
        }
    }

    func dismiss(_ id: String) {
        notifications.removeAll { $0.id == id }
    }

    // MARK: Init with sample data

    init() {
        let now = Date()
        notifications = [
            AMENNotification(
                id: "1",
                type: .bereanInsight,
                actorName: "Berean AI",
                actorInitials: "BA",
                body: "Berean has an insight for you about Romans 8:28",
                timestamp: now.addingTimeInterval(-120),
                isRead: false
            ),
            AMENNotification(
                id: "2",
                type: .bereanInsight,
                actorName: "Berean AI",
                actorInitials: "BA",
                body: "Berean has an insight for you about your recent post on forgiveness",
                timestamp: now.addingTimeInterval(-3600),
                isRead: true
            ),
            AMENNotification(
                id: "3",
                type: .mention,
                actorName: "Marcus Johnson",
                actorInitials: "MJ",
                body: "Marcus Johnson mentioned you in a post",
                timestamp: now.addingTimeInterval(-600),
                isRead: false
            ),
            AMENNotification(
                id: "4",
                type: .mention,
                actorName: "Priya Osei",
                actorInitials: "PO",
                body: "Priya Osei mentioned you in a post",
                timestamp: now.addingTimeInterval(-7200),
                isRead: true
            ),
            AMENNotification(
                id: "5",
                type: .reaction,
                actorName: "David Kim",
                actorInitials: "DK",
                body: "David Kim reacted to your post",
                timestamp: now.addingTimeInterval(-900),
                isRead: false
            ),
            AMENNotification(
                id: "6",
                type: .reaction,
                actorName: "Sarah Mwangi",
                actorInitials: "SM",
                body: "Sarah Mwangi reacted to your post",
                timestamp: now.addingTimeInterval(-1800),
                isRead: false
            ),
            AMENNotification(
                id: "7",
                type: .reaction,
                actorName: "James Okafor",
                actorInitials: "JO",
                body: "James Okafor reacted to your post",
                timestamp: now.addingTimeInterval(-10800),
                isRead: true
            ),
            AMENNotification(
                id: "8",
                type: .comment,
                actorName: "Rachel Torres",
                actorInitials: "RT",
                body: "Rachel Torres commented: 'This really blessed me today, thank you!'",
                timestamp: now.addingTimeInterval(-1200),
                isRead: false
            ),
            AMENNotification(
                id: "9",
                type: .comment,
                actorName: "Emmanuel Adeyemi",
                actorInitials: "EA",
                body: "Emmanuel Adeyemi commented: 'Amen! Sharing this with my small group'",
                timestamp: now.addingTimeInterval(-5400),
                isRead: true
            ),
            AMENNotification(
                id: "10",
                type: .communityInvite,
                actorName: "Grace Fellowship",
                actorInitials: "GF",
                body: "Grace Fellowship invited you to Sunday Morning Prayers",
                timestamp: now.addingTimeInterval(-14400),
                isRead: false
            ),
            AMENNotification(
                id: "11",
                type: .system,
                actorName: "AMEN",
                actorInitials: "AM",
                body: "Your profile is 80% complete. Add a bio to connect better.",
                timestamp: now.addingTimeInterval(-86400),
                isRead: true
            ),
        ]
    }
}

// MARK: - Helpers

private func relativeTimestamp(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    switch interval {
    case ..<60:
        return "just now"
    case 60..<3600:
        let m = Int(interval / 60)
        return "\(m)m ago"
    case 3600..<86400:
        let h = Int(interval / 3600)
        return "\(h)h ago"
    default:
        let d = Int(interval / 86400)
        return "\(d)d ago"
    }
}

// MARK: - Glass background modifier

private struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 4)
            )
    }
}

private extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Avatar View

private struct NotificationAvatar: View {
    let initials: String
    let type: NotificationType

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color.white.opacity(0.55)))
                .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)

            if type == .bereanInsight || type == .system {
                Image(systemName: type.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.7))
            } else {
                Text(initials)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color.black.opacity(0.8))
            }
        }
    }
}

// MARK: - Notification Card

private struct NotificationCard: View {
    let notification: AMENNotification
    let index: Int
    let onMarkRead: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var showContextMenu = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Unread indicator
            Circle()
                .fill(notification.isRead ? Color.clear : Color.black)
                .frame(width: 8, height: 8)
                .padding(.top, 18)

            NotificationAvatar(initials: notification.actorInitials, type: notification.type)

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.body)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(Color.black)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(notification.actorName)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(Color(white: 0.45))

                Text(relativeTimestamp(notification.timestamp))
                    .font(AMENFont.regular(12))
                    .foregroundStyle(Color(white: 0.65))
            }
            .padding(.vertical, 4)

            Spacer(minLength: 0)

            // Type icon badge
            Image(systemName: notification.type.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.55))
                .padding(.top, 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -12)
        .onAppear {
            withAnimation(
                .spring(response: 0.35, dampingFraction: 0.80)
                .delay(Double(index) * 0.05)
            ) {
                appeared = true
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                    onDismiss()
                }
            } label: {
                Label("Clear", systemImage: "xmark.circle.fill")
            }
            .tint(.red)
        }
        .contextMenu {
            Button {
                onMarkRead()
            } label: {
                Label("Mark Read", systemImage: "checkmark.circle")
            }
            Button {
                // Mute — wired to type muting logic when backend is added
            } label: {
                Label("Mute this type", systemImage: "bell.slash")
            }
            Button {
                // View detail — navigation wired when backend is added
            } label: {
                Label("View", systemImage: "arrow.right.circle")
            }
        }
    }
}

// MARK: - Group Section Header

private struct GroupSectionHeader: View {
    let type: NotificationType
    let unreadCount: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: type.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.75))
                    .frame(width: 20)

                Text(type.label)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(Color.black)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.55))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .animation(.spring(response: 0.35, dampingFraction: 0.80), value: isCollapsed)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Focus Mode Pill

private struct FocusModePill: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "moon.fill" : "moon")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.75))

            Text("Focus Mode")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(Color.black)

            Text(isOn ? "ON" : "OFF")
                .font(AMENFont.bold(12))
                .foregroundStyle(isOn ? Color.black : Color(white: 0.55))

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.black)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 3)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.80), value: isOn)
    }
}

// MARK: - Empty State

private struct NotificationsEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.55)))
                    .overlay(Circle().strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5))
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 4)

                Image(systemName: "bell.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.6))
            }

            VStack(spacing: 6) {
                Text("You're all caught up")
                    .font(AMENFont.semiBold(17))
                    .foregroundStyle(Color.black)

                Text("New activity will appear here")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(32)
        .glassCard(cornerRadius: 20)
        .padding(.horizontal, 24)
    }
}

// MARK: - Main View

struct AMENNotificationsView: View {
    @StateObject private var viewModel = AMENNotificationsViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                if viewModel.filteredNotifications.isEmpty {
                    emptyStateContent
                } else {
                    notificationsList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.unreadCount > 0 {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                viewModel.markAllRead()
                            }
                        } label: {
                            Text("Mark all read")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(Color.black)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State Content

    private var emptyStateContent: some View {
        VStack(spacing: 24) {
            FocusModePill(isOn: $viewModel.focusModeOn)
                .padding(.top, 8)

            Spacer()
            NotificationsEmptyState()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20, pinnedViews: []) {

                // Focus Mode Pill
                FocusModePill(isOn: $viewModel.focusModeOn)
                    .padding(.top, 4)
                    .padding(.horizontal, 2)

                // Groups
                ForEach(viewModel.visibleGroups, id: \.self) { groupType in
                    groupSection(for: groupType)
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // MARK: - Group Section

    @ViewBuilder
    private func groupSection(for type: NotificationType) -> some View {
        let items = viewModel.notifications(for: type)
        let unread = items.filter { !$0.isRead }.count
        let isCollapsed = viewModel.collapsedGroups.contains(type)

        VStack(spacing: 0) {
            // Section header
            GroupSectionHeader(
                type: type,
                unreadCount: unread,
                isCollapsed: isCollapsed
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.80)) {
                    if isCollapsed {
                        viewModel.collapsedGroups.remove(type)
                    } else {
                        viewModel.collapsedGroups.insert(type)
                    }
                }
            }

            // Cards
            if !isCollapsed {
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, notification in
                        NotificationCard(
                            notification: notification,
                            index: index
                        ) {
                            viewModel.markRead(notification.id)
                        } onDismiss: {
                            viewModel.dismiss(notification.id)
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard(cornerRadius: 20)
        .padding(.vertical, 1)
    }
}

// MARK: - Preview

struct AMENNotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AMENNotificationsView()
                .previewDisplayName("Default — Light")

            AMENNotificationsView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
