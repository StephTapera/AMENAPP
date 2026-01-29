//
//  NotificationsView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import UserNotifications

struct NotificationsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @State private var selectedFilter: NotificationFilter = .all
    @Namespace private var filterAnimation
    
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
                        
                        // Unread count badge
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
                    }
                    .padding(.horizontal)
                    
                    // Enhanced Filter Pills with Icons
                    modernFilterSection
                }
                .padding(.top)
                .background(Color(.systemBackground))
                
                // Notifications list with enhanced animations and grouping
                if notificationService.isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if filteredNotifications.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            // Group notifications by time period
                            ForEach(groupedNotifications.keys.sorted(by: { timeOrder($0) < timeOrder($1) }), id: \.self) { timeGroup in
                                Section {
                                    LazyVStack(spacing: 12) {
                                        ForEach(groupedNotifications[timeGroup] ?? []) { notification in
                                            RealNotificationRow(
                                                notification: notification,
                                                onDismiss: {
                                                    removeNotification(notification)
                                                },
                                                onMarkAsRead: {
                                                    markAsRead(notification)
                                                }
                                            )
                                            .transition(.asymmetric(
                                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)
                                            ))
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.bottom, 16)
                                } header: {
                                    HStack {
                                        Text(timeGroup)
                                            .font(.custom("OpenSans-Bold", size: 14))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                        
                                        Spacer()
                                        
                                        // Count for this time period
                                        let groupCount = (groupedNotifications[timeGroup] ?? []).filter { !$0.read }.count
                                        if groupCount > 0 {
                                            Text("\(groupCount) unread")
                                                .font(.custom("OpenSans-SemiBold", size: 12))
                                                .foregroundStyle(.secondary.opacity(0.7))
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemBackground).opacity(0.95))
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                notificationService.startListening()
                clearBadgeCount()
                
                // Optional: Auto-mark all as read when opening notifications
                // Uncomment if you want this behavior:
                // Task {
                //     try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                //     await notificationService.markAllAsRead()
                // }
            }
            .onDisappear {
                notificationService.stopListening()
            }
        }
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
        
        return notificationService.notifications.filter { notification in
            !notification.read && {
                switch filter {
                case .priority: return false // Not implemented yet
                case .mentions: return notification.type == "mention"
                case .reactions: return notification.type == "amen"
                case .follows: return notification.type == "follow"
                default: return false
                }
            }()
        }.count
    }
    
    private func markAllAsRead() {
        Task {
            await notificationService.markAllAsRead()
        }
        
        // Update badge count
        clearBadgeCount()
    }
    
    private func markAsRead(_ notification: AppNotification) {
        Task {
            guard let id = notification.id else { return }
            await notificationService.markAsRead(id)
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
            await notificationService.deleteNotification(id)
        }
    }
    
    private var filteredNotifications: [AppNotification] {
        guard selectedFilter != .all else { return notificationService.notifications }
        
        return notificationService.notifications.filter { notification in
            switch selectedFilter {
            case .all:
                return true
            case .priority:
                return false // Not implemented
            case .mentions:
                return notification.type == "mention"
            case .reactions:
                return notification.type == "amen"
            case .follows:
                return notification.type == "follow"
            }
        }
    }
    
    // MARK: - Time Grouping
    
    /// Group notifications by time periods
    private var groupedNotifications: [String: [AppNotification]] {
        Dictionary(grouping: filteredNotifications) { notification in
            notification.timeCategory
        }
    }
    
    /// Define time order for sorting sections
    private func timeOrder(_ category: String) -> Int {
        switch category {
        case "Today": return 0
        case "Yesterday": return 1
        case "This Week": return 2
        case "This Month": return 3
        case "Earlier": return 4
        default: return 5
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


// MARK: - Notification Item Model
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
    
    var body: some View {
        Button {
            // Mark as read when tapped
            if !notification.read {
                onMarkAsRead()
            }
            // TODO: Navigate to relevant content
            handleNotificationTap()
        } label: {
            HStack(spacing: 14) {
                // Avatar with notification icon
                ZStack(alignment: .bottomTrailing) {
                    // Main avatar
                    Circle()
                        .fill(notification.color.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: notification.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(notification.color)
                        )
                    
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
    }
    
    private func handleNotificationTap() {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Navigate based on notification type
        switch notification.type {
        case "follow":
            print("📍 Navigate to profile: \(notification.actorUsername ?? "")")
            // TODO: Navigate to user profile
            
        case "amen":
            print("📍 Navigate to post: \(notification.postId ?? "")")
            // TODO: Navigate to post
            
        case "comment":
            print("📍 Navigate to post comments: \(notification.postId ?? "")")
            // TODO: Navigate to post comments
            
        case "prayer_reminder":
            print("📍 Navigate to prayer requests")
            // TODO: Navigate to prayers
            
        default:
            print("📍 Unknown notification type: \(notification.type)")
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

// MARK: - Supporting Components

#Preview {
    NotificationsView()
}
