//
//  AMENNotificationsView.swift
//  AMENAPP
//
//  Premium Liquid Glass notifications screen.
//  Wired to Firestore — loads real notifications for the authenticated user.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

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
    // Deep-link routing fields — populated by Firebase backend.
    var postId: String? = nil
    var actorId: String? = nil
    var commentId: String? = nil
    var conversationId: String? = nil

    /// Decode from a Firestore document. Returns nil if required fields are missing.
    init?(from doc: DocumentSnapshot) {
        guard let data = doc.data(),
              let typeRaw = data["type"] as? String,
              let notifType = NotificationType(rawValue: typeRaw),
              let actorName = data["actorName"] as? String,
              let body = data["body"] as? String
        else { return nil }

        self.id = doc.documentID
        self.type = notifType
        self.actorName = actorName
        self.body = body
        let readValue = (data["read"] as? Bool) ?? (data["isRead"] as? Bool) ?? false
        self.isRead = readValue
        self.postId = data["postId"] as? String
        self.actorId = data["actorId"] as? String
        self.commentId = data["commentId"] as? String
        self.conversationId = data["conversationId"] as? String

        // Compute initials from actorName
        self.actorInitials = actorName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map { String($0) } }
            .joined()
            .uppercased()

        // Firestore timestamp → Date
        if let ts = data["timestamp"] as? Timestamp {
            self.timestamp = ts.dateValue()
        } else {
            self.timestamp = Date()
        }
    }
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
        Task { await markReadRemote(id) }
    }

    func markReadRemote(_ id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("notifications")
            .document(id)
        do {
            try await ref.setData(["read": true, "isRead": true], merge: true)
        } catch {
            dlog("❌ Failed to mark notification read: \(error.localizedDescription)")
        }
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
        }
        await BadgeCountManager.shared.immediateUpdate()
    }

    func dismiss(_ id: String) {
        notifications.removeAll { $0.id == id }
    }

    // MARK: - Init

    init() {
        notifications = []
    }

    // MARK: - Firestore Loading

    private var listener: ListenerRegistration?

    /// Start a real-time listener for the current user's notifications collection.
    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("notifications")
            .order(by: "timestamp", descending: true)
            .limit(to: 60)
            .addSnapshotListener { [weak self] snap, error in
                guard let self, let snap, error == nil else { return }
                Task { @MainActor in
                    self.notifications = snap.documents.compactMap { doc in
                        AMENNotification(from: doc)
                    }
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Mark all notifications read in Firestore + locally.
    func markAllReadRemote() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let batch = Firestore.firestore().batch()
        let ref = Firestore.firestore().collection("users").document(uid).collection("notifications")
        for n in notifications where !n.isRead {
            batch.setData(["read": true, "isRead": true], forDocument: ref.document(n.id), merge: true)
        }
        Task {
            try? await batch.commit()
            markAllRead()
            BadgeCountManager.shared.clearNotifications()
            await BadgeCountManager.shared.immediateUpdate()
        }
    }

    /// Delete a notification from Firestore + locally.
    func dismissRemote(_ id: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("notifications").document(id)
            .delete()
        dismiss(id)
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
                            .fill(AmenTheme.Colors.glassFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                    )
                    .shadow(color: AmenTheme.Colors.shadowCard, radius: 14, x: 0, y: 4)
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
                .overlay(Circle().fill(AmenTheme.Colors.glassFill))
                .overlay(Circle().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                .frame(width: 44, height: 44)
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, x: 0, y: 2)

            if type == .bereanInsight || type == .system {
                Image(systemName: type.iconName)
                    .font(.systemScaled(18, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.iconPrimary)
            } else {
                Text(initials)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
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
    let onTap: () -> Void

    @State private var appeared = false
    @State private var showContextMenu = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Unread indicator
            Circle()
                .fill(notification.isRead ? Color.clear : AmenTheme.Colors.iconPrimary)
                .frame(width: 8, height: 8)
                .padding(.top, 18)

            NotificationAvatar(initials: notification.actorInitials, type: notification.type)

            VStack(alignment: .leading, spacing: 3) {
                Text(notification.body)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(notification.actorName)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)

                Text(relativeTimestamp(notification.timestamp))
                    .font(AMENFont.regular(12))
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            .padding(.vertical, 4)

            Spacer(minLength: 0)

            // Type icon badge
            Image(systemName: notification.type.iconName)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.iconSecondary)
                .padding(.top, 14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onTap() }
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
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.80))) {
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
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.iconPrimary)
                    .frame(width: 20)

                Text(type.label)
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.primary)

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(AmenTheme.Colors.buttonPrimaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AmenTheme.Colors.buttonPrimary))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
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
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.iconPrimary)

            Text("Focus Mode")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.primary)

            Text(isOn ? "ON" : "OFF")
                .font(AMENFont.bold(12))
                .foregroundStyle(isOn ? AmenTheme.Colors.iconPrimary : AmenTheme.Colors.iconSecondary)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AmenTheme.Colors.buttonPrimary)
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(AmenTheme.Colors.glassFill))
                .overlay(Capsule().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                .shadow(color: AmenTheme.Colors.shadowCard, radius: 12, x: 0, y: 3)
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
                    .overlay(Circle().fill(AmenTheme.Colors.glassFill))
                    .overlay(Circle().strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5))
                    .frame(width: 72, height: 72)
                    .shadow(color: AmenTheme.Colors.shadowCard, radius: 16, x: 0, y: 4)

                Image(systemName: "bell.fill")
                    .font(.systemScaled(28, weight: .medium))
                    .foregroundStyle(AmenTheme.Colors.iconSecondary)
            }

            VStack(spacing: 6) {
                Text("You're all caught up")
                    .font(AMENFont.semiBold(17))
                    .foregroundStyle(.primary)

                Text("New activity will appear here")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
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
                AmenTheme.Colors.backgroundGrouped
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
                            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.85))) {
                                viewModel.markAllReadRemote()
                            }
                        } label: {
                            Text("Mark all read")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .task {
                viewModel.startListening()
            }
            .onAppear {
                viewModel.markAllReadRemote()
                BadgeCountManager.shared.clearNotifications()
            }
            .onDisappear {
                viewModel.stopListening()
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
                withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.80))) {
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
                            viewModel.dismissRemote(notification.id)
                        } onTap: {
                            viewModel.markRead(notification.id)
                            routeNotification(notification)
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

    // MARK: - Routing

    /// Route an in-app notification tap to its canonical destination.
    /// Uses routing fields if present; falls back gracefully for sample/legacy data.
    private func routeNotification(_ notification: AMENNotification) {
        switch notification.type {

        case .mention, .comment, .reaction:
            if let postId = notification.postId, !postId.isEmpty {
                let route: NotificationRoute
                if let commentId = notification.commentId, !commentId.isEmpty {
                    route = .postComment(postID: postId, commentID: commentId)
                } else {
                    route = .post(postID: postId)
                }
                NotificationTapHandler.shared.execute(route)
            }
            // No postId → stay on notifications (graceful no-op for sample data)

        case .bereanInsight:
            break // Berean insight — stays in notifications; no external destination

        case .communityInvite:
            NotificationTapHandler.shared.execute(.fallback)

        case .system:
            break // System notifications — no deep destination
        }
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
