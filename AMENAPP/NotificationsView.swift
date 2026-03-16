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
    @Environment(\.mainTabSelection) private var mainTabSelection
    @ObservedObject private var notificationService = NotificationService.shared
    @ObservedObject private var followRequestsViewModel = FollowRequestsViewModel.shared  // P0 FIX: Use singleton
    @ObservedObject private var profileCache = NotificationProfileCache.shared
    private let priorityEngine = NotificationPriorityEngine.shared
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
    // Suppresses the onChange debounce during the synchronous onAppear rebuild
    // to avoid a double-rebuild (and resulting flash) each time the view opens.
    @State private var suppressNextDebounce = false

    enum NotificationFilter: String, CaseIterable {
        case all = "All"
        case follows = "Follows"
        case conversations = "Conversations"
        case mentions = "Mentions"
        
        var icon: String {
            switch self {
            case .all: return "bell.fill"
            case .follows: return "person.2.fill"
            case .conversations: return "bubble.left.and.bubble.right.fill"
            case .mentions: return "at"
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
        dlog("🔔 [NOTIF] rebuildGroupedNotifications — source=\(notificationService.notifications.count) filter=\(selectedFilter.rawValue)")
        var notifications = notificationService.notifications

        // P0 FIX: Filter out self-notifications (user shouldn't see their own actions)
        if let currentUserId = Auth.auth().currentUser?.uid {
            notifications = notifications.filter { $0.actorId != currentUserId }
        }

        switch selectedFilter {
        case .all:
            break
        case .follows:
            notifications = notifications.filter {
                $0.type == .follow || $0.type == .followRequestAccepted
            }
        case .conversations:
            notifications = notifications.filter {
                $0.type == .comment || $0.type == .reply || $0.type == .repost
            }
        case .mentions:
            notifications = notifications.filter { $0.type == .mention }
        }

        // P0 FIX: Sort by updatedAt (for grouped) or createdAt (newest first)
        let sorted = notifications.sorted { lhs, rhs in
            let lhsDate = lhs.updatedAt?.dateValue() ?? lhs.createdAt.dateValue()
            let rhsDate = rhs.updatedAt?.dateValue() ?? rhs.createdAt.dateValue()
            return lhsDate > rhsDate
        }

        let rebuilt = deduplicator.groupNotifications(sorted)
        dlog("🔔 [NOTIF] rebuild complete — \(notifications.count) filtered → \(rebuilt.count) groups (was \(cachedGroupedNotifications.count))")
        cachedGroupedNotifications = rebuilt
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
                    suppressNextDebounce = true
                    rebuildGroupedNotifications()
                }
                .onDisappear(perform: handleOnDisappear)
                // P1 PERF FIX: Rebuild cache when data or filter changes.
                // Track both count AND unread count so read/unread state transitions
                // (same item count, different read flag) also trigger a rebuild.
                // Debounced so rapid streaming inserts batch into a single rebuild.
                .onChange(of: notificationService.notifications.count) { _, _ in
                    if suppressNextDebounce { suppressNextDebounce = false; return }
                    rebuildTask?.cancel()
                    rebuildTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
                        guard !Task.isCancelled else { return }
                        await MainActor.run { rebuildGroupedNotifications() }
                    }
                }
                .onChange(of: notificationService.unreadCount) { _, _ in
                    if suppressNextDebounce { suppressNextDebounce = false; return }
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
        .transition(.move(edge: .top).combined(with: .opacity))
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
        // 🔔 [NOTIF] Branch: isLoading=\(notificationService.isLoading) groups=\(groupedNotifications.count)
        let _ = dlog("🔔 [NOTIF] listView branch — isLoading=\(notificationService.isLoading) groups=\(groupedNotifications.count) unread=\(notificationService.unreadCount)")
        if notificationService.isLoading {
            // P0 FIX: Show loading skeleton instead of spinner for better UX
            NotificationsLoadingView()
        } else if groupedNotifications.isEmpty && !notificationService.notifications.isEmpty {
            // Cache hasn't been populated yet (first render after tab switch before onAppear
            // rebuilds cachedGroupedNotifications). Show skeleton instead of empty state to
            // avoid a 1-frame flash of "No notifications yet" when data already exists.
            NotificationsLoadingView()
        } else if groupedNotifications.isEmpty {
            emptyStateView
        } else {
            notificationsScrollView
        }
    }
    
    // MARK: - Time section bucketing

    /// Bucket label for a notification group date.
    private func timeBucket(for date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date) {
            // "New" = unread today; "Earlier Today" = read today
            return "Today"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = cal.dateComponents([.day], from: date, to: now).day, daysAgo <= 6 {
            return "This Week"
        } else {
            return "Older"
        }
    }

    /// Ordered section titles (Threads-style).
    private let sectionOrder = ["New", "Earlier Today", "Yesterday", "This Week", "Earlier"]

    /// Groups sorted notifications into ordered [(label, [group])] tuples.
    /// "New" = unread from today. "Earlier Today" = read from today.
    private var timeSectionedNotifications: [(label: String, groups: [NotificationGroup])] {
        var buckets: [String: [NotificationGroup]] = [:]
        for group in groupedNotifications {
            let label: String
            let timeLabel = timeBucket(for: group.mostRecentDate)
            if timeLabel == "Today" && group.hasUnread {
                label = "New"
            } else if timeLabel == "Today" {
                label = "Earlier Today"
            } else if timeLabel == "Older" {
                label = "Earlier"
            } else {
                label = timeLabel
            }
            buckets[label, default: []].append(group)
        }
        return sectionOrder.compactMap { label in
            guard let groups = buckets[label], !groups.isEmpty else { return nil }
            return (label: label, groups: groups)
        }
    }

    @ViewBuilder
    private var notificationsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(timeSectionedNotifications, id: \.label) { section in
                    SwiftUI.Section {
                        ForEach(section.groups) { group in
                            GroupedNotificationRow(
                                group: group,
                                onDismiss: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.profile(userId: actorId))
                                }
                            )
                            .id(group.id)
                            .transition(.opacity.animation(.easeOut(duration: 0.15)))
                        }
                    } header: {
                        NotificationSectionHeader(label: section.label)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 32)
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
        dlog("🔔 [NOTIF] NotificationsView.onAppear — notifications=\(notificationService.notifications.count) unread=\(notificationService.unreadCount) isLoading=\(notificationService.isLoading)")
        notificationService.startListening()
        dlog("🔔 [NOTIF] startListening() called — isLoading=\(notificationService.isLoading)")
        // Pre-populate groups immediately to avoid flash of empty state
        if cachedGroupedNotifications.isEmpty && !notificationService.notifications.isEmpty {
            rebuildGroupedNotifications()
        }
        // Auto-mark all notifications as read when the screen is opened (like Instagram/Threads).
        markAllAsRead()
        dlog("🔔 [NOTIF] markAllAsRead called (badge cleared after writes land)")
        
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
        dlog("🔔 [NOTIF] NotificationsView.onDisappear — notifications=\(notificationService.notifications.count) unread=\(notificationService.unreadCount)")
        // P1-4 FIX: Do NOT stop the notification listener on tab-switch disappear.
        // Stopping and restarting on every tab switch causes stale UI, missed real-time
        // updates, and wasteful network cycles. The listener is idempotent (startListening
        // checks for an existing listener) and app-level sign-out cleanup is handled by
        // AppLifecycleManager.performFullSignOutCleanup() which calls NotificationService.stopListening().
        // profileCache listeners are also long-lived; they self-manage per-user caching.
        // Only cancel the in-flight debounced rebuild task to free memory.
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
        
        HapticManager.impact(style: .medium)

        // Navigate to relevant content (Threads-style: tap row → content, tap avatar → profile)
        if let firstNotification = group.notifications.first {
            switch firstNotification.type {
            case .follow, .followRequestAccepted:
                // Follow notifications → open actor's profile
                if let actorId = firstNotification.actorId, !actorId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.profile(userId: actorId))
                }
            case .amen, .comment, .mention, .reply, .repost:
                // Engagement notifications → open the post
                if let postId = firstNotification.postId, !postId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.post(postId: postId))
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
                // For any unhandled type, navigate to actor's profile (like Threads)
                if let actorId = firstNotification.actorId, !actorId.isEmpty {
                    navigationPath.append(NotificationNavigationDestinations.NotificationDestination.profile(userId: actorId))
                }
            }
        }
    }
    
    private func showQuickActions(for group: NotificationGroup) {
        guard let first = group.notifications.first else { return }
        quickActionNotification = first
        showQuickActions = true
        HapticManager.impact(style: .medium)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Navigate back to Home tab (0). Falls back to dismiss() if presented as a sheet.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                mainTabSelection.wrappedValue = 0
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close notifications")
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
        Text("\(min(unreadCount, 99))\(unreadCount > 99 ? "+" : "")")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue, in: Capsule())
            .accessibilityLabel("\(unreadCount) unread notifications")
    }
    
    private var settingsButton: some View {
        Menu {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    markAllAsRead()
                }
                HapticManager.notification(type: .success)
            } label: {
                Label("Mark All as Read", systemImage: "envelope.open")
            }

            Button {
                showSettings = true
                HapticManager.impact(style: .light)
            } label: {
                Label("Notification Settings", systemImage: "gearshape")
            }

            if !notificationService.notifications.filter({ $0.read }).isEmpty {
                Divider()
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
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notification options")
    }
    
    // MARK: - Modern Filter Section (Liquid Glass)
    private var modernFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NotificationFilter.allCases, id: \.self) { filter in
                    filterPill(for: filter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func filterPill(for filter: NotificationFilter) -> some View {
        let isSelected = selectedFilter == filter
        let count = notificationCount(for: filter)
        
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedFilter = filter
            }
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                
                Text(filter.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .contentTransition(.interpolate)
                
                if count > 0 && filter != .all {
                    Text("\(min(count, 99))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Color(uiColor: .label))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color(uiColor: .label).opacity(0.35) : Color(uiColor: .separator).opacity(0.4))
                        )
                }
            }
            .foregroundStyle(isSelected ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "selectedFilter", in: filterAnimation)
                } else {
                    Capsule()
                        .fill(Color(uiColor: .systemFill).opacity(0.0))
                }
            }
            .overlay {
                if isSelected {
                    Capsule()
                        .strokeBorder(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(filter.rawValue) notifications\(count > 0 ? ", \(count) unread" : "")")
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
        
        let unread = notificationService.notifications.filter { !$0.read }
        
        switch filter {
        case .all:
            return unreadCount
        case .follows:
            return unread.filter {
                $0.type == .follow || $0.type == .followRequestAccepted
            }.count
        case .conversations:
            return unread.filter {
                $0.type == .comment || $0.type == .reply || $0.type == .repost
            }.count
        case .mentions:
            return unread.filter { $0.type == .mention }.count
        }
    }
    
    private func markAllAsRead() {
        dlog("🔔 [NOTIF] markAllAsRead — unreadCount before=\(notificationService.unreadCount)")
        // Badge is cleared AFTER Firestore writes land to prevent the BadgeCountManager
        // notificationsListener from re-reading stale unread docs and flipping the
        // app icon badge back from 0 to the old count (0→8 race condition).
        Task {
            try? await notificationService.markAllAsRead()
            dlog("🔔 [NOTIF] markAllAsRead complete — unreadCount after=\(notificationService.unreadCount)")
            clearBadgeCount()
        }
    }
    
    private func markAsRead(_ notification: AppNotification) {
        Task {
            guard let id = notification.id else { return }
            try? await notificationService.markAsRead(id)
            // Update badge count immediately after marking individual notification as read
            await BadgeCountManager.shared.immediateUpdate()
        }
    }
    
    private func removeNotification(_ notification: AppNotification) async {
        guard let id = notification.id else { return }
        try? await notificationService.deleteNotification(id)
        await BadgeCountManager.shared.immediateUpdate()
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
    
    var timeAgo: String {
        let interval = Date().timeIntervalSince(mostRecentDate)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
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

// MARK: - Section Header

/// Pinned section header shown above each time bucket (Today / Yesterday / This Week / Older).
/// Thin, low-profile — same visual weight as Threads/Instagram section dividers.
private struct NotificationSectionHeader: View {
    let label: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: label == "New" ? 16 : 14, weight: label == "New" ? .bold : .semibold))
                .foregroundStyle(label == "New" ? Color.primary : Color(uiColor: .secondaryLabel))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, label == "New" ? 12 : 8)
        .padding(.bottom, 6)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Grouped Notification Row (Threads-style)

struct GroupedNotificationRow: View {
    let group: NotificationGroup
    let onDismiss: () -> Void
    let onMarkAsRead: () -> Void
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onAvatarTap: (String) -> Void

    @ObservedObject private var followService = FollowService.shared
    @ObservedObject private var profileCache = NotificationProfileCache.shared
    @State private var actorProfile: CachedProfile?
    // Optimistic follow state — hides Follow Back button immediately on tap
    @State private var didFollowBack = false

    private var isFollowType: Bool {
        group.primaryNotification.type == .follow ||
        group.primaryNotification.type == .followRequestAccepted
    }

    private var showFollowBack: Bool {
        guard isFollowType, !didFollowBack else { return false }
        guard let actorId = group.primaryNotification.actorId, !actorId.isEmpty else { return false }
        return !followService.following.contains(actorId)
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Left unread dot (Threads-style)
                Circle()
                    .fill(group.hasUnread ? Color.blue : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 22)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: group.hasUnread)
                    .accessibilityHidden(true)

                // Avatar with type badge overlay
                avatarView

                // Text content (name + action + timestamp + preview)
                VStack(alignment: .leading, spacing: 2) {
                    notificationText

                    // Timestamp
                    Text(group.primaryNotification.timeAgo)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing area: Follow Back OR thumbnail
                trailingView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(group.hasUnread ? Color(uiColor: .secondarySystemBackground).opacity(0.5) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(NotificationRowButtonStyle())
        .contextMenu {
            Button { onMarkAsRead() } label: {
                Label(group.hasUnread ? "Mark as Read" : "Mark as Unread", systemImage: "envelope.open")
            }
            if let actorName = group.primaryNotification.actorName {
                Button {
                    // Mute this user's notifications
                    if let actorId = group.primaryNotification.actorId {
                        Task { try? await ModerationService.shared.muteUser(userId: actorId) }
                    }
                } label: {
                    Label("Mute \(actorName.components(separatedBy: " ").first ?? actorName)", systemImage: "speaker.slash")
                }
            }
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onDismiss() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onLongPressGesture { onLongPress() }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { onMarkAsRead() } label: {
                Label("Read", systemImage: "envelope.open")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onDismiss() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            if let actorId = group.primaryNotification.actorId {
                actorProfile = await profileCache.getProfile(userId: actorId)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Notification text builder

    @ViewBuilder
    private var notificationText: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1-2: "username liked your post · 4m"
            HStack(spacing: 0) {
                notificationAttributedText
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(2)

                Text(" · \(group.timeAgo)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }

            // Line 3: comment preview (if comment/reply)
            if let preview = group.primaryNotification.commentText, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)
            }
        }
    }

    /// Builds an `AttributedString` with bold actor name(s) and plain action text.
    /// Rules:
    ///   1 actor  → "[Name] liked your post"
    ///   2 actors → "[Name] and [Name2] liked your post"
    ///   3+ actors → "[Name] and N others liked your post"
    private var notificationAttributedText: Text {
        let action = group.primaryNotification.actionText
        let names = group.actorNames
        let others = group.otherCount

        func boldAttr(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            a.font = .system(size: 15, weight: .semibold)
            a.foregroundColor = .label
            return a
        }
        func plainAttr(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            a.foregroundColor = .secondaryLabel
            return a
        }

        var result = AttributedString()

        if names.isEmpty {
            result.append(plainAttr(action))
        } else if !group.isGrouped {
            // Single actor
            result.append(boldAttr(names[0]))
            result.append(plainAttr(" \(action)"))
        } else if names.count == 1 && others == 0 {
            // Grouped but only one distinct actor name
            result.append(boldAttr(names[0]))
            result.append(plainAttr(" \(action)"))
        } else if names.count >= 2 && others == 0 {
            // Exactly 2 actors: "Name and Name2 action"
            result.append(boldAttr(names[0]))
            result.append(plainAttr(" and "))
            result.append(boldAttr(names[1]))
            result.append(plainAttr(" \(action)"))
        } else {
            // 3+ actors: "Name and N others action"
            let othersLabel = others == 1 ? "1 other" : "\(others) others"
            result.append(boldAttr(names[0]))
            result.append(plainAttr(" and \(othersLabel) \(action)"))
        }

        return Text(result)
    }

    // MARK: - Trailing view: Follow Back button or post thumbnail

    @ViewBuilder
    private var trailingView: some View {
        if showFollowBack {
            FollowBackButton(actorId: group.primaryNotification.actorId ?? "") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    didFollowBack = true
                }
            }
            .transition(.scale.combined(with: .opacity))
        } else if group.primaryNotification.type != .follow,
                  group.primaryNotification.type != .followRequestAccepted {
            // Post thumbnail placeholder (42×42 gray square like Threads/Instagram)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: group.primaryNotification.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(group.primaryNotification.color)
                )
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            if group.isGrouped {
                groupedAvatarStack
            } else {
                NotificationProfileImage(
                    imageURL: group.primaryNotification.actorProfileImageURL ?? actorProfile?.imageURL,
                    fallbackName: group.primaryNotification.actorName,
                    fallbackColor: group.primaryNotification.color,
                    size: 44
                )
            }

            // Notification type badge (bottom-right of avatar)
            Circle()
                .fill(group.primaryNotification.color)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: group.primaryNotification.icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
                .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 1.5))
                .offset(x: 4, y: 4)
        }
        .frame(width: 52, height: 52)
        .contentShape(Circle().size(CGSize(width: 52, height: 52)))
        .onTapGesture {
            if let actorId = group.primaryNotification.actorId, !actorId.isEmpty {
                onAvatarTap(actorId)
            }
        }
        .accessibilityHidden(true) // full row has combined accessibility
    }

    /// Up to 3 stacked avatars for grouped notifications.
    /// Layout (left-to-right depth): third (smallest, back) → second → first (front, largest).
    /// Each ring has a 2pt white border to separate overlapping circles.
    @ViewBuilder
    private var groupedAvatarStack: some View {
        let actors = group.actorProfiles
        // Sizes and offsets for a 3-deep fan effect anchored to the primary (front) avatar
        // The container stays 44×44 so the badge overlay reference point is stable.
        ZStack(alignment: .bottomLeading) {
            // Third avatar — smallest, furthest back
            if actors.count >= 3 {
                NotificationProfileImage(
                    imageURL: actors[safe: 2]?.profileImageURL,
                    fallbackName: actors[safe: 2]?.name,
                    fallbackColor: group.primaryNotification.color.opacity(0.4),
                    size: 24
                )
                .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                .offset(x: -18, y: 18)
            }
            // Second avatar — medium, mid-layer
            if actors.count >= 2 {
                NotificationProfileImage(
                    imageURL: actors[safe: 1]?.profileImageURL,
                    fallbackName: actors[safe: 1]?.name,
                    fallbackColor: group.primaryNotification.color.opacity(0.6),
                    size: 30
                )
                .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                .offset(x: -10, y: 12)
            }
            // Primary avatar — largest, front
            NotificationProfileImage(
                imageURL: actors.first?.profileImageURL,
                fallbackName: actors.first?.name,
                fallbackColor: group.primaryNotification.color,
                size: 44
            )
        }
        .frame(width: 44, height: 44)
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let actorName = group.primaryNotification.actorName {
            parts.append(actorName)
        }
        parts.append(group.primaryNotification.actionText)
        if let commentText = group.primaryNotification.commentText, !commentText.isEmpty {
            parts.append(commentText)
        }
        parts.append(group.primaryNotification.timeAgo)
        if group.hasUnread { parts.append("unread") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Follow Back Button

private struct FollowBackButton: View {
    let actorId: String
    let onFollowBack: () -> Void

    @State private var isFollowingBack = false

    var body: some View {
        Button {
            guard !isFollowingBack else { return }
            isFollowingBack = true
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            onFollowBack()
            Task {
                try? await FollowService.shared.followUser(userId: actorId)
            }
        } label: {
            Text(isFollowingBack ? "Following" : "Follow back")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isFollowingBack ? Color(uiColor: .label) : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if isFollowingBack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color(uiColor: .separator), lineWidth: 0.8)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: .label))
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isFollowingBack)
        .accessibilityLabel(isFollowingBack ? "Following" : "Follow back")
        .accessibilityHint(isFollowingBack ? "" : "Double tap to follow this person back")
    }
}

// MARK: - Safe Array subscript (notifications)
private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
                    // Real Firestore error (network, permissions, etc.) — log and bail.
                    if let error = error {
                        dlog("⚠️ Profile listener error for \(userId): \(error.localizedDescription)")
                        return
                    }
                    // Document doesn't exist (deleted user) — silent return, not an error.
                    guard let document = documentSnapshot,
                          let data = document.data() else {
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

    // ── Per-type grouping windows ─────────────────────────────────────────
    // Likes/amens/reactions → 24 h (many actors pile up over a day)
    // Follows              → 12 h
    // Comments/replies     → group by thread (no time window — same postId always groups)
    // Mentions             → 6 h per conversation
    // Everything else      → 30 min
    private static let likeWindow:    TimeInterval = 86_400   // 24 h
    private static let followWindow:  TimeInterval = 43_200   // 12 h
    private static let mentionWindow: TimeInterval = 21_600   //  6 h
    private static let defaultWindow: TimeInterval = 1_800    // 30 min

    // ── Solo types — never grouped ────────────────────────────────────────
    // DMs, security, system events should always show as individual items.
    private static let soloTypes: Set<AppNotification.NotificationType> = [
        .message,
        .messageRequest,
        .messageRequestAccepted,
        .prayerReminder,
        .unknown
    ]

    private init() {}

    // MARK: - Deduplication

    /// Remove duplicate notifications using fingerprinting (5-min near-duplicate window).
    func deduplicate(_ notifications: [AppNotification]) -> [AppNotification] {
        var unique: [AppNotification] = []
        var seen: Set<String> = []
        for n in notifications {
            let fp = generateFingerprint(for: n)
            if seen.insert(fp).inserted {
                unique.append(n)
            } else {
                dlog("🔍 Duplicate detected: \(n.type) from \(n.actorName ?? "unknown")")
            }
        }
        seenFingerprints = seen
        dlog("✅ Deduplicated: \(notifications.count) → \(unique.count) notifications")
        return unique
    }

    /// Fingerprint: type + actorId + postId + 5-min bucket.
    private func generateFingerprint(for n: AppNotification) -> String {
        let bucket = Int(n.createdAt.seconds) / 300 * 300
        var parts = [n.type.rawValue]
        if let v = n.actorId      { parts.append(v) }
        if let v = n.postId       { parts.append(v) }
        parts.append("\(bucket)")
        return parts.joined(separator: "|")
    }

    // MARK: - Grouping

    /// Group unique notifications using per-type time windows.
    func groupNotifications(_ notifications: [AppNotification]) -> [NotificationGroup] {
        let unique = deduplicate(notifications)
        var buckets: [String: [AppNotification]] = [:]
        for n in unique {
            let key = generateGroupKey(for: n)
            buckets[key, default: []].append(n)
        }

        var groups: [NotificationGroup] = []
        for (_, members) in buckets {
            guard let primary = members.first else { continue }
            if let g = NotificationGroup(notifications: members) {
                groups.append(g)
                if members.count > 1 {
                    dlog("📦 Grouped \(members.count) \(primary.type) notifications")
                }
            }
        }
        return groups.sorted { $0.mostRecentDate > $1.mostRecentDate }
    }

    // MARK: - Group Key

    /// Build a stable grouping key with per-type semantics.
    private func generateGroupKey(for n: AppNotification) -> String {
        // Solo types — unique key per notification (never grouped)
        if Self.soloTypes.contains(n.type) {
            return n.id ?? UUID().uuidString
        }

        let window = timeWindow(for: n.type)
        let timeBucket = Int(Double(n.createdAt.seconds) / window) * Int(window)

        var parts = [n.type.rawValue]

        switch n.type {
        case .amen, .repost:
            // Group all amens/reposts on the same post within 24 h
            if let postId = n.postId { parts.append(postId) }
            parts.append("\(timeBucket)")

        case .follow, .followRequestAccepted:
            // Group new followers within 12 h (no per-post anchor)
            parts.append("\(timeBucket)")

        case .comment, .reply:
            // Group by thread: same postId + same parent commentId (if present)
            if let postId = n.postId { parts.append(postId) }
            if let cid = n.commentId { parts.append(cid) }
            parts.append("\(timeBucket)")

        case .mention:
            // Group by conversation or post within 6 h
            if let convId = n.conversationId {
                parts.append(convId)
            } else if let postId = n.postId {
                parts.append(postId)
            }
            parts.append("\(timeBucket)")

        default:
            if let postId = n.postId { parts.append(postId) }
            parts.append("\(timeBucket)")
        }

        return parts.joined(separator: "_")
    }

    private func timeWindow(for type: AppNotification.NotificationType) -> TimeInterval {
        switch type {
        case .amen, .repost:               return Self.likeWindow
        case .follow, .followRequestAccepted: return Self.followWindow
        case .mention:                     return Self.mentionWindow
        default:                           return Self.defaultWindow
        }
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
    @State private var shimmerPhase: CGFloat = -1.0

    var body: some View {
        HStack(spacing: 14) {
            // Unread dot placeholder
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 8, height: 8)

            // Avatar skeleton
            Circle()
                .fill(Color(uiColor: .secondarySystemFill))
                .frame(width: 44, height: 44)
                .nxShimmer(phase: shimmerPhase)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(width: 180, height: 13)
                    .nxShimmer(phase: shimmerPhase)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(width: 80, height: 11)
                    .nxShimmer(phase: shimmerPhase)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.4
            }
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

// Phase-based shimmer — no UUID trick, properly animates
extension View {
    func nxShimmer(phase: CGFloat) -> some View {
        self.overlay {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.36), .clear],
                    startPoint: .init(x: phase - 0.4, y: 0.5),
                    endPoint: .init(x: phase + 0.4, y: 0.5)
                )
            }
        }
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
