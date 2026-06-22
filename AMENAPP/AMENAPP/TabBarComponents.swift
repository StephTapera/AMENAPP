import SwiftUI

// MARK: - Animated Quick Action Button with Press Effects

struct AnimatedQuickActionButton: View {
    let icon: String
    let title: String
    let delay: Double
    let action: () -> Void

    @State private var isPressed = false
    @State private var isAppeared = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)
                    .frame(width: 22)

                Text(title)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(isPressed ? Color.primary.opacity(0.5) : Color.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPressed ? Color.black.opacity(0.08) : Color.clear)
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .opacity(isAppeared ? 1 : 0)
            .offset(x: isAppeared ? 0 : -10)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.08)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75)).delay(delay)) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Arrow Shape for Context Menu

struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - 10, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Compact Tab Bar (DEPRECATED — superseded by AMENTabBar in AMENTabBar.swift)
// This component is no longer instantiated anywhere. AMENTabBar renders the canonical
// 5-tab (home/search/messages/library/profile) pill bar with a floating compose button.
// Do NOT add this back to ContentView or any other view — use AMENTabBar instead.
@available(*, deprecated, renamed: "AMENTabBar", message: "Use AMENTabBar which renders exactly 5 tabs via AMENTab.visibleTabs")
struct CompactTabBar: View {
    @Binding var selectedTab: Int
    @Binding var showCreatePost: Bool
    @Binding var showCreateQuickActions: Bool
    // P0-7: Use @EnvironmentObject instead of @ObservedObject for singletons
    // This prevents unnecessary view re-creation and improves memory usage
    @EnvironmentObject private var messagingService: FirebaseMessagingService
    @EnvironmentObject private var postsManager: PostsManager
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var notificationService: NotificationService
    // ✅ P0-10, P0-11, P0-12 FIX: Access BadgeCountManager as single source of truth
    @EnvironmentObject private var badgeCountManager: BadgeCountManager
    // ✅ Shabbat Mode: Access church focus manager
    @EnvironmentObject private var churchFocusManager: SundayChurchFocusManager
    @State private var previousUnreadCount: Int = 0
    @State private var badgePulse: Bool = false
    @State private var newPostsBadgePulse: Bool = false
    @State private var lastSeenPostTime: Date = Date()
    @Namespace private var pillNS

    // Tab haptic handled by AMENTabBar's .sensoryFeedback(.selection) — no duplicate needed

    // PERFORMANCE FIX: Navigation tap protection
    @State private var isNavigating = false
    @State private var lastTapTime: Date = .distantPast
    @State private var lastHomeRefreshDate: Date = .distantPast
    @State private var isHomeRefreshInFlight = false
    private let homeAutoRefreshCooldown: TimeInterval = 60

    // ✅ REAL-TIME PROFILE PHOTO UPDATE
    @State private var profilePhotoUpdateTrigger = UUID() // Force AsyncImage to reload

    // All tabs in order: Home, People, Messages, Resources, Notifications, Profile
    let allTabs: [(icon: String, tag: Int)] = [
        ("house.fill", 0),
        ("magnifyingglass", 1),
        ("message.fill", 2),
        ("books.vertical.fill", 3),
        ("bell.fill", 4),
        ("person.fill", 5)
    ]

    // ✅ P0-10, P0-11, P0-12 FIX: Use BadgeCountManager as single source of truth
    private var totalUnreadCount: Int {
        badgeCountManager.unreadMessages
    }

    // Computed property for new posts indicator
    private var hasNewPosts: Bool {
        guard let latestPost = postsManager.allPosts.first else { return false }
        return latestPost.createdAt > lastSeenPostTime
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {

            // ── Floating pill with all nav icons ──
            HStack(spacing: 0) {
                ForEach(Array(allTabs.enumerated()), id: \.element.tag) { _, tab in
                    tabButton(for: tab, isSelected: selectedTab == tab.tag)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(glassmorphicBackground)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 8)
            .shadow(color: .black.opacity(0.15), radius: 4,  x: 0, y: 2)

            // ── Compose button — separate glass circle ──
            createButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 5)
        .onChange(of: totalUnreadCount) { oldValue, newValue in
            // Trigger pulse animation when unread count increases
            if newValue > oldValue {
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.5))) {
                    badgePulse = true
                }

                // Haptic feedback for new message
                HapticManager.notification(type: .success)

                // Reset pulse after animation
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        withAnimation { badgePulse = false }
                    }
                }
            }
            previousUnreadCount = newValue
        }
        .onChange(of: postsManager.allPosts.count) { oldValue, newValue in
            // Trigger pulse animation when new posts are added
            if newValue > oldValue && selectedTab != 0 {
                // Only show if user is not on Home tab
                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.5))) {
                    newPostsBadgePulse = true
                }

                // Haptic feedback for new post
                HapticManager.notification(type: .success)

                // Reset pulse after animation
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        withAnimation { newPostsBadgePulse = false }
                    }
                }
            }
        }
        .onAppear {
            previousUnreadCount = totalUnreadCount
            lastSeenPostTime = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("profilePhotoUpdated"))) { notification in
            // ✅ REAL-TIME UPDATE: Refresh tab bar profile photo immediately
            if let imageURL = notification.userInfo?["profileImageURL"] as? String {
                // Update UserDefaults cache
                if !imageURL.isEmpty {
                    UserDefaults.standard.set(imageURL, forKey: "currentUserProfileImageURL")
                } else {
                    UserDefaults.standard.removeObject(forKey: "currentUserProfileImageURL")
                }

                // Trigger re-render by changing UUID
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    profilePhotoUpdateTrigger = UUID()
                }

                // Success haptic
                HapticManager.impact(style: .light)
            }
        }
    }

    // MARK: - Glassmorphic Background (adaptive — ultraThinMaterial auto-adjusts for dark/light)

    private var glassmorphicBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
    }

    // MARK: - Tab Button (Smaller Icon-Only Pill Style)

    @ViewBuilder
    private func tabButton(for tab: (icon: String, tag: Int), isSelected: Bool) -> some View {
        Button {
            // If already on this tab, handle same-tab re-tap (scroll to top + refresh)
            if selectedTab == tab.tag {
                if tab.tag == 0 {
                    NotificationCenter.default.post(name: .homeTabTapped, object: nil)
                    HapticManager.impact(style: .light)
                }
                return
            }

            // PERFORMANCE FIX: Debounce rapid taps (300ms window)
            let now = Date()
            guard now.timeIntervalSince(lastTapTime) > 0.3 else {
                return
            }
            lastTapTime = now

            // PERFORMANCE FIX: Prevent re-entrant navigation
            guard !isNavigating else {
                return
            }

            isNavigating = true

            dlog("🚦 [TAB] User tapped tab bar → selectedTab = \(tab.tag) (from \(selectedTab))")
            withAnimation(Motion.adaptive(.spring(response: 0.38, dampingFraction: 0.72))) {
                selectedTab = tab.tag
            }

            // Auto-refresh Home feed when switching to Home tab from another tab
            if tab.tag == 0 {
                let shouldRefresh = postsManager.openTablePosts.isEmpty
                    || Date().timeIntervalSince(lastHomeRefreshDate) > homeAutoRefreshCooldown
                if shouldRefresh && !isHomeRefreshInFlight {
                    isHomeRefreshInFlight = true
                    Task {
                        await postsManager.refreshPosts()
                        await MainActor.run {
                            lastHomeRefreshDate = Date()
                            isHomeRefreshInFlight = false
                        }
                    }
                }
                // Mark posts as seen
                lastSeenPostTime = Date()
            }

            // Immediately clear badge dots when user taps into those tabs
            if tab.tag == 2 {
                badgeCountManager.clearMessages()
            }
            // Notifications is tag 4 (bell), not tag 5 (profile)
            if tab.tag == 4 {
                badgeCountManager.clearNotifications()
            }

            // Reset navigation guard after animation completes
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run { isNavigating = false }
            }
        } label: {
            ZStack {
                // ── Sliding active pill — matchedGeometryEffect moves it between tabs ──
                if isSelected {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "activePill", in: pillNS)
                }

                // Icon + badge stack
                VStack(spacing: 2) {
                    ZStack(alignment: .topTrailing) {
                        // Selection circle background (adaptive tint — visible in both light & dark)
                        Circle()
                            .fill(Color.primary.opacity(isSelected ? 0.08 : 0))
                            .frame(width: 44, height: 44)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)

                        // Profile tab shows user's photo if available
                        if tab.tag == 5 {
                            profileTabContent(isSelected: isSelected)
                        } else {
                            Image(systemName: tab.icon)
                                // Icon pops to semibold + slightly larger when selected
                                .font(.system(
                                    size: isSelected ? 22 : 20,
                                    weight: isSelected ? .semibold : .regular
                                ))
                                .foregroundStyle(.primary)
                                // Scales up ahead of the pill landing (snappier spring)
                                .scaleEffect(isSelected ? 1.12 : 1.0)
                                .animation(
                                    .spring(response: 0.32, dampingFraction: 0.65),
                                    value: isSelected
                                )
                                // Native bounce fires once on selection (iOS 17+)
                                .symbolEffect(.bounce, value: isSelected)
                        }

                        // Messages unread badge
                        if tab.tag == 2 && totalUnreadCount > 0 {
                            SmartMessageBadge(unreadCount: totalUnreadCount, pulse: badgePulse)
                                .offset(x: 2, y: -2)
                        }

                        // Home new-posts dot
                        if tab.tag == 0 && hasNewPosts {
                            UnreadDot(pulse: newPostsBadgePulse)
                                .offset(x: 2, y: -2)
                        }

                        // Notifications dot
                        if tab.tag == 4 && badgeCountManager.unreadNotifications > 0 {
                            UnreadDot(pulse: false)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .offset(y: isSelected ? -2 : 0)
                    .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isSelected)

                    // Active dot — uses brand accent (AmenTheme.Colors.amenGold)
                    Circle()
                        .fill(AmenTheme.Colors.amenGold)
                        .frame(width: 4, height: 4)
                        .scaleEffect(isSelected ? 1.0 : 0.01)
                        .opacity(isSelected ? 1.0 : 0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: isSelected)
                }
                .frame(width: 44, height: 40)
            }
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(tabAccessibilityLabel(for: tab.tag))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func tabAccessibilityLabel(for tag: Int) -> String {
        switch tag {
        case 0: return "Home"
        case 1: return "Discover"
        case 2: return totalUnreadCount > 0 ? "Messages, \(totalUnreadCount) unread" : "Messages"
        case 3: return "Resources"
        case 4: return badgeCountManager.unreadNotifications > 0 ? "Notifications, \(badgeCountManager.unreadNotifications) unread" : "Notifications"
        case 5: return "Profile"
        default: return "Tab"
        }
    }

    // MARK: - Profile Tab Content

    @ViewBuilder
    private func profileTabContent(isSelected: Bool) -> some View {
        Group {
            // Try to get profile image URL from UserDefaults cache first (faster)
            let cachedImageURL = UserDefaults.standard.string(forKey: "currentUserProfileImageURL")

            if let photoURL = cachedImageURL ?? userService.currentUser?.profileImageURL,
               !photoURL.isEmpty,
               let url = URL(string: photoURL) {
                // User has profile photo - show it
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 26, height: 26)  // Smaller profile photo for compact tab bar
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        isSelected ? Color.primary : Color.secondary.opacity(0.5),
                                        lineWidth: isSelected ? 1.5 : 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            .symbolEffect(.bounce, value: isSelected)
                    case .failure(_):
                        // Fallback to icon if image fails to load
                        Image(systemName: "person.fill")
                            .font(.systemScaled(18, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .symbolEffect(.bounce, value: isSelected)
                    case .empty:
                        // Show loading placeholder
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 26, height: 26)  // Smaller placeholder
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.6)
                            )
                    @unknown default:
                        Image(systemName: "person.fill")
                            .font(.systemScaled(20, weight: isSelected ? .semibold : .medium))  // Smaller icon
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
                .id(profilePhotoUpdateTrigger) // ✅ Force reload when UUID changes
            } else {
                // No profile photo - show default icon
                Image(systemName: "person.fill")
                    .font(.systemScaled(20, weight: isSelected ? .semibold : .medium))  // Smaller icon
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .symbolEffect(.bounce, value: isSelected)
            }
        }
        .task {
            // Ensure user data is loaded
            if userService.currentUser == nil {
                await userService.fetchCurrentUser()
            }
        }
    }

    // MARK: - Create Button (Smaller with Glassmorphic Touch)

    @State private var createButtonScale: CGFloat = 1.0

    @State private var isLongPressing = false

    private var createButton: some View {
        ZStack {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
                .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                .frame(width: 54, height: 54)

            Image(systemName: "plus")
                .font(.systemScaled(22, weight: .semibold))
                .foregroundStyle(.primary)
                // Rotates 45° → 0° on first appear — subtle "unfurl"
                .transition(.opacity)
        }
        .scaleEffect(createButtonScale)
        .brightness(isLongPressing ? 0.06 : 0)
        .animation(.spring(response: 0.22, dampingFraction: 0.55), value: createButtonScale)
        .contentShape(Circle())
        .accessibilityLabel("Create post")
        .accessibilityHint("Tap to compose a new post. Long press for quick options.")
        .onTapGesture {
            // Regular tap - open create post immediately

            // PERFORMANCE FIX: Debounce rapid taps
            let now = Date()
            guard now.timeIntervalSince(lastTapTime) > 0.3 else { return }
            lastTapTime = now

            // PERFORMANCE FIX: Prevent duplicate sheet presentation
            guard !showCreatePost else { return }

            // ✅ Shabbat Mode: Block create post during church focus window
            guard !SundayChurchFocusManager.shared.shouldGateFeature() else {
                // Show Shabbat Mode gate
                NotificationCenter.default.post(name: .showShabbatModeGate, object: nil)
                HapticManager.notification(type: .warning)
                return
            }

            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.6))) {
                showCreatePost = true
            }
            HapticManager.impact(style: .light)
        }
        .simultaneousGesture(
            // Long press - show quick actions menu (optional feature)
            LongPressGesture(minimumDuration: 0.5)
                .onChanged { _ in
                    if !isLongPressing {
                        isLongPressing = true
                        HapticManager.impact(style: .light)

                        withAnimation(Motion.adaptive(.spring(response: 0.15, dampingFraction: 0.8))) {
                            createButtonScale = 0.9
                        }
                    }
                }
                .onEnded { _ in
                    HapticManager.notification(type: .success)

                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.8))) {
                        createButtonScale = 1.0
                        showCreateQuickActions = true
                    }

                    // Reset after a delay
                    Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        await MainActor.run { isLongPressing = false }
                    }
                }
        )
    }
}

// MARK: - Unread Badge Component

struct UnreadDot: View {
    let pulse: Bool

    var body: some View {
        ZStack {
            // Pulse ring (only when pulse is active)
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }

            // White border ring — separates dot from icon underneath (Instagram-style)
            Circle()
                .fill(Color(UIColor.systemBackground))
                .frame(width: 9, height: 9)

            // Main dot
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.15 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulse)
        }
        // CRITICAL FIX: Color-only indicator. The dot communicates state visually via
        // color alone. The parent tab button already exposes the count through
        // tabAccessibilityLabel (e.g. "Notifications, 3 unread"), so this dot is purely
        // decorative — hide it from the AX tree to avoid redundant/confusing announcements.
        .accessibilityHidden(true)
    }
}

// MARK: - Smart Message Badge (Shows count then transitions to dot)

struct SmartMessageBadge: View {
    let unreadCount: Int
    let pulse: Bool
    @State private var showCount: Bool = true

    var body: some View {
        ZStack {
            // Pulse ring (only when pulse active)
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: showCount ? 22 : 14, height: showCount ? 22 : 14)
                    .scaleEffect(pulse ? 1.8 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }

            if showCount && unreadCount > 0 {
                // Count badge with white border
                ZStack {
                    // White border ring
                    Capsule()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: max(19, CGFloat(unreadCount > 9 ? 23 : 19)), height: 19)

                    Capsule()
                        .fill(Color.red)
                        .frame(width: max(16, CGFloat(unreadCount > 9 ? 20 : 16)), height: 16)

                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .font(.systemScaled(10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(pulse ? 1.15 : 1.0)
                .transition(.scale.combined(with: .opacity))
            } else {
                // Simple dot matching UnreadDot style
                ZStack {
                    Circle()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: 9, height: 9)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 6, height: 6)
                }
                .scaleEffect(pulse ? 1.15 : 1.0)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .task(id: unreadCount) {
            // Show count for 2 seconds on appear or whenever unreadCount increases,
            // then transition back to dot. Using .task(id:) automatically cancels
            // the previous sleep when unreadCount changes.
            guard unreadCount > 0 else { return }
            showCount = true
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                showCount = false
            }
        }
    }
}
