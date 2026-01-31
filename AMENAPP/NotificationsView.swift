//
//  NotificationsView.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//
//  Complete notification view with real-time Firebase integration
//  Features: Grouping, Smart Filters, Quick Actions, Performance Optimized
//

import SwiftUI
import UserNotifications
import FirebaseFirestore
import Combine

struct NotificationsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var followRequestsViewModel = FollowRequestsViewModel()
    @StateObject private var profileCache = NotificationProfileCache.shared
    @StateObject private var priorityEngine = NotificationPriorityEngine.shared
    @State private var selectedFilter: NotificationFilter = .all
    @State private var showFollowRequests = false
    @State private var isRefreshing = false
    @State private var showSettings = false
    @Namespace private var filterAnimation
    
    // Navigation state
    @State private var navigationPath = NavigationPath()
    
    // Quick Actions state
    @State private var showQuickActions = false
    @State private var quickActionNotification: AppNotification?
    @State private var quickReplyText = ""
    
    enum NotificationFilter: String, CaseIterable {
        case all = "All"
        case priority = "Priority" // AI/ML filtered
        case mentions = "Mentions"
        case reactions = "Reactions"
        case follows = "Follows"
        
        var icon: String {
            switch self {
            case .all: return "bell.fill"
            case .priority: return "sparkles"
            case .mentions: return "at"
            case .reactions: return "heart.fill"
            case .follows: return "person.2.fill"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Grouped notifications with smart aggregation
    private var groupedNotifications: [NotificationGroup] {
        let filtered = filteredNotifications
        
        // Group by post and type for aggregation
        var groups: [String: [AppNotification]] = [:]
        var standalone: [AppNotification] = []
        
        for notification in filtered {
            // Group reactions and comments by post
            if let postId = notification.postId,
               (notification.type == .amen || notification.type == .comment) {
                let key = "\(postId)_\(notification.type.rawValue)"
                groups[key, default: []].append(notification)
            } else {
                standalone.append(notification)
            }
        }
        
        // Create notification groups
        var result: [NotificationGroup] = []
        
        // Add grouped notifications
        for (_, groupNotifications) in groups {
            guard !groupNotifications.isEmpty else { continue }
            
            if groupNotifications.count > 1 {
                // Multiple users - create aggregated group
                result.append(NotificationGroup(notifications: groupNotifications))
            } else {
                // Single notification
                result.append(NotificationGroup(notifications: [groupNotifications[0]]))
            }
        }
        
        // Add standalone notifications
        for notification in standalone {
            result.append(NotificationGroup(notifications: [notification]))
        }
        
        // Sort by most recent
        result.sort { $0.mostRecentDate > $1.mostRecentDate }
        
        return result
    }
    
    private var filteredNotifications: [AppNotification] {
        var notifications = notificationService.notifications
        
        switch selectedFilter {
        case .all:
            break
        case .priority:
            // Use ML-powered priority filtering
            let priorityIds = priorityEngine.getPriorityNotificationIds()
            notifications = notifications.filter { notification in
                guard let id = notification.id else { return false }
                return priorityIds.contains(id)
            }
        case .mentions:
            notifications = notifications.filter { $0.type == .mention }
        case .reactions:
            notifications = notifications.filter { $0.type == .amen }
        case .follows:
            notifications = notifications.filter { $0.type == .follow }
        }
        
        return notifications
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Enhanced Header Section
                VStack(spacing: 16) {
                    // Title with Exit and Mark All Read
                    HStack(alignment: .center, spacing: 12) {
                        // Exit Button
                        Button {
                            dismiss()
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.05))
                                )
                        }
                        
                        Text("Notifications")
                            .font(.custom("OpenSans-Bold", size: 24))
                        
                        Spacer()
                        
                        // Unread count badge + Settings
                        HStack(spacing: 12) {
                            if unreadCount > 0 {
                                HStack(spacing: 8) {
                                    Text("\(unreadCount)")
                                        .font(.custom("OpenSans-Bold", size: 15))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule()
                                                .fill(Color.blue)
                                                .shadow(color: .blue.opacity(0.3), radius: 8, y: 2)
                                        )
                                    
                                    Button {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                            markAllAsRead()
                                        }
                                    } label: {
                                        Text("Mark all read")
                                            .font(.custom("OpenSans-SemiBold", size: 14))
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            
                            // Settings button
                            Button {
                                showSettings = true
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(Color.black.opacity(0.05))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Follow Requests Button
                    if followRequestsViewModel.requests.count > 0 {
                        Button {
                            showFollowRequests = true
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            HStack(spacing: 12) {
                                // Icon
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: "person.badge.clock.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.purple)
                                }
                                
                                // Text
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Follow Requests")
                                        .font(.custom("OpenSans-Bold", size: 16))
                                        .foregroundStyle(.primary)
                                    
                                    Text("\(followRequestsViewModel.requests.count) pending request\(followRequestsViewModel.requests.count == 1 ? "" : "s")")
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                // Badge + Arrow
                                HStack(spacing: 8) {
                                    Text("\(followRequestsViewModel.requests.count)")
                                        .font(.custom("OpenSans-Bold", size: 13))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.purple)
                                                .shadow(color: .purple.opacity(0.3), radius: 4, y: 2)
                                        )
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.purple.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                                    )
                                    .shadow(color: .purple.opacity(0.1), radius: 8, y: 2)
                            )
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Enhanced Filter Pills with Icons
                    modernFilterSection
                }
                .padding(.top)
                .background(Color(.systemBackground))
                
                // Notifications list with smart grouping
                if notificationService.isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if groupedNotifications.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(groupedNotifications) { group in
                                GroupedNotificationRow(
                                    group: group,
                                    onDismiss: {
                                        removeGroup(group)
                                    },
                                    onMarkAsRead: {
                                        markGroupAsRead(group)
                                    },
                                    onTap: {
                                        handleGroupTap(group)
                                    },
                                    onLongPress: {
                                        showQuickActions(for: group)
                                    }
                                )
                                .id(group.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                    }
                    .refreshable {
                        await refreshNotifications()
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showFollowRequests) {
                FollowRequestsView()
            }
            .sheet(isPresented: $showSettings) {
                NotificationSettingsSheet()
            }
            .sheet(isPresented: $showQuickActions) {
                if let notification = quickActionNotification {
                    QuickActionsSheet(
                        notification: notification,
                        replyText: $quickReplyText,
                        onReply: { handleQuickReply(notification) },
                        onMarkRead: { markAsRead(notification) },
                        onDismiss: { showQuickActions = false }
                    )
                    .presentationDetents([.height(300), .medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .onAppear {
                notificationService.startListening()
                clearBadgeCount()
                
                // Load follow requests and priority scores
                Task {
                    await followRequestsViewModel.loadRequests()
                    await priorityEngine.calculatePriorities(for: notificationService.notifications)
                }
            }
            .onDisappear {
                notificationService.stopListening()
            }
        }
    }
    
    // MARK: - Group Actions
    
    private func handleGroupTap(_ group: NotificationGroup) {
        // Mark all in group as read
        for notification in group.notifications where !notification.read {
            markAsRead(notification)
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Navigate to relevant content
        if let firstNotification = group.notifications.first {
            switch firstNotification.type {
            case .follow:
                if let actorId = firstNotification.actorId {
                    navigationPath.append("profile_\(actorId)")
                }
            case .amen, .comment, .mention, .reply:
                if let postId = firstNotification.postId {
                    navigationPath.append("post_\(postId)")
                }
            default:
                break
            }
        }
    }
    
    private func showQuickActions(for group: NotificationGroup) {
        guard let first = group.notifications.first else { return }
        quickActionNotification = first
        showQuickActions = true
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    private func handleQuickReply(_ notification: AppNotification) {
        guard !quickReplyText.isEmpty else { return }
        
        Task {
            // TODO: Implement quick reply to post/comment
            print("Quick reply: \(quickReplyText)")
            
            // Close sheet
            showQuickActions = false
            quickReplyText = ""
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    }
    
    private func markGroupAsRead(_ group: NotificationGroup) {
        for notification in group.notifications where !notification.read {
            markAsRead(notification)
        }
    }
    
    private func removeGroup(_ group: NotificationGroup) {
        for notification in group.notifications {
            removeNotification(notification)
        }
    }
    
    // MARK: - Refresh Handler
    
    private func refreshNotifications() async {
        isRefreshing = true
        
        // Reload notifications
        await notificationService.refresh()
        
        // Reload follow requests
        await followRequestsViewModel.loadRequests()
        
        // Recalculate priorities
        await priorityEngine.calculatePriorities(for: notificationService.notifications)
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        isRefreshing = false
    }
    
    // MARK: - Modern Filter Section
    private var modernFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(NotificationFilter.allCases, id: \.self) { filter in
                    filterPill(for: filter)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.gray.opacity(0.08))
                    .shadow(color: .black.opacity(0.03), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func filterPill(for filter: NotificationFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = notificationCount(for: filter)
        
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedFilter = filter
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                
                Text(filter.rawValue)
                    .font(.custom("OpenSans-Bold", size: 14))
                
                if count > 0 && filter != .all {
                    Text("\(count)")
                        .font(.custom("OpenSans-Bold", size: 11))
                        .foregroundStyle(isSelected ? .white : .blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white.opacity(0.3) : Color.blue.opacity(0.15))
                        )
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.black)
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                            .matchedGeometryEffect(id: "selectedFilter", in: filterAnimation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                    }
                }
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.05), radius: 20, y: 10)
                
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text("No notifications")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)
                
                Text("You're all caught up!")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Helper Functions
    private var unreadCount: Int {
        notificationService.unreadCount
    }
    
    private func notificationCount(for filter: NotificationFilter) -> Int {
        guard filter != .all else { return unreadCount }
        
        let filtered = notificationService.notifications.filter { !$0.read }
        
        switch filter {
        case .all:
            return unreadCount
        case .priority:
            let priorityIds = priorityEngine.getPriorityNotificationIds()
            return filtered.filter { notification in
                guard let id = notification.id else { return false }
                return priorityIds.contains(id)
            }.count
        case .mentions:
            return filtered.filter { $0.type == .mention }.count
        case .reactions:
            return filtered.filter { $0.type == .amen }.count
        case .follows:
            return filtered.filter { $0.type == .follow }.count
        }
    }
    
    private func markAllAsRead() {
        Task {
            try? await notificationService.markAllAsRead()
        }
        
        // Update badge count
        clearBadgeCount()
    }
    
    private func markAsRead(_ notification: AppNotification) {
        Task {
            guard let id = notification.id else { return }
            try? await notificationService.markAsRead(id)
        }
    }
    
    private func muteUser(_ userName: String) {
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // TODO: Implement muting in future
        print("🔇 Muted notifications from \(userName)")
    }
    
    private func removeNotification(_ notification: AppNotification) {
        Task {
            guard let id = notification.id else { return }
            try? await notificationService.deleteNotification(id)
        }
    }
    
    // MARK: - Badge Management
    
    /// Clear app badge count when viewing notifications
    private func clearBadgeCount() {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }
}

// MARK: - Notification Group Model

struct NotificationGroup: Identifiable {
    let id = UUID()
    let notifications: [AppNotification]
    
    var isGrouped: Bool {
        notifications.count > 1
    }
    
    var primaryNotification: AppNotification {
        notifications.first!
    }
    
    var otherCount: Int {
        max(0, notifications.count - 1)
    }
    
    var mostRecentDate: Date {
        notifications.map { $0.createdAt.dateValue() }.max() ?? Date()
    }
    
    var hasUnread: Bool {
        notifications.contains { !$0.read }
    }
    
    var actorNames: [String] {
        notifications.compactMap { $0.actorName }
    }
    
    var displayText: String {
        if isGrouped {
            let first = actorNames.first ?? "Someone"
            let others = otherCount
            return "\(first) and \(others) other\(others == 1 ? "" : "s") \(primaryNotification.actionText)"
        } else {
            return primaryNotification.actionText
        }
    }
}

// MARK: - Grouped Notification Row

struct GroupedNotificationRow: View {
    let group: NotificationGroup
    let onDismiss: () -> Void
    let onMarkAsRead: () -> Void
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    @StateObject private var profileCache = NotificationProfileCache.shared
    @State private var actorProfile: CachedProfile?
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                // Avatar or stacked avatars
                avatarView
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // User action text
                    if group.isGrouped {
                        // Grouped: "John and 3 others liked your post"
                        HStack(spacing: 0) {
                            Text(group.actorNames.first ?? "Someone")
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Text(" and \(group.otherCount) other\(group.otherCount == 1 ? "" : "s") ")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                            
                            Text(group.primaryNotification.actionText)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(2)
                    } else {
                        // Single notification
                        HStack(spacing: 0) {
                            if let actorName = group.primaryNotification.actorName {
                                Text(actorName)
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(.primary)
                                
                                Text(" " + group.primaryNotification.actionText)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(group.primaryNotification.actionText)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(2)
                    }
                    
                    // Comment preview
                    if let commentText = group.primaryNotification.commentText {
                        Text(commentText)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.08))
                            )
                    }
                    
                    // Time ago
                    Text(group.primaryNotification.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(group.hasUnread ? Color.blue.opacity(0.04) : Color(.systemBackground))
                    .shadow(
                        color: .black.opacity(group.hasUnread ? 0.06 : 0.04),
                        radius: 12,
                        y: 4
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                onMarkAsRead()
            } label: {
                Label("Mark as Read", systemImage: "envelope.open")
            }
            
            Button(role: .destructive) {
                onDismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onLongPressGesture {
            onLongPress()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onMarkAsRead()
            } label: {
                Label("Read", systemImage: "envelope.open")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            // Load profile for avatar
            if let actorId = group.primaryNotification.actorId {
                actorProfile = await profileCache.getProfile(userId: actorId)
            }
        }
    }
    
    @ViewBuilder
    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main avatar
            if group.isGrouped {
                // Stacked avatars for groups
                ZStack(alignment: .topTrailing) {
                    // Back avatar
                    Circle()
                        .fill(group.primaryNotification.color.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: group.primaryNotification.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(group.primaryNotification.color)
                        )
                    
                    // Front avatar (slightly offset)
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .fill(group.primaryNotification.color.opacity(0.3))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Text("+\(group.otherCount)")
                                        .font(.custom("OpenSans-Bold", size: 12))
                                        .foregroundStyle(group.primaryNotification.color)
                                )
                        )
                        .offset(x: 12, y: -12)
                }
                .frame(width: 56, height: 56)
            } else if let profile = actorProfile,
                      let imageURL = profile.imageURL,
                      !imageURL.isEmpty {
                // Real profile image
                AsyncImage(url: URL(string: imageURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    case .failure, .empty:
                        Circle()
                            .fill(group.primaryNotification.color.opacity(0.2))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(profile.initials)
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(group.primaryNotification.color)
                            )
                    @unknown default:
                        Circle()
                            .fill(group.primaryNotification.color.opacity(0.2))
                            .frame(width: 56, height: 56)
                    }
                }
            } else {
                // Fallback icon
                Circle()
                    .fill(group.primaryNotification.color.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: group.primaryNotification.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(group.primaryNotification.color)
                    )
            }
            
            // Unread indicator
            if group.hasUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
            }
        }
    }
}


// MARK: - Notification Item Model (Legacy - for reference only)
struct NotificationItem: Identifiable {
    let id = UUID()
    let type: NotificationType
    let userName: String
    let userInitials: String
    let action: String
    let timeAgo: String
    let timestamp: Date
    var isRead: Bool
    let avatarColor: Color
    let postContent: String?
    let priorityScore: Double // 0.0 to 1.0 for AI/ML filtering
    
    enum NotificationType {
        case reaction
        case comment
        case follow
        case mention
        
        var icon: String {
            switch self {
            case .reaction: return "hands.sparkles.fill"
            case .comment: return "bubble.left.fill"
            case .follow: return "person.fill.badge.plus"
            case .mention: return "at.circle.fill"
            }
        }
        
        var accentColor: Color {
            switch self {
            case .reaction: return .blue
            case .comment: return .purple
            case .follow: return .green
            case .mention: return .orange
            }
        }
    }
    
    /// Categorize notification by time
    var timeCategory: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(timestamp) {
            return "Today"
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else if calendar.isDate(timestamp, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(timestamp, equalTo: now, toGranularity: .month) {
            return "This Month"
        } else {
            return "Earlier"
        }
    }
    
    static let sampleNotifications = [
        NotificationItem(
            type: .reaction,
            userName: "Sarah Chen",
            userInitials: "SC",
            action: "lit a lightbulb on your post",
            timeAgo: "2m",
            timestamp: Date().addingTimeInterval(-120),
            isRead: false,
            avatarColor: .blue,
            postContent: "\"God's timing is perfect...\"",
            priorityScore: 0.85
        ),
        NotificationItem(
            type: .follow,
            userName: "David Martinez",
            userInitials: "DM",
            action: "started following you",
            timeAgo: "15m",
            timestamp: Date().addingTimeInterval(-900),
            isRead: false,
            avatarColor: .green,
            postContent: nil,
            priorityScore: 0.65
        ),
        NotificationItem(
            type: .comment,
            userName: "Emily Rodriguez",
            userInitials: "ER",
            action: "commented on your testimony",
            timeAgo: "1h",
            timestamp: Date().addingTimeInterval(-3600),
            isRead: false,
            avatarColor: .purple,
            postContent: "\"Amen! So powerful! 🙏\"",
            priorityScore: 0.92
        ),
        NotificationItem(
            type: .mention,
            userName: "Michael Thompson",
            userInitials: "MT",
            action: "mentioned you in a post",
            timeAgo: "2h",
            timestamp: Date().addingTimeInterval(-7200),
            isRead: true,
            avatarColor: .orange,
            postContent: "\"@you check this sermon out!\"",
            priorityScore: 0.78
        ),
        NotificationItem(
            type: .reaction,
            userName: "Rachel Kim",
            userInitials: "RK",
            action: "prayed for your request",
            timeAgo: "3h",
            timestamp: Date().addingTimeInterval(-10800),
            isRead: true,
            avatarColor: .red,
            postContent: nil,
            priorityScore: 0.95
        ),
        NotificationItem(
            type: .follow,
            userName: "James Wilson",
            userInitials: "JW",
            action: "started following you",
            timeAgo: "Yesterday",
            timestamp: Date().addingTimeInterval(-86400),
            isRead: true,
            avatarColor: .cyan,
            postContent: nil,
            priorityScore: 0.45
        ),
        NotificationItem(
            type: .comment,
            userName: "Lisa Anderson",
            userInitials: "LA",
            action: "replied to your comment",
            timeAgo: "2d",
            timestamp: Date().addingTimeInterval(-172800),
            isRead: true,
            avatarColor: .indigo,
            postContent: "\"Yes! Trusting His plan ✨\"",
            priorityScore: 0.72
        )
    ]
}

// MARK: - Real Notification Row (Simplified for Cloud Functions data)

struct RealNotificationRow: View {
    let notification: AppNotification
    let onDismiss: () -> Void
    let onMarkAsRead: () -> Void
    let onTap: () -> Void
    
    @StateObject private var profileCache = NotificationProfileCache.shared
    @State private var actorProfile: CachedProfile?
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 14) {
                // Avatar with notification icon + REAL PROFILE IMAGE
                ZStack(alignment: .bottomTrailing) {
                    // Main avatar with profile image
                    Group {
                        if let actorProfile = actorProfile,
                           let imageURL = actorProfile.imageURL,
                           !imageURL.isEmpty {
                            AsyncImage(url: URL(string: imageURL)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(Circle())
                                case .failure(_), .empty:
                                    Circle()
                                        .fill(notification.color.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Text(actorProfile.initials)
                                                .font(.custom("OpenSans-Bold", size: 18))
                                                .foregroundStyle(notification.color)
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(notification.color.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                }
                            }
                        } else {
                            // Fallback to colored circle with icon
                            Circle()
                                .fill(notification.color.opacity(0.2))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: notification.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(notification.color)
                                )
                        }
                    }
                    
                    // Unread indicator
                    if !notification.read {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // User action text
                    HStack(spacing: 0) {
                        if let actorName = notification.actorName {
                            Text(actorName)
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Text(" " + notification.actionText)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(notification.actionText)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(2)
                    
                    // Comment preview (if available)
                    if let commentText = notification.commentText {
                        Text(commentText)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.08))
                            )
                    }
                    
                    // Time ago
                    Text(notification.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(notification.read ? Color(.systemBackground) : Color.blue.opacity(0.04))
                    .shadow(
                        color: .black.opacity(notification.read ? 0.04 : 0.06),
                        radius: 12,
                        y: 4
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onMarkAsRead()
            } label: {
                Label(notification.read ? "Unread" : "Read", systemImage: notification.read ? "envelope.badge" : "envelope.open")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            // Load actor profile for avatar
            if let actorId = notification.actorId {
                actorProfile = await profileCache.getProfile(userId: actorId)
            }
        }
    }
}

// MARK: - Old Enhanced Notification Row (Keeping for reference)
struct EnhancedNotificationRow: View {
    let notification: NotificationItem
    let onDismiss: () -> Void
    let onMarkAsRead: () -> Void
    let onMute: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isPressed = false
    @State private var showActions = false
    @State private var navigateToDestination = false
    
    var body: some View {
        Button {
            handleNotificationTap()
        } label: {
            HStack(spacing: 14) {
                // Enhanced Avatar
                ZStack(alignment: .bottomTrailing) {
                    // Main avatar
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        notification.avatarColor.opacity(0.3),
                                        notification.avatarColor.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: notification.avatarColor.opacity(0.2), radius: 8, y: 4)
                        
                        Text(notification.userInitials)
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(notification.avatarColor)
                    }
                    
                    // Notification type badge
                    ZStack {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        
                        Image(systemName: notification.type.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(notification.type.accentColor)
                            .symbolEffect(.bounce, value: !notification.isRead)
                    }
                    .offset(x: 2, y: 2)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // User action text
                    HStack(spacing: 0) {
                        Text(notification.userName)
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        
                        Text(" " + notification.action)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                        
                        // Priority indicator (AI/ML)
                        if notification.priorityScore >= 0.85 {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(.leading, 4)
                        }
                    }
                    .lineLimit(2)
                    
                    // Post content preview (if available)
                    if let content = notification.postContent {
                        Text(content)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.08))
                            )
                    }
                    
                    // Time ago
                    Text(notification.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                // Unread indicator
                if !notification.isRead {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .shadow(color: .blue.opacity(0.4), radius: 4, y: 1)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(notification.isRead ? Color(.systemBackground) : Color.blue.opacity(0.04))
                    .shadow(
                        color: .black.opacity(notification.isRead ? 0.04 : 0.06),
                        radius: 12,
                        y: 4
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                notification.isRead ? Color.clear : Color.blue.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.easeIn(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPressed = false
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { gesture in
                        if gesture.translation.width < 0 {
                            offset = gesture.translation.width
                        }
                    }
                    .onEnded { gesture in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if gesture.translation.width < -100 {
                                offset = -80
                                showActions = true
                            } else {
                                offset = 0
                                showActions = false
                            }
                        }
                    }
            )
        }
        .buttonStyle(PlainButtonStyle())
        // iOS Mail-style swipe actions
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onMarkAsRead()
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } label: {
                Label(notification.isRead ? "Unread" : "Read", systemImage: notification.isRead ? "envelope.badge" : "envelope.open")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDismiss()
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.warning)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                onMute()
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            } label: {
                Label("Mute", systemImage: "bell.slash")
            }
            .tint(.orange)
        }
        // Context menu with preview (Haptic preview)
        .contextMenu {
            Button {
                handleNotificationTap()
            } label: {
                Label("View", systemImage: "eye")
            }
            
            Button {
                onMarkAsRead()
            } label: {
                Label(notification.isRead ? "Mark as Unread" : "Mark as Read", 
                      systemImage: notification.isRead ? "envelope.badge" : "envelope.open")
            }
            
            Button {
                onMute()
            } label: {
                Label("Mute \(notification.userName)", systemImage: "bell.slash")
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } preview: {
            NotificationPreviewView(notification: notification)
        }
        .overlay(alignment: .trailing) {
            if showActions {
                HStack(spacing: 12) {
                    // Delete button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onDismiss()
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.red)
                                    .shadow(color: .red.opacity(0.3), radius: 8, y: 2)
                            )
                    }
                }
                .padding(.trailing, 16)
                .transition(.move(edge: .trailing))
            }
        }
    }
    
    // MARK: - Navigation Handler
    
    private func handleNotificationTap() {
        // Mark notification as read
        // In a real app, you'd update this in your data store
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Navigate based on notification type
        switch notification.type {
        case .reaction:
            // Navigate to the post that received the reaction
            navigateToPost()
            
        case .comment:
            // Navigate to the post with the comment
            navigateToPostComments()
            
        case .follow:
            // Navigate to the user's profile who followed
            navigateToUserProfile()
            
        case .mention:
            // Navigate to the post where user was mentioned
            navigateToMentionedPost()
        }
    }
    
    private func navigateToPost() {
        // TODO: Implement navigation to post detail
        // For now, we'll post a notification that can be handled by the main app
        NotificationCenter.default.post(
            name: .navigateToPost,
            object: nil,
            userInfo: [
                "userName": notification.userName,
                "action": "reaction",
                "content": notification.postContent ?? ""
            ]
        )
        print("📍 Navigating to post from \(notification.userName)")
    }
    
    private func navigateToPostComments() {
        // TODO: Implement navigation to post comments
        NotificationCenter.default.post(
            name: .navigateToPost,
            object: nil,
            userInfo: [
                "userName": notification.userName,
                "action": "comment",
                "content": notification.postContent ?? "",
                "scrollToComments": true
            ]
        )
        print("📍 Navigating to post comments from \(notification.userName)")
    }
    
    private func navigateToUserProfile() {
        // TODO: Implement navigation to user profile
        NotificationCenter.default.post(
            name: .navigateToProfile,
            object: nil,
            userInfo: [
                "userName": notification.userName,
                "userInitials": notification.userInitials
            ]
        )
        print("📍 Navigating to profile of \(notification.userName)")
    }
    
    private func navigateToMentionedPost() {
        // TODO: Implement navigation to mentioned post
        NotificationCenter.default.post(
            name: .navigateToPost,
            object: nil,
            userInfo: [
                "userName": notification.userName,
                "action": "mention",
                "content": notification.postContent ?? ""
            ]
        )
        print("📍 Navigating to mentioned post from \(notification.userName)")
    }
}

// MARK: - Old Notification Row (Keeping for reference but unused)
struct NotificationRow: View {
    let notification: NotificationItem
    
    var body: some View {
        Button {
            // Notification action
        } label: {
            HStack(spacing: 12) {
                // Avatar with notification icon
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(notification.avatarColor.opacity(0.2))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Text(notification.userInitials)
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(notification.avatarColor)
                        )
                    
                    // Notification type indicator
                    ZStack {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: notification.type.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(notification.avatarColor)
                    }
                    .offset(x: 4, y: 4)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(notification.userName)
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.primary)
                        
                        Text(notification.action)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(notification.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !notification.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(notification.isRead ? Color.clear : Color.blue.opacity(0.05))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Notification Names for Navigation

extension Notification.Name {
    static let navigateToPost = Notification.Name("navigateToPost")
    static let navigateToProfile = Notification.Name("navigateToProfile")
}

// MARK: - Notification Preview View (for Context Menu)

struct NotificationPreviewView: View {
    let notification: NotificationItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    notification.avatarColor.opacity(0.3),
                                    notification.avatarColor.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Text(notification.userInitials)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(notification.avatarColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.userName)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: notification.type.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(notification.type.accentColor)
                        
                        Text(notification.action)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Content Preview
            if let content = notification.postContent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    
                    Text(content)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                }
            }
            
            // Metadata
            HStack {
                Label(notification.timeAgo, systemImage: "clock")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Priority indicator
                if notification.priorityScore >= 0.85 {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("High Priority")
                            .font(.custom("OpenSans-Bold", size: 11))
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.yellow.opacity(0.15))
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        .onAppear {
            // Haptic feedback when preview appears
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
        }
    }
}

// MARK: - AI/ML Priority Scoring Helper

extension NotificationItem {
    /// Calculate priority score based on multiple factors
    /// In a real app, this would use on-device ML (Core ML)
    static func calculatePriorityScore(
        type: NotificationType,
        userName: String,
        hasContent: Bool,
        userInteractionHistory: [String: Double] = [:] // User interaction scores
    ) -> Double {
        var score = 0.0
        
        // Base score by type
        switch type {
        case .mention:
            score += 0.4
        case .comment:
            score += 0.3
        case .reaction:
            score += 0.2
        case .follow:
            score += 0.1
        }
        
        // Boost for content presence
        if hasContent {
            score += 0.2
        }
        
        // User relationship strength (simulated)
        // In real app: analyze message frequency, response rate, etc.
        let relationshipScore = userInteractionHistory[userName] ?? 0.3
        score += relationshipScore * 0.4
        
        // Recency boost (handled elsewhere with timestamp)
        
        return min(score, 1.0) // Cap at 1.0
    }
}

// MARK: - Quick Actions Sheet

struct QuickActionsSheet: View {
    let notification: AppNotification
    @Binding var replyText: String
    let onReply: () -> Void
    let onMarkRead: () -> Void
    let onDismiss: () -> Void
    @FocusState private var isReplyFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Actions")
                            .font(.custom("OpenSans-Bold", size: 20))
                        
                        Text(notification.actorName ?? "Unknown")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Quick reply for comments
                if notification.type == .comment || notification.type == .mention {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Reply")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            TextField("Type your reply...", text: $replyText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isReplyFocused)
                            
                            Button {
                                onReply()
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(replyText.isEmpty ? Color.gray : Color.blue)
                                    )
                            }
                            .disabled(replyText.isEmpty)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onMarkRead()
                        onDismiss()
                    } label: {
                        HStack {
                            Image(systemName: "envelope.open")
                            Text("Mark as Read")
                            Spacer()
                        }
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.primary)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.1))
                        )
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .onAppear {
                isReplyFocused = true
            }
        }
    }
}

// MARK: - Profile Cache

@MainActor
class NotificationProfileCache: ObservableObject {
    static let shared = NotificationProfileCache()
    
    private var cache: [String: CachedProfile] = [:]
    private let db = Firestore.firestore()
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    func getProfile(userId: String) async -> CachedProfile? {
        // Check cache
        if let cached = cache[userId] {
            return cached
        }
        
        // Fetch from Firestore
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data() else { return nil }
            
            let profile = CachedProfile(
                id: userId,
                name: data["displayName"] as? String ?? "Unknown",
                imageURL: data["profileImageURL"] as? String
            )
            
            // Cache it
            cache[userId] = profile
            return profile
        } catch {
            print("❌ Error fetching profile: \(error)")
            return nil
        }
    }
}

struct CachedProfile {
    let id: String
    let name: String
    let imageURL: String?
    
    var initials: String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Priority Engine (Simple ML-like scoring)

@MainActor
class NotificationPriorityEngine: ObservableObject {
    static let shared = NotificationPriorityEngine()
    
    @Published private(set) var priorityScores: [String: Double] = [:]
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    func calculatePriorities(for notifications: [AppNotification]) async {
        var scores: [String: Double] = [:]
        
        for notification in notifications {
            guard let id = notification.id else { continue }
            
            var score = 0.0
            
            // Base score by type
            switch notification.type {
            case .mention:
                score += 0.4
            case .comment:
                score += 0.3
            case .amen:
                score += 0.2
            case .follow:
                score += 0.15
            default:
                score += 0.1
            }
            
            // Recency boost
            let age = Date().timeIntervalSince(notification.createdAt.dateValue())
            if age < 3600 { // 1 hour
                score += 0.3
            } else if age < 86400 { // 1 day
                score += 0.1
            }
            
            // Unread boost
            if !notification.read {
                score += 0.2
            }
            
            scores[id] = min(score, 1.0)
        }
        
        priorityScores = scores
    }
    
    func getPriorityNotificationIds(threshold: Double = 0.6) -> Set<String> {
        Set(priorityScores.filter { $0.value >= threshold }.map { $0.key })
    }
}

// MARK: - Settings Sheet

struct NotificationSettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationSoundEnabled") private var soundEnabled = true
    @AppStorage("notificationBadgeEnabled") private var badgeEnabled = true
    
    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    Toggle("Enable Notifications", isOn: $notificationsEnabled)
                }
                
                Section("Style") {
                    Toggle("Sound", isOn: $soundEnabled)
                    Toggle("Badge", isOn: $badgeEnabled)
                }
                
                Section("Privacy") {
                    NavigationLink("Follow Requests") {
                        FollowRequestsView()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension NotificationService {
    func refreshNotifications() async {
        await refresh()
    }
}

// Note: ScaleButtonStyle is defined in SharedUIComponents.swift

#Preview {
    NotificationsView()
}
