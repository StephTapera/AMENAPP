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
import FirebaseAuth
import Combine

struct NotificationsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var followRequestsViewModel = FollowRequestsViewModel.shared  // P0 FIX: Use singleton
    @ObservedObject private var profileCache = NotificationProfileCache.shared
    @ObservedObject private var priorityEngine = NotificationPriorityEngine.shared
    @ObservedObject private var deduplicator = SmartNotificationDeduplicator.shared
    @State private var selectedFilter: NotificationFilter = .all
    @State private var showFollowRequests = false
    @State private var isRefreshing = false
    @State private var showSettings = false
    @Namespace private var filterAnimation
    
    // Navigation state - Use strongly-typed navigation to avoid ambiguity
    @State private var navigationPath: [NotificationNavigationDestinations.NotificationDestination] = []
    
    // Animation timing constants for consistency
    private let fastAnimationDuration: Double = 0.15
    private let standardAnimationDuration: Double = 0.2
    
    // Quick Actions state
    @State private var showQuickActions = false
    @State private var quickActionNotification: AppNotification?
    @State private var quickReplyText = ""

    // P1 PERF FIX: Cache sorted+grouped results so they aren't recomputed on every render.
    // Updated only when source notifications or the selected filter actually change.
    @State private var cachedGroupedNotifications: [NotificationGroup] = []
    // Debounce task — cancels the previous rebuild when rapid streaming updates arrive
    @State private var rebuildTask: Task<Void, Never>?

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

    /// Grouped notifications — reads from the cached state to avoid sorting/dedup on every render.
    private var groupedNotifications: [NotificationGroup] {
        cachedGroupedNotifications
    }

    /// Rebuild the filtered+sorted+grouped notification list.
    /// Called only when source data or selected filter actually changes (via .onChange).
    private func rebuildGroupedNotifications() {
        var notifications = notificationService.notifications

        // P0 FIX: Filter out self-notifications (user shouldn't see their own actions)
        if let currentUserId = Auth.auth().currentUser?.uid {
            notifications = notifications.filter { $0.actorId != currentUserId }
        }

        switch selectedFilter {
        case .all:
            break
        case .priority:
            let priorityIds = priorityEngine.getPriorityNotificationIds()
            notifications = notifications.filter { notification in
                guard let id = notification.id else { return false }
                return priorityIds.contains(id)
            }
        case .mentions:
            notifications = notifications.filter { $0.type == .mention }
        case .reactions:
            notifications = notifications.filter { $0.type == .amen || $0.type == .repost }
        case .follows:
            notifications = notifications.filter { $0.type == .follow }
        }

        // P0 FIX: Sort by updatedAt (for grouped) or createdAt (newest first)
        let sorted = notifications.sorted { lhs, rhs in
            let lhsDate = lhs.updatedAt?.dateValue() ?? lhs.createdAt.dateValue()
            let rhsDate = rhs.updatedAt?.dateValue() ?? rhs.createdAt.dateValue()
            return lhsDate > rhsDate
        }

        cachedGroupedNotifications = deduplicator.groupNotifications(sorted)
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            contentView
                .navigationBarHidden(true)
                .sheet(isPresented: $showFollowRequests) {
                    FollowRequestsView()
                }
                .sheet(isPresented: $showSettings) {
                    NotificationSettingsSheet()
                }
                .sheet(isPresented: $showQuickActions) {
                    quickActionsSheetContent
                }
                .onAppear {
                    handleOnAppear()
                    rebuildGroupedNotifications()
                }
                .onDisappear(perform: handleOnDisappear)
                // P1 PERF FIX: Rebuild cache only when data or filter actually changes.
                // Debounced so rapid streaming inserts batch into a single rebuild.
                .onChange(of: notificationService.notifications.count) { _, _ in
                    rebuildTask?.cancel()
                    rebuildTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
                        guard !Task.isCancelled else { return }
                        await MainActor.run { rebuildGroupedNotifications() }
                    }
                }
                .onChange(of: selectedFilter) { _, _ in
                    rebuildGroupedNotifications()
                }
                .navigationDestination(for: NotificationNavigationDestinations.NotificationDestination.self) { destination in
                    navigationDestinationView(destination)
                }
                .alert("Error", isPresented: errorBinding, actions: alertActions, message: alertMessage)
        }
    }
    
    // MARK: - Body Sub-Views
    
    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            headerContainerView
            
            // Notifications list with smart grouping
            notificationListView
        }
    }
    
    @ViewBuilder
    private var headerContainerView: some View {
        VStack(spacing: 16) {
            headerSection
                .padding(.horizontal)
            
            // Follow Requests Button
            if !followRequestsViewModel.requests.isEmpty {
                followRequestsButton
            }
            
            // Enhanced Filter Pills with Icons
            modernFilterSection
        }
        .padding(.top)
        .background(Color(.systemBackground))
    }
    
    @ViewBuilder
    private var followRequestsButton: some View {
        Button {
            showFollowRequests = true
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            followRequestsButtonLabel
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity).animation(.easeOut(duration: fastAnimationDuration)))
    }
    
    @ViewBuilder
    private var followRequestsButtonLabel: some View {
        HStack(spacing: 12) {
            // Icon
            followRequestsIcon
            
            // Text
            followRequestsText
            
            Spacer()
            
            // Badge + Arrow
            followRequestsBadge
        }
        .padding(16)
        .background(followRequestsBackground)
    }
    
    @ViewBuilder
    private var followRequestsIcon: some View {
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
    }
    
    @ViewBuilder
    private var followRequestsText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Follow Requests")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            
            Text("\(followRequestsViewModel.requests.count) pending request\(followRequestsViewModel.requests.count == 1 ? "" : "s")")
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var followRequestsBadge: some View {
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
    
    @ViewBuilder
    private var followRequestsBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.purple.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: .purple.opacity(0.1), radius: 8, y: 2)
    }
    
    @ViewBuilder
    private var notificationListView: some View {
        if notificationService.isLoading {
            // P0 FIX: Show loading skeleton instead of spinner for better UX
            NotificationsLoadingView()
        } else if groupedNotifications.isEmpty {
            emptyStateView
        } else {
            notificationsScrollView
        }
    }
    
    @ViewBuilder
    private var notificationsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(groupedNotifications) { group in
                    GroupedNotificationRow(
                        group: group,
                        onDismiss: {
                            withAnimation(.easeOut(duration: fastAnimationDuration)) {
                                removeGroup(group)
                            }
                        },
                        onMarkAsRead: {
                            markGroupAsRead(group)
                        },
                        onTap: {
                            handleGroupTap(group)
                        },
                        onLongPress: {
                            showQuickActions(for: group)
                        },
                        onAvatarTap: { actorId in
                            // P0 FIX: Avatar tap navigates to profile
                            navigationPath.append(NotificationNavigationDestinations.NotificationDestination.profile(userId: actorId))
                        }
                    )
                    .id(group.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ).animation(.easeOut(duration: fastAnimationDuration)))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .refreshable {
            await refreshNotifications()
        }
    }
    
    @ViewBuilder
    private var quickActionsSheetContent: some View {
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
    
    // MARK: - Alert Helpers
    
    private var errorBinding: Binding<Bool> {
        Binding(
            get: { notificationService.error != nil },
            set: { newValue in
                if !newValue {
                    Task { @MainActor [weak notificationService] in
                        notificationService?.clearError()
                    }
                }
            }
        )
    }
    
    @ViewBuilder
    private func alertActions() -> some View {
        Button("OK", role: .cancel) { }
        
        if case .networkError = notificationService.error {
            Button("Retry") {
                notificationService.stopListening()
                notificationService.startListening()
            }
        }
    }
    
    @ViewBuilder
    private func alertMessage() -> some View {
        if let error = notificationService.error {
            Text(error.localizedDescription)
        }
    }
    
    private func navigationDestinationView(_ destination: NotificationNavigationDestinations.NotificationDestination) -> some View {
        Group {
            switch destination {
            case .profile(let userId):
                NotificationUserProfileView(userId: userId)
            case .post(let postId):
                NotificationPostDetailView(postId: postId)
            case .prayer(let prayerId):
                // Delegate to global router which handles tab switch to Prayer
                Color.clear
                    .onAppear {
                        NotificationDeepLinkRouter.shared.navigate(to: .prayer(prayerId: prayerId))
                    }
            case .churchNote(let noteId):
                // Delegate to global router which handles tab switch to Church Notes
                Color.clear
                    .onAppear {
                        NotificationDeepLinkRouter.shared.navigate(to: .churchNote(noteId: noteId))
                    }
            case .conversation(let conversationId):
                // Delegate to global router which handles tab switch to Messages
                Color.clear
                    .onAppear {
                        NotificationDeepLinkRouter.shared.navigate(to: .conversation(conversationId: conversationId))
                    }
            }
        }
    }
    
    // MARK: - Lifecycle Handlers
    
    private func handleOnAppear() {
        notificationService.startListening()
        // Auto-mark all notifications as read when the screen is opened (like Instagram/Threads)
        markAllAsRead()
        clearBadgeCount()
        
        // Load follow requests and priority scores
        Task { @MainActor in
            await followRequestsViewModel.loadRequests()
            await priorityEngine.calculatePriorities(for: notificationService.notifications)
            
            // Clean up duplicate follow notifications on first load
            await notificationService.cleanupDuplicateFollowNotifications()
        }
        
        // ✅ Handle deep link if present (using legacy handler for navigation compatibility)
        // Note: LegacyNotificationDeepLinkHandler is kept for backward compatibility
        // with the existing navigation system. NotificationDeepLinkHandler is used
        // for push notification handling in PushNotificationManager.
        if let deepLink = LegacyNotificationDeepLinkHandler.shared.activeDeepLink {
            let path = deepLink.navigationPath
            if path.hasPrefix("profile_") {
                let userId = String(path.dropFirst("profile_".count))
                navigationPath.append(NotificationNavigationDestinations.NotificationDestination.profile(userId: userId))
            } else if path.hasPrefix("post_") {
                let postId = String(path.dropFirst("post_".count))
                navigationPath.append(NotificationNavigationDestinations.NotificationDestination.post(postId: postId))
            }
            LegacyNotificationDeepLinkHandler.shared.clearDeepLink()
        }
    }
    
    private func handleOnDisappear() {
        // ✅ P0-5: Stop all listeners to prevent memory leaks
        notificationService.stopListening()
        profileCache.stopAllListeners()
        // Cancel any pending debounced rebuild
        rebuildTask?.cancel()
        rebuildTask = nil
        
        dlog("🛑 NotificationsView: Cleaned up all listeners")
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
                if let actorId = firstNotification.actorId, !actorId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.profile(userId: actorId))
                }
            case .amen, .comment, .mention, .reply, .repost:
                if let postId = firstNotification.postId, !postId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.post(postId: postId))
                }
            case .followRequestAccepted:
                if let actorId = firstNotification.actorId, !actorId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.profile(userId: actorId))
                }
            case .messageRequestAccepted:
                if let conversationId = firstNotification.conversationId, !conversationId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.conversation(conversationId: conversationId))
                }
            case .prayerReminder, .prayerAnswered:
                if let prayerId = firstNotification.prayerId, !prayerId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.prayer(prayerId: prayerId))
                }
            case .churchNoteShared:
                if let noteId = firstNotification.noteId, !noteId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.churchNote(noteId: noteId))
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
            guard let postId = notification.postId else {
                return
            }
            
            do {
                // ✅ Use NotificationQuickReplyService to post comment
                guard let currentUser = Auth.auth().currentUser else {
                    throw NotificationQuickReplyError.notAuthenticated
                }
                
                // Extract username with proper fallback
                let username: String
                if let email = currentUser.email, !email.isEmpty {
                    username = email.components(separatedBy: "@").first ?? currentUser.displayName ?? "Unknown"
                } else {
                    username = currentUser.displayName ?? "Unknown"
                }
                
                try await NotificationQuickReplyService.shared.postQuickReply(
                    postId: postId,
                    text: quickReplyText,
                    authorUsername: username
                )
                
                // Close sheet and clear text
                showQuickActions = false
                quickReplyText = ""
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
            } catch {
                // Show error to user
                await MainActor.run {
                    notificationService.setError(.firestoreError(error))
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    private func markGroupAsRead(_ group: NotificationGroup) {
        for notification in group.notifications where !notification.read {
            markAsRead(notification)
        }
    }
    
    private func removeGroup(_ group: NotificationGroup) {
        Task {
            for notification in group.notifications {
                await removeNotification(notification)
            }
        }
    }
    
    // MARK: - Refresh Handler
    
    private func refreshNotifications() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        defer { isRefreshing = false }
        
        // Reload notifications
        await notificationService.refresh()
        
        // Reload follow requests
        await followRequestsViewModel.loadRequests()
        
        // Recalculate priorities
        await priorityEngine.calculatePriorities(for: notificationService.notifications)
        
        // Haptic feedback
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            // Exit Button
            exitButton
            
            Text("Notifications")
                .font(.custom("OpenSans-Bold", size: 24))
            
            Spacer()
            
            // Unread count badge + Settings
            trailingHeaderButtons
        }
    }
    
    private var exitButton: some View {
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
        .buttonStyle(.plain)
    }
    
    private var trailingHeaderButtons: some View {
        HStack(spacing: 12) {
            if unreadCount > 0 {
                unreadBadgeSection
            }
            
            settingsButton
        }
    }
    
    private var unreadBadgeSection: some View {
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
                withAnimation(.easeOut(duration: standardAnimationDuration)) {
                    markAllAsRead()
                }
            } label: {
                Text("Mark all read")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var settingsButton: some View {
        Menu {
            Button {
                showSettings = true
                HapticManager.impact(style: .light)
            } label: {
                Label("Notification Settings", systemImage: "gearshape")
            }

            if !notificationService.notifications.filter({ $0.read }).isEmpty {
                Button(role: .destructive) {
                    Task {
                        try? await notificationService.deleteAllRead()
                        HapticManager.notification(type: .success)
                    }
                } label: {
                    Label("Clear Read Notifications", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
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
            // Spring-driven animation makes the capsule slide feel liquid
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72, blendDuration: 0.15)) {
                selectedFilter = filter
            }
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.icon)
                    .font(.system(size: 14, weight: .semibold))
                    // Icon morphs with a liquid dissolve when the pill is selected/deselected
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    .symbolEffect(.bounce, value: isSelected)
                
                Text(filter.rawValue)
                    .font(.custom("OpenSans-Bold", size: 14))
                    // Label content fades smoothly during selection changes
                    .contentTransition(.interpolate)
                
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
        .buttonStyle(.plain)
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
            return filtered.filter { $0.type == .amen || $0.type == .repost }.count
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
    
    private func removeNotification(_ notification: AppNotification) async {
        guard let id = notification.id else { return }
        try? await notificationService.deleteNotification(id)
    }
    
    // MARK: - Badge Management

    /// Clear app badge count when viewing notifications
    /// Optimistically zeros the dot immediately; listener will re-sync actual count.
    private func clearBadgeCount() {
        BadgeCountManager.shared.clearNotifications()
    }
}

// MARK: - Notification Group Model

struct NotificationGroup: Identifiable, Equatable {
    /// Stable ID derived from the primary notification's Firestore document ID + type,
    /// so SwiftUI can track rows across re-renders without creating new identities.
    let id: String
    let notifications: [AppNotification]
    
    init?(notifications: [AppNotification]) {
        guard !notifications.isEmpty else { return nil }
        self.notifications = notifications
        // Use primaryNotification's Firestore ID + type as stable group identity
        let primary = notifications[0]
        // P1 FIX: Use deterministic fallback when id is nil so SwiftUI view identity is stable.
        // UUID() would generate a new random string on every render, causing full list re-render.
        let stableId = primary.id ?? "\(primary.type.rawValue)_\(primary.actorId ?? "unknown")"
        self.id = "\(stableId)_\(primary.type.rawValue)"
    }
    
    static func == (lhs: NotificationGroup, rhs: NotificationGroup) -> Bool {
        lhs.id == rhs.id &&
        lhs.notifications.map(\.id) == rhs.notifications.map(\.id)
    }
    
    var isGrouped: Bool {
        // Grouped if either: 
        // 1. Multiple notification documents (client-side grouping)
        // 2. Single notification with actors array from Firebase (server-side grouping)
        if notifications.count > 1 {
            return true
        }
        if let actorCount = primaryNotification.actorCount, actorCount > 1 {
            return true
        }
        return false
    }
    
    var primaryNotification: AppNotification {
        notifications[0] // Safe because init guards against empty array
    }
    
    var otherCount: Int {
        // For Firebase grouped notifications, use actorCount - 1
        if let actorCount = primaryNotification.actorCount, actorCount > 1 {
            return actorCount - 1
        }
        // Otherwise use client-side grouping count
        return max(0, notifications.count - 1)
    }
    
    var mostRecentDate: Date {
        // For Firebase grouped notifications with updatedAt, use that
        if let updatedAt = primaryNotification.updatedAt {
            return updatedAt.dateValue()
        }
        // Otherwise use most recent createdAt from all notifications
        return notifications.map { $0.createdAt.dateValue() }.max() ?? Date()
    }
    
    var hasUnread: Bool {
        notifications.contains { !$0.read }
    }
    
    var actorNames: [String] {
        // For Firebase grouped notifications, use actors array
        if let actors = primaryNotification.actors, !actors.isEmpty {
            return actors.map { $0.name }
        }
        // Otherwise use client-side grouping
        return notifications.compactMap { $0.actorName }
    }
    
    var actorProfiles: [NotificationActor] {
        // Return actors array for displaying profile photos
        if let actors = primaryNotification.actors {
            return actors
        }
        // Fallback to constructing from notifications
        return notifications.compactMap { notif -> NotificationActor? in
            guard let id = notif.actorId,
                  let name = notif.actorName else { return nil }
            return NotificationActor(
                id: id,
                name: name,
                username: notif.actorUsername ?? "",
                profileImageURL: notif.actorProfileImageURL
            )
        }
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
    let onAvatarTap: (String) -> Void  // P0 FIX: Separate handler for avatar taps
    
    @ObservedObject private var profileCache = NotificationProfileCache.shared
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
        .buttonStyle(NotificationRowButtonStyle())
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                onMarkAsRead()
            } label: {
                Label("Mark as Read", systemImage: "envelope.open")
            }
            
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.15)) {
                    onDismiss()
                }
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
                withAnimation(.easeOut(duration: 0.15)) {
                    onDismiss()
                }
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
                // Stacked avatars for groups - show actual profile photos
                let actors = group.actorProfiles
                ZStack(alignment: .topTrailing) {
                    // Back avatar - first actor's profile photo
                    if let firstActor = actors.first {
                        NotificationProfileImage(
                            imageURL: firstActor.profileImageURL,
                            fallbackName: firstActor.name,
                            fallbackColor: group.primaryNotification.color,
                            size: 56
                        )
                    } else {
                        Circle()
                            .fill(group.primaryNotification.color.opacity(0.2))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: group.primaryNotification.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(group.primaryNotification.color)
                            )
                    }
                    
                    // Front avatar - count indicator or second actor
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
            } else {
                // Single notification - use cached profile image
                NotificationProfileImage(
                    imageURL: group.primaryNotification.actorProfileImageURL ?? actorProfile?.imageURL,
                    fallbackName: group.primaryNotification.actorName,
                    fallbackColor: group.primaryNotification.color,
                    size: 56
                )
                .overlay(
                    // Badge icon for notification type
                    Circle()
                        .fill(group.primaryNotification.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: group.primaryNotification.icon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .offset(x: 18, y: 18)
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
        .contentShape(Rectangle())
        .onTapGesture {
            // P0 FIX: Avatar tap should navigate to user profile, not post
            if let actorId = group.primaryNotification.actorId, !actorId.isEmpty {
                onAvatarTap(actorId)
            }
        }
    }
}
// MARK: - Notification Names for Navigation

extension Notification.Name {
    static let navigateToPost = Notification.Name("navigateToPost")
    static let navigateToProfile = Notification.Name("navigateToProfile")
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

// MARK: - Enhanced Profile Cache with Real-Time Sync ✨

@MainActor
class NotificationProfileCache: ObservableObject {
    static let shared = NotificationProfileCache()
    
    // ✅ @Published for automatic UI updates
    @Published private(set) var profiles: [String: CachedProfile] = [:]
    
    private var listeners: [String: ListenerRegistration] = [:]
    private let maxConcurrentListeners = 50
    private let db = Firestore.firestore()
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    // ✅ Fire-and-forget prefetch — starts listener in background, returns immediately.
    // Use this when you want to warm the cache without awaiting (e.g. list prefetch).
    func prefetchProfile(userId: String) {
        guard profiles[userId] == nil else { return }
        Task {
            await fetchAndSubscribe(userId: userId)
        }
    }
    
    // ✅ Async getter with real-time subscription — always prefer this at call sites.
    func getProfile(userId: String) async -> CachedProfile? {
        // If already cached, return it
        if let cached = profiles[userId] {
            return cached
        }
        
        // Fetch and subscribe
        return await fetchAndSubscribe(userId: userId)
    }
    
    // ✅ Fetch profile and set up real-time listener
    private func fetchAndSubscribe(userId: String) async -> CachedProfile? {
        // Check if we already have a listener
        if listeners[userId] != nil {
            // Wait a moment for the listener to populate data
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return profiles[userId]
        }
        
        // Limit concurrent listeners to prevent memory issues
        if listeners.count >= maxConcurrentListeners {
            // Just do a one-time fetch without listener
            return await fetchProfileOnce(userId: userId)
        }
        
        // Set up real-time listener
        let listener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                
                Task { @MainActor in
                    guard let document = documentSnapshot,
                          let data = document.data(),
                          error == nil else {
                        dlog("❌ Error fetching profile for \(userId): \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    
                    let profile = CachedProfile(
                        id: userId,
                        name: data["displayName"] as? String ?? "Unknown",
                        imageURL: data["profileImageURL"] as? String
                    )
                    
                    // ✅ Update cache - triggers @Published update
                    self.profiles[userId] = profile
                    dlog("✅ Profile updated in real-time for \(profile.name)")
                }
            }
        
        // Store listener
        listeners[userId] = listener
        
        // Wait for initial data
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        return profiles[userId]
    }
    
    // One-time fetch without listener (for when limit reached)
    private func fetchProfileOnce(userId: String) async -> CachedProfile? {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()
            guard let data = doc.data() else { return nil }
            
            let profile = CachedProfile(
                id: userId,
                name: data["displayName"] as? String ?? "Unknown",
                imageURL: data["profileImageURL"] as? String
            )
            
            profiles[userId] = profile
            return profile
        } catch {
            dlog("❌ Error fetching profile once: \(error)")
            return nil
        }
    }
    
    // ✅ Stop listening to a specific user (cleanup)
    func stopListening(userId: String) {
        listeners[userId]?.remove()
        listeners.removeValue(forKey: userId)
    }
    
    // ✅ Stop all listeners (cleanup)
    func stopAllListeners() {
        for (_, listener) in listeners {
            listener.remove()
        }
        listeners.removeAll()
    }
    
    func clearCache() {
        stopAllListeners()
        profiles.removeAll()
    }
}

struct CachedProfile: Equatable {
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

// MARK: - Profile Image Component with CachedAsyncImage ✨

/// Notification profile image using CachedAsyncImage for better performance
struct NotificationProfileImage: View {
    let imageURL: String?
    let fallbackName: String?
    let fallbackColor: Color
    let size: CGFloat
    
    init(
        imageURL: String?,
        fallbackName: String? = nil,
        fallbackColor: Color = .blue,
        size: CGFloat = 56
    ) {
        self.imageURL = imageURL
        self.fallbackName = fallbackName
        self.fallbackColor = fallbackColor
        self.size = size
    }
    
    var body: some View {
        Group {
            if let imageURL = imageURL,
               !imageURL.isEmpty,
               let url = URL(string: imageURL) {
                // ✅ Use CachedAsyncImage for better performance
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } placeholder: {
                    fallbackView
                }
            } else {
                fallbackView
            }
        }
    }
    
    private var fallbackView: some View {
        Circle()
            .fill(fallbackColor.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Group {
                    if let fallbackName = fallbackName {
                        Text(initials(from: fallbackName))
                            .font(.custom("OpenSans-Bold", size: size * 0.32))
                            .foregroundStyle(fallbackColor)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(fallbackColor)
                    }
                }
            )
    }
    
    private func initials(from name: String) -> String {
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

// MARK: - Smart Notification Deduplication ✨

@MainActor
class SmartNotificationDeduplicator: ObservableObject {
    static let shared = SmartNotificationDeduplicator()
    
    private var seenFingerprints: Set<String> = []
    private let timeWindowSeconds: TimeInterval = 1800 // 30 minutes
    
    private init() {
        // Private initializer for singleton pattern
    }
    
    /// Remove duplicate notifications using fingerprinting
    func deduplicate(_ notifications: [AppNotification]) -> [AppNotification] {
        var uniqueNotifications: [AppNotification] = []
        var currentFingerprints: Set<String> = []
        
        for notification in notifications {
            let fingerprint = generateFingerprint(for: notification)
            
            // Check if we've seen this fingerprint
            if !currentFingerprints.contains(fingerprint) {
                uniqueNotifications.append(notification)
                currentFingerprints.insert(fingerprint)
            } else {
                dlog("🔍 Duplicate detected: \(notification.type) from \(notification.actorName ?? "unknown")")
            }
        }
        
        // Update seen fingerprints
        seenFingerprints = currentFingerprints
        
        dlog("✅ Deduplicated: \(notifications.count) → \(uniqueNotifications.count) notifications")
        return uniqueNotifications
    }
    
    /// Generate a unique fingerprint for a notification
    private func generateFingerprint(for notification: AppNotification) -> String {
        // Round timestamp to 5-minute window to catch near-duplicates
        let roundedTimestamp = Int(notification.createdAt.seconds) / 300 * 300
        
        // Create fingerprint: type + actorId + postId + timeWindow
        var components: [String] = []
        components.append(notification.type.rawValue)
        
        if let actorId = notification.actorId {
            components.append(actorId)
        }
        
        if let postId = notification.postId {
            components.append(postId)
        }
        
        components.append("\(roundedTimestamp)")
        
        return components.joined(separator: "|")
    }
    
    /// Enhanced grouping with time windows
    func groupNotifications(_ notifications: [AppNotification]) -> [NotificationGroup] {
        // First deduplicate
        let uniqueNotifications = deduplicate(notifications)
        
        // Group by type + postId + time window
        var groups: [String: [AppNotification]] = [:]
        
        for notification in uniqueNotifications {
            let groupKey = generateGroupKey(for: notification)
            
            if groups[groupKey] == nil {
                groups[groupKey] = []
            }
            groups[groupKey]?.append(notification)
        }
        
        // Convert to NotificationGroup objects
        var notificationGroups: [NotificationGroup] = []
        
        for (_, notificationsInGroup) in groups {
            guard let primary = notificationsInGroup.first else { continue }
            
            if notificationsInGroup.count > 1 {
                // Create grouped notification
                if let group = NotificationGroup(notifications: notificationsInGroup) {
                    notificationGroups.append(group)
                    dlog("📦 Grouped \(notificationsInGroup.count) \(primary.type) notifications")
                }
            } else {
                // Single notification
                if let group = NotificationGroup(notifications: notificationsInGroup) {
                    notificationGroups.append(group)
                }
            }
        }
        
        // Sort by most recent activity — uses updatedAt when available (e.g. grouped reactions)
        // so new activity on an existing group bubbles it to the top correctly.
        return notificationGroups.sorted {
            $0.mostRecentDate > $1.mostRecentDate
        }
    }
    
    /// Generate grouping key for notifications
    private func generateGroupKey(for notification: AppNotification) -> String {
        // Round timestamp to 30-minute window for grouping
        let roundedTimestamp = Int(Double(notification.createdAt.seconds) / timeWindowSeconds) * Int(timeWindowSeconds)
        
        var components: [String] = []
        components.append(notification.type.rawValue)
        
        // Group by post for likes/comments/amens
        if let postId = notification.postId {
            components.append(postId)
        }
        
        // Add time window
        components.append("\(roundedTimestamp)")
        
        return components.joined(separator: "_")
    }
    
    /// Clear fingerprint cache
    func clearCache() {
        seenFingerprints.removeAll()
        dlog("🗑️ Deduplication cache cleared")
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

// MARK: - Loading Skeleton

struct NotificationSkeletonRow: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar skeleton
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
                .shimmer(isAnimating: isAnimating)
            
            VStack(alignment: .leading, spacing: 8) {
                // Name + action text
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 14)
                    .shimmer(isAnimating: isAnimating)
                
                // Timestamp
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 12)
                    .shimmer(isAnimating: isAnimating)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .onAppear {
            isAnimating = true
        }
    }
}

struct NotificationsLoadingView: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    NotificationSkeletonRow()
                }
            }
            .padding(.vertical, 16)
        }
    }
}

// Shimmer effect modifier
extension View {
    func shimmer(isAnimating: Bool) -> some View {
        self.overlay(
            GeometryReader { geometry in
                let gradientWidth = geometry.size.width
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.white.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: gradientWidth)
                .offset(x: isAnimating ? gradientWidth : -gradientWidth)
                .animation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
            }
        )
        .clipped()
    }
}

// MARK: - Extensions

// P0 FIX: Instant press feedback for notification rows
struct NotificationRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Note: ScaleButtonStyle is defined in SharedUIComponents.swift
// Note: QuickReplyService and QuickReplyError are defined in NotificationQuickActions.swift

#Preview {
    NotificationsView()
}
