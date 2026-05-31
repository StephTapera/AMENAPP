//
//  PrayerView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import Combine
import UIKit
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore

struct PrayerView: View {
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var prayerAlgorithm = PrayerAlgorithm.shared
    @State private var selectedTab: PrayerTab = .requests
    @State private var showDailyPrayer = false
    @State private var showPrayerGroups = false
    @State private var showPrayerWall = false
    @State private var showLiveDiscussion = false
    @State private var showCollaborationHub = false
    @State private var currentBannerIndex = 0
    @State private var isBannerExpanded = true  // ✅ NEW: Toggle for banner visibility
    @State private var rankedPrayers: [Post] = []
    @State private var hasRanked = false
    @State private var scrollViewDelegate: ScrollViewDelegateHandler?
    @State private var showHeader = true
    @State private var pressedTab: PrayerTab? = nil
    private let tabHaptic = UIImpactFeedbackGenerator(style: .light)
    
    // ⚡️ PERFORMANCE FIX: Reduced initial load for faster first render
    // MARK: - Pagination State
    @State private var visiblePostCount = 15  // Reduced from 20 to 15
    @State private var isLoadingMore = false
    @State private var viewedPostIds: Set<UUID> = []

    @Environment(\.tabBarVisible) private var tabBarVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion


    enum PrayerTab: String, CaseIterable {
        case requests = "Requests"
        case praises = "Praises"
        case answered = "Answered"
    }
    
    // MARK: - Filtered Posts

    /// Computed once per body evaluation — callers must snapshot with `let posts = filteredPosts`
    /// rather than evaluating this multiple times per render pass (expensive filter + sort).
    var filteredPosts: [Post] {
        let t0 = Date()
        var posts = postsManager.prayerPosts.filter { post in
            guard let topicTag = post.topicTag else { return false }
            switch selectedTab {
            case .requests: return topicTag == "Prayer Request"
            case .praises:  return topicTag == "Praise Report"
            case .answered: return topicTag == "Answered Prayer"
            }
        }
        // Apply ranking for requests tab
        if selectedTab == .requests && hasRanked && !rankedPrayers.isEmpty {
            let rankedIds = Set(rankedPrayers.map { $0.id })
            posts = rankedPrayers.filter { rankedIds.contains($0.id) }
        }
        let ms = Date().timeIntervalSince(t0) * 1000
        if ms > 5 { dlog("⚡️ [PrayerView] filteredPosts took \(String(format: "%.1f", ms))ms (\(posts.count) posts, tab=\(selectedTab.rawValue))") }
        return posts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

                // MARK: Header
                if showHeader {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("#Prayer")
                            .font(AMENFont.bold(24))
                            .foregroundStyle(.primary)
                        Text("Pray together, grow together")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // MARK: Filter Tabs
                HStack {
                    Spacer()
                    AmenLiquidGlassFilterPillRow(selection: $selectedTab)
                    Spacer()
                }
                .padding(.horizontal, 16)

                // MARK: Fruit of the Spirit Banner
                FruitOfSpiritBannerView()

                // MARK: Prayer Action Rail
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        AmenLiquidGlassPillButton(
                            title: "Daily Prayer",
                            systemImage: "sun.horizon.fill",
                            isLoading: false,
                            isDisabled: false,
                            hint: "Open today's guided prayer prompts"
                        ) {
                            showDailyPrayer = true
                        }

                        AmenLiquidGlassPillButton(
                            title: "Prayer Groups",
                            systemImage: "person.3.fill",
                            isLoading: false,
                            isDisabled: false,
                            hint: "Browse and join prayer groups"
                        ) {
                            showPrayerGroups = true
                        }

                        AmenLiquidGlassPillButton(
                            title: "Prayer Wall",
                            systemImage: "square.grid.2x2.fill",
                            isLoading: false,
                            isDisabled: false,
                            hint: "Browse the community prayer wall"
                        ) {
                            showPrayerWall = true
                        }

                        AmenLiquidGlassPillButton(
                            title: "Live Discussion",
                            systemImage: "waveform.circle.fill",
                            isLoading: false,
                            isDisabled: false,
                            hint: "Join a live prayer discussion"
                        ) {
                            showLiveDiscussion = true
                        }

                        AmenLiquidGlassPillButton(
                            title: "Pray Together",
                            systemImage: "hands.sparkles.fill",
                            isLoading: false,
                            isDisabled: false,
                            hint: "Find prayer partners in the community"
                        ) {
                            showCollaborationHub = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }

                // MARK: Prayer Rooms
                PrayerRoomsSection()
                    .onAppear { PrayerRoomService.shared.startListening() }

                // MARK: Posts Feed
                LazyVStack(spacing: 0) {
                    // Snapshot once — avoids triple filter+sort on every body re-evaluation.
                    let allPosts = filteredPosts
                    let displayPosts = Array(allPosts.prefix(visiblePostCount))

                    ForEach(displayPosts, id: \.id) { post in
                        let index = displayPosts.firstIndex(where: { $0.id == post.id }) ?? 0
                        prayerRow(post: post, index: index, total: displayPosts.count, allCount: allPosts.count)

                        // Suggested prayer connections rail — after the 3rd prayer
                        if index == 2 {
                            FeedPostDivider()
                            PrayerSuggestedRailView()
                                .background(Color(.systemBackground))
                                .padding(.vertical, 8)
                                .clipped()
                            FeedPostDivider()
                        }
                    }

                    // Pagination spinner
                    if isLoadingMore && visiblePostCount < allPosts.count {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.8).padding(.vertical, 20)
                            Spacer()
                        }
                    }

                    // Empty state
                    if allPosts.isEmpty {
                        VStack(spacing: 16) {
                            AmenGlass3DIcon(systemName: emptyStateGlassIcon, tint: AmenTheme.Colors.amenGold, size: 72)
                            Text(emptyStateTitle)
                                .font(AMENFont.bold(18))
                                .foregroundStyle(.primary)
                            Text(emptyStateSubtitle)
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
                    }
                }
                .padding(.horizontal)
        }
        .overlay(alignment: .bottom) {
            BurdenMatchPrompt()
                .padding(.bottom, 16)
                .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.7), value: BurdenMatchService.shared.showMatchPrompt)
        }
        .task {
            // Keep listener alive across tab switches — only start if not already active
            FirebasePostService.shared.startListening(category: .prayer)
            if !hasRanked {
                prayerAlgorithm.loadHistory()
                rankPrayerRequests()
                hasRanked = true
            }
            // Check for burden matches in background
            BurdenMatchService.shared.checkForMatches()
        }
        .onAppear {
            tabHaptic.prepare()
            if postsManager.prayerPosts.isEmpty {
                Task { await refreshPrayers() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .feedDidRefresh)) { note in
            guard (note.userInfo?["category"] as? String) == "Prayer" else { return }
            visiblePostCount = 20
        }
        .onDisappear {
            // Don't stop the listener — keep it alive for real-time updates across tab switches.
            // hasRanked intentionally NOT reset: avoids expensive re-rank on every tab switch.
        }
        .onChange(of: postsManager.prayerPosts) { oldValue, newValue in
            // Only re-rank when the Prayer Request subset actually changes.
            // Guard on count change only — avoids re-rank on like/comment edits
            // that don't add/remove requests, and avoids re-rank when only
            // Praise/Answered posts change count.
            let oldRequestCount = oldValue.filter { $0.topicTag == "Prayer Request" }.count
            let newRequestCount = newValue.filter { $0.topicTag == "Prayer Request" }.count
            if oldRequestCount != newRequestCount {
                dlog("🙏 [PrayerView] Request count changed \(oldRequestCount)→\(newRequestCount), re-ranking")
                rankPrayerRequests()
            }
        }
        .onChange(of: selectedTab) { _, _ in
            visiblePostCount = 20
        }
        // MARK: - Sheet Gates
        // P1-4: route to EnhancedDailyPrayerView (DailyPrayerView.swift) which has the full feature set
        .sheet(isPresented: $showDailyPrayer) {
            EnhancedDailyPrayerView()
        }
        .sheet(isPresented: $showPrayerGroups) {
            PrayerGroupsView()
        }
        .sheet(isPresented: $showPrayerWall) {
            PrayerWallView()
        }
        // CollaborationHubView uses @Binding for dismiss and is a full-screen overlay
        // (dark backdrop + slide-up card), matching the LiveDiscussion pattern.
        .overlay {
            if showCollaborationHub {
                CollaborationHubView(isShowing: $showCollaborationHub)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(11)
                    .animation(reduceMotion ? .none : .smooth(duration: 0.3), value: showCollaborationHub)
            }
        }
        // LiveDiscussionView uses @Binding instead of @Environment(\.dismiss), so it is
        // presented as a ZStack overlay rather than a sheet.
        .overlay {
            if showLiveDiscussion {
                LiveDiscussionView(isShowing: $showLiveDiscussion)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(10)
                    .animation(reduceMotion ? .none : .smooth(duration: 0.3), value: showLiveDiscussion)
            }
        }
    }

    // MARK: - Helper Functions

    private func prayerRow(post: Post, index: Int, total: Int, allCount: Int) -> some View {
        PostCard(post: post, isUserPost: post.authorId == Auth.auth().currentUser?.uid)
            .feedItemAppear(id: post.id, delay: min(Double(index) * 0.04, 0.20))
            .onAppear {
                // Only record view once per post to avoid excessive updates during scroll
                if !viewedPostIds.contains(post.id) {
                    viewedPostIds.insert(post.id)
                    prayerAlgorithm.recordView(for: post)
                }
                // ⚡️ PERFORMANCE FIX: Load more only when 5 items from end (was 3)
                // This reduces pagination thrashing during fast scrolls
                if index >= total - 5 && !isLoadingMore && visiblePostCount < allCount {
                    loadMorePosts()
                }
            }
    }

    /// Rank prayer requests using algorithm
    private func rankPrayerRequests() {
        let snapshot = postsManager.prayerPosts.filter { $0.topicTag == "Prayer Request" }
        let history = prayerAlgorithm.userPrayerHistory

        guard !snapshot.isEmpty else {
            rankedPrayers = []
            return
        }

        let t0 = Date()
        // Snapshot captured above — safe to use from detached task without data races
        Task.detached(priority: .userInitiated) {
            let ranked = await prayerAlgorithm.rankPrayers(snapshot, for: history)
            await MainActor.run {
                let ms = Date().timeIntervalSince(t0) * 1000
                rankedPrayers = ranked
                dlog("🙏 [PrayerView] Ranked \(rankedPrayers.count) requests in \(String(format: "%.1f", ms))ms")
            }
        }
    }

    /// Refresh prayers with pull-to-refresh
    private func refreshPrayers() async {
        dlog("🔄 Refreshing Prayer posts...")
        
        let topicTag: String?
        
        switch selectedTab {
        case .requests:
            topicTag = "Prayer Request"
        case .praises:
            topicTag = "Praise Report"
        case .answered:
            topicTag = "Answered Prayer"
        }
        
        await postsManager.fetchFilteredPosts(
            for: .prayer,
            filter: "all",
            topicTag: topicTag
        )
        
        // Haptic feedback on completion
        await MainActor.run {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            dlog("✅ Prayer posts refreshed!")
        }
        
        // Reset pagination after refresh
        visiblePostCount = 20
    }
    
    // MARK: - Pagination
    
    /// Load more posts when user scrolls near the bottom
    private func loadMorePosts() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        // ⚡️ PERFORMANCE FIX: Synchronous pagination for instant response
        // No delay needed - VStack handles rendering efficiently
        let increment = 10
        // Use filteredPosts count (not prayerPosts) so we don't over-paginate
        let maxCount = filteredPosts.count
        visiblePostCount = min(visiblePostCount + increment, maxCount)
        isLoadingMore = false
    }
    
    private var emptyStateIcon: String {
        switch selectedTab {
        case .requests:
            return "hands.sparkles"
        case .praises:
            return "hands.clap"
        case .answered:
            return "checkmark.seal"
        }
    }

    private var emptyStateGlassIcon: String {
        switch selectedTab {
        case .requests: return "hands.sparkles"
        case .praises:  return "hands.clap"
        case .answered: return "checkmark.seal.fill"
        }
    }

    private var emptyStateTitle: String {
        switch selectedTab {
        case .requests:
            return "No Prayer Requests"
        case .praises:
            return "No Praise Reports"
        case .answered:
            return "No Answered Prayers"
        }
    }
    
    private var emptyStateSubtitle: String {
        switch selectedTab {
        case .requests:
            return "Be the first to share a prayer request!"
        case .praises:
            return "Share how God is working in your life!"
        case .answered:
            return "Celebrate answered prayers with the community!"
        }
    }
}

// MARK: - Prayer Banner Card (Swipable Design)

struct PrayerBannerCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let gradientColors: [Color]?
    let isBlackAndWhite: Bool

    @State private var isPressed = false
    @State private var shimmerPhase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {  // ✅ Reduced from 14 to 8
            HStack(spacing: 10) {  // ✅ Reduced from 14 to 10
                // Icon
                ZStack {
                    Circle()
                        .fill(isBlackAndWhite ? Color.black : (gradientColors?.first ?? .black).opacity(0.2))
                        .frame(width: 40, height: 40)  // ✅ Reduced from 56 to 40
                        .shadow(color: isBlackAndWhite ? .black.opacity(0.2) : (gradientColors?.first ?? .black).opacity(0.3), radius: 6, y: 2)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(18, weight: .semibold))  // ✅ Reduced from 26 to 18
                        .foregroundStyle(isBlackAndWhite ? .white : .white)
                        .symbolEffect(.pulse, options: .repeating.speed(0.7))
                }
                
                VStack(alignment: .leading, spacing: 2) {  // ✅ Reduced from 4 to 2
                    Text(title)
                        .font(AMENFont.bold(15))  // ✅ Reduced from 20 to 15
                        .foregroundStyle(isBlackAndWhite ? .black : .white)
                    
                    Text(subtitle)
                        .font(AMENFont.semiBold(11))  // ✅ Reduced from 13 to 11
                        .foregroundStyle(isBlackAndWhite ? .black.opacity(0.6) : .white.opacity(0.9))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .semibold))  // ✅ Reduced from 16 to 12
                    .foregroundStyle(isBlackAndWhite ? .black.opacity(0.3) : .white.opacity(0.7))
            }
            
            Text(description)
                .font(AMENFont.regular(11))  // ✅ Reduced from 14 to 11
                .foregroundStyle(isBlackAndWhite ? .black.opacity(0.5) : .white.opacity(0.85))
                .lineSpacing(2)  // ✅ Reduced from 3 to 2
        }
        .padding(14)  // ✅ Reduced from 20 to 14
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isBlackAndWhite {
                    RoundedRectangle(cornerRadius: 14)  // ✅ Reduced from 20 to 14
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)  // ✅ Reduced shadow
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                } else if let colors = gradientColors {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)  // ✅ Reduced from 20 to 14
                            .fill(
                                LinearGradient(
                                    colors: colors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Shimmer effect for colorful banners
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .offset(x: shimmerPhase)
                        .blur(radius: 20)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: (colors.first ?? Color.purple).opacity(0.4), radius: 10, y: 4)  // ✅ Reduced shadow
                }
            }
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(reduceMotion ? nil : .easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            if !isBlackAndWhite {
                withAnimation(reduceMotion ? nil : .linear(duration: 3).repeatForever(autoreverses: false)) {
                    shimmerPhase = 400
                }
            }
        }
    }
}

#Preview {
    PrayerView()
}

// MARK: - Daily Prayer View

struct DailyPrayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPrayerIndex = 0
    @State private var completedPrayers: Set<Int> = []
    @State private var showCompletionCelebration = false

    // MARK: - Firestore persistence key (P0-7)
    private var prayerProgressDateKey: String {
        String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    }
    
    let dailyPrayers = [
        DailyPrayerItem(
            title: "Morning Prayer",
            time: "6:00 AM - 9:00 AM",
            icon: "sunrise.fill",
            color: Color(red: 1.0, green: 0.7, blue: 0.3),
            prayer: "Lord, thank You for this new day. Guide my steps, guard my heart, and help me to walk in Your ways. Let Your presence fill every moment. Amen.",
            scripture: "\"This is the day the Lord has made; let us rejoice and be glad in it.\" - Psalm 118:24"
        ),
        DailyPrayerItem(
            title: "Midday Prayer",
            time: "12:00 PM - 2:00 PM",
            icon: "sun.max.fill",
            color: Color(red: 1.0, green: 0.85, blue: 0.4),
            prayer: "Heavenly Father, refresh my spirit in this moment. Give me strength to finish well what You've started. Help me to be a light to those around me.",
            scripture: "\"Come to me, all who are weary and burdened, and I will give you rest.\" - Matthew 11:28"
        ),
        DailyPrayerItem(
            title: "Evening Prayer",
            time: "9:00 PM - 11:00 PM",
            icon: "moon.stars.fill",
            color: Color(red: 0.4, green: 0.7, blue: 1.0),
            prayer: "Lord, thank You for carrying me through today. Forgive where I've fallen short. Grant me peaceful rest and prepare my heart for tomorrow. I trust You with all things.",
            scripture: "\"In peace I will lie down and sleep, for you alone, Lord, make me dwell in safety.\" - Psalm 4:8"
        )
    ]
    
    var body: some View {
        ZStack {
            // P1-11: adaptive background for light/dark mode
            (colorScheme == .dark ? Color.black.opacity(0.85) : AmenTheme.Colors.backgroundPrimary)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        dismiss()
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Daily Prayer")
                        .font(AMENFont.bold(24))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)
                
                Text("Three moments with God throughout your day")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                
                // Prayer cards in tab view
                TabView(selection: $currentPrayerIndex) {
                    ForEach(Array(dailyPrayers.enumerated()), id: \.offset) { index, prayer in
                        DailyPrayerCard(
                            prayer: prayer,
                            isCompleted: completedPrayers.contains(index),
                            onComplete: {
                                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                                    completedPrayers.insert(index)
                                    persistCompletedPrayers(index: index) // S3-1: persist to Firestore
                                    if completedPrayers.count == dailyPrayers.count {
                                        showCompletionCelebration = true
                                    }
                                }
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 500)
                
                // Progress indicator
                HStack(spacing: 12) {
                    ForEach(0..<dailyPrayers.count, id: \.self) { index in
                        Circle()
                            .fill(completedPrayers.contains(index) ? 
                                  Color(red: 0.4, green: 0.85, blue: 0.7) : 
                                  .white.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(completedPrayers.contains(index) ? 
                                           Color(red: 0.4, green: 0.85, blue: 0.7) : 
                                           .clear, lineWidth: 2)
                                    .scaleEffect(completedPrayers.contains(index) ? 1.5 : 1.0)
                            )
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            
            // Completion celebration
            if showCompletionCelebration {
                CompletionCelebrationView(isShowing: $showCompletionCelebration)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }
        }
        // S3-1: Load persisted prayer progress from Firestore on appear (auto-reset at midnight via date key)
        .task {
            let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
            guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
            let db = Firestore.firestore()
            if let snap = try? await db.document("users/\(uid)/dailyPrayers/\(today)").getDocument(),
               let indices = snap.data()?["completedIndices"] as? [Int] {
                completedPrayers = Set(indices)
            }
        }
    }

    // S3-1: Persist completed prayer moments to Firestore using arrayUnion for safe concurrent writes
    private func persistCompletedPrayers(index: Int) {
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        let db = Firestore.firestore()
        Task {
            try? await db.document("users/\(uid)/dailyPrayers/\(today)")
                .setData(["completedIndices": FieldValue.arrayUnion([index]),
                          "updatedAt": FieldValue.serverTimestamp()],
                         merge: true)
        }
    }
}

// MARK: - Daily Prayer Card with Liquid Glass Buttons

struct DailyPrayerCard: View {
    let prayer: DailyPrayerItem
    let isCompleted: Bool
    let onComplete: () -> Void

    @State private var showFullPrayer = false
    @State private var isButtonPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    // MARK: - Computed Properties for Button Styling
    
    private var buttonBackground: some View {
        ZStack {
            if isCompleted {
                completedButtonBackground
            } else {
                defaultButtonBackground
            }
        }
    }
    
    private var completedButtonBackground: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            prayer.color.opacity(0.25),
                            prayer.color.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            prayer.color.opacity(0.6),
                            prayer.color.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var defaultButtonBackground: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Capsule(style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.40),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Icon and title section
                    VStack(spacing: 16) {
                        ZStack {
                            // Outer glow
                            Circle()
                                .fill(prayer.color.opacity(0.15))
                                .frame(width: 100, height: 100)
                                .blur(radius: 30)
                            
                            // Middle layer with glass effect
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 85, height: 85)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.3),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                )
                                .shadow(color: prayer.color.opacity(0.3), radius: 20, y: 10)
                            
                            // Icon
                            Image(systemName: prayer.icon)
                                .font(.systemScaled(36, weight: .medium))
                                .foregroundStyle(prayer.color)
                                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                        }
                        .padding(.top, 30)
                        
                        VStack(spacing: 8) {
                            Text(prayer.title)
                                .font(AMENFont.bold(28))
                                .foregroundStyle(.white)
                            
                            Text(prayer.time)
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    
                    // Prayer content cards
                    VStack(spacing: 16) {
                        // Prayer text with liquid glass background
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(prayer.color.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "hands.sparkles.fill")
                                        .font(.systemScaled(14, weight: .semibold))
                                        .foregroundStyle(prayer.color)
                                }
                                
                                Text("Prayer")
                                    .font(AMENFont.bold(15))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            
                            Text(prayer.prayer)
                                .font(AMENFont.regular(17))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            ZStack {
                                // Glass morphism background
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.12),
                                                Color.white.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                // Border
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.25),
                                                Color.white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        )
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                        
                        // Scripture with liquid glass background
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(prayer.color.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    
                                    Image(systemName: "book.closed.fill")
                                        .font(.systemScaled(14, weight: .semibold))
                                        .foregroundStyle(prayer.color)
                                }
                                
                                Text("Scripture")
                                    .font(AMENFont.bold(15))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            
                            Text(prayer.scripture)
                                .font(AMENFont.regular(16))
                                .foregroundStyle(.white.opacity(0.8))
                                .italic()
                                .lineSpacing(7)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(22)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            ZStack {
                                // Glass morphism background
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.08),
                                                Color.white.opacity(0.03)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                // Border
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.2),
                                                Color.white.opacity(0.08)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        )
                        .shadow(color: .black.opacity(0.15), radius: 15, y: 8)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 120)
            }
            
            // Liquid Glass Complete Button - Fixed at bottom
            VStack(spacing: 0) {
                // Gradient fade
                LinearGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.black.opacity(0.85)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                
                // Button container
                VStack(spacing: 16) {
                    // "Focus Prayer" — starts a Live Activity in the Dynamic Island
                    if !isCompleted && LiveActivityManager.shared.isLiveActivitiesAvailable {
                        Button {
                            PrayerLiveActivityService.shared.startPersonalPrayerSession(title: prayer.title)
                            let h = UIImpactFeedbackGenerator(style: .light)
                            h.impactOccurred()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "hands.sparkles")
                                    .font(.systemScaled(13, weight: .medium))
                                Text("Focus Prayer")
                                    .font(AMENFont.semiBold(14))
                            }
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                ZStack {
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.10))
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // "Mark as Prayed" primary CTA
                    Button(action: {
                        onComplete()
                        // Also end any active prayer Live Activity with success state
                        if LiveActivityManager.shared.isLiveActivitiesAvailable {
                            LiveActivityManager.shared.markPrayerAsAnswered()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.systemScaled(16, weight: .bold))
                                .symbolEffect(.bounce, value: isCompleted)
                            Text(isCompleted ? "Prayed ✓" : "Mark as Prayed")
                                .font(AMENFont.bold(15))
                        }
                        .foregroundStyle(isCompleted ? prayer.color : .white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity)
                        .background(buttonBackground)
                        .shadow(
                            color: isCompleted ? prayer.color.opacity(0.35) : Color.white.opacity(0.15),
                            radius: isCompleted ? 16 : 10,
                            y: 6
                        )
                        .scaleEffect(isButtonPressed ? 0.96 : 1.0)
                    }
                    .disabled(isCompleted)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.1)) {
                                    isButtonPressed = true
                                }
                            }
                            .onEnded { _ in
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) {
                                    isButtonPressed = false
                                }
                            }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .background(Color.black.opacity(0.85))
            }
        }
    }
}

// MARK: - Daily Prayer Item Model

struct DailyPrayerItem {
    let title: String
    let time: String
    let icon: String
    let color: Color
    let prayer: String
    let scripture: String
}

// MARK: - Completion Celebration View

struct CompletionCelebrationView: View {
    @Binding var isShowing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Celebration icon
                ZStack {
                    Circle()
                        .fill(Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: 30)
                    
                    Circle()
                        .fill(Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.systemScaled(60))
                        .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
                        .symbolEffect(.bounce)
                }
                
                VStack(spacing: 8) {
                    Text("All Prayers Complete!")
                        .font(AMENFont.bold(26))
                        .foregroundStyle(.white)
                    
                    Text("You've spent time with God throughout your day. Well done, faithful servant!")
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                }
                
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        isShowing = false
                    }
                } label: {
                    Text("Continue")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 0.4, green: 0.85, blue: 0.7))
                        )
                }
                .padding(.horizontal, 40)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.pill) // P2-3: canonical token (24 = pill/sheet radius)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.pill) // P2-3: canonical token
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 30)
        }
    }
}

// MARK: - Prayer Groups View (OLD - Now in PrayerGroupsView.swift)

/*
struct PrayerGroupsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: GroupTab = .myGroups
    @State private var showCreateGroup = false
    @State private var selectedGroup: PrayerGroup?
    
    enum GroupTab: String, CaseIterable {
        case myGroups = "My Groups"
        case discover = "Discover"
        case invites = "Invites"
    }
    
    let sampleGroups: [PrayerGroup] = [
        PrayerGroup(
            name: "Young Adults Prayer Circle",
            icon: "person.3.fill",
            memberCount: 24,
            activeNow: 3,
            description: "Ages 18-30 praying together for careers, relationships, and purpose",
            color: Color(red: 0.4, green: 0.7, blue: 1.0),
            category: "Youth"
        ),
        PrayerGroup(
            name: "Parents in Faith",
            icon: "figure.2.and.child.holdinghands",
            memberCount: 47,
            activeNow: 8,
            description: "Lifting up our children and families in prayer",
            color: Color(red: 1.0, green: 0.6, blue: 0.7),
            category: "Family"
        ),
        PrayerGroup(
            name: "Healing & Restoration",
            icon: "heart.circle.fill",
            memberCount: 89,
            activeNow: 12,
            description: "Praying for physical, emotional, and spiritual healing",
            color: Color(red: 0.4, green: 0.85, blue: 0.7),
            category: "Health"
        ),
        PrayerGroup(
            name: "Missionaries United",
            icon: "globe.americas.fill",
            memberCount: 156,
            activeNow: 34,
            description: "Supporting global missionaries and unreached people groups",
            color: Color(red: 1.0, green: 0.7, blue: 0.4),
            category: "Missions"
        ),
        PrayerGroup(
            name: "Financial Breakthrough",
            icon: "chart.line.uptrend.xyaxis",
            memberCount: 63,
            activeNow: 7,
            description: "Trusting God for provision, debt freedom, and generosity",
            color: Color(red: 0.6, green: 0.5, blue: 1.0),
            category: "Finance"
        ),
        PrayerGroup(
            name: "Marriage Warriors",
            icon: "heart.text.square.fill",
            memberCount: 52,
            activeNow: 9,
            description: "Strengthening marriages through prayer and encouragement",
            color: Color(red: 1.0, green: 0.85, blue: 0.4),
            category: "Marriage"
        )
    ]
    
    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) {
                        dismiss()
                    }
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prayer Groups")
                            .font(AMENFont.bold(26))
                            .foregroundStyle(.white)
                        
                        Text("Pray together, grow together")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)
                
                // Tab selector
                HStack(spacing: 8) {
                    ForEach(GroupTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.white.opacity(0.15) : Color.clear)
                                        .overlay(
                                            Capsule()
                                                .stroke(selectedTab == tab ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(sampleGroups, id: \.name) { group in
                            PrayerGroupCard(group: group) {
                                selectedGroup = group
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100)
                }
                
                Spacer()
            }
            
            // Floating create button
            VStack {
                Spacer()
                
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        showCreateGroup = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.systemScaled(18, weight: .semibold))
                        
                        Text("Create Prayer Group")
                            .font(AMENFont.bold(16))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $selectedGroup) { group in
            PrayerGroupDetailView(group: group)
        }
        .sheet(isPresented: $showCreateGroup) {
            CreatePrayerGroupView()
        }
    }
}
*/

// MARK: - Prayer Group Model (OLD - Now in PrayerGroupsView.swift)

/*
struct PrayerGroup: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let memberCount: Int
    let activeNow: Int
    let description: String
    let color: Color
    let category: String
}
*/

// MARK: - Prayer Group Card (OLD - Now in PrayerGroupsView.swift)

/*
struct PrayerGroupCard: View {
    let group: PrayerGroup
    let onTap: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(group.color.opacity(0.15))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: group.icon)
                            .font(.systemScaled(24, weight: .medium))
                            .foregroundStyle(group.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        Text(group.category)
                            .font(AMENFont.semiBold(11))
                            .foregroundStyle(group.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(group.color.opacity(0.15))
                            )
                    }
                    
                    Spacer()
                }
                
                Text(group.description)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(4)
                    .lineLimit(2)
                
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text("\(group.memberCount) members")
                            .font(AMENFont.semiBold(12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    if group.activeNow > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.4, green: 0.85, blue: 0.7))
                                .frame(width: 6, height: 6)
                            
                            Text("\(group.activeNow) praying now")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}
*/

// MARK: - PrayerPostCard (Black & White Liquid Glass Design)

struct PrayerPostCard: View {
    let post: Post  // Use Post model from PostsManager
    
    enum PrayerCategory {
        case prayer
        case praise
        case answered
    }
    
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var interactionsService = PostInteractionsService.shared
    @ObservedObject private var savedPostsService = RealtimeSavedPostsService.shared
    @ObservedObject private var followService = FollowService.shared
    @State private var amenCount: Int
    @State private var commentCount: Int
    @State private var repostCount: Int
    @State private var hasAmened = false
    @State private var hasReposted = false
    @State private var hasSaved = false
    @State private var showComments = false
    @State private var showFullCommentSheet = false
    @State private var isAmenAnimating = false
    @State private var isFollowing = false
    @State private var showReportSheet = false
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var showUserProfile = false
    @State private var showShareSheet = false  // ✅ NEW: For native SwiftUI sharing
    // P1 #8: Debounce rapid amen taps — only the last tap within 300ms is committed
    @State private var amenDebounceTask: Task<Void, Never>?
    @State private var showEncouragementSheet = false
    @State private var encouragementSent = false
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Check if this is the user's own post
    private var isOwnPost: Bool {
        guard let currentUserId = FirebaseManager.shared.currentUser?.uid else {
            return false
        }
        return post.authorId == currentUserId
    }
    
    // Check if post can be edited (within 30 minutes)
    private func canEditPost() -> Bool {
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
        return post.createdAt >= thirtyMinutesAgo
    }
    
    init(post: Post) {
        self.post = post
        // Initialize with real counts from backend
        _amenCount = State(initialValue: post.amenCount)
        _commentCount = State(initialValue: post.commentCount)
        _repostCount = State(initialValue: post.repostCount)
    }
    
    // Computed properties for backward compatibility
    private var authorName: String { post.authorName }
    private var timeAgo: String { post.timeAgo }
    private var content: String { post.content }
    private var topicTag: String? { post.topicTag }
    private var category: PrayerCategory {
        guard let tag = post.topicTag else { return .prayer }
        switch tag {
        case "Prayer Request": return .prayer
        case "Praise Report": return .praise
        case "Answered Prayer": return .answered
        default: return .prayer
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            topicTagSection
            contentSection
            reactionButtonsSection
        }
        .padding(16)
        .background(cardBackground)
        .overlay(cardOverlay)
        .contextMenu {
            // Reply
            Button {
                showFullCommentSheet = true
            } label: {
                Label("Reply", systemImage: "arrow.turn.up.left")
            }

            // Copy
            Button {
                copyLink()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            // Pray for this
            Button {
                showEncouragementSheet = true
            } label: {
                Label("Pray for this", systemImage: "hands.sparkles")
            }

            Divider()

            // Own-post: Delete
            if isOwnPost {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Others' posts: Report
            if !isOwnPost {
                Button(role: .destructive) {
                    showReportSheet = true
                } label: {
                    Label("Report", systemImage: "flag")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditPostSheet(post: post)
        }
        .sheet(isPresented: $showFullCommentSheet) {
            CommentsView(post: post)
                .environmentObject(UserService())
        }
        .amenAlert(isPresented: $showingDeleteAlert, config: LiquidGlassAlertConfig(
            title: "Delete Prayer Post",
            message: "This prayer can't be recovered.",
            icon: "hands.and.sparkles",
            primaryButton: LiquidGlassAlertButton("Delete", tone: .destructive) {
                deletePost()
            },
            secondaryButton: .cancel()
        ))
        .sheet(isPresented: $showReportSheet) {
            ReportPostSheet(post: post, postAuthor: authorName, category: .prayer)
        }
        .sheet(isPresented: $showShareSheet) {
            // ✅ FIXED: Use native SwiftUI ActivityViewController wrapper
            ShareSheet(items: [shareText])
        }
        .sheet(isPresented: $showEncouragementSheet) {
            EncouragementSheet(post: post, onSent: {
                withAnimation(reduceMotion ? nil : .default) { encouragementSent = true }
            })
            .presentationDetents([.height(320)])
        }
        .sheet(isPresented: $showUserProfile) {
            if !post.authorId.isEmpty {
                UserProfileView(userId: post.authorId)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.systemScaled(60))
                        .foregroundStyle(.secondary)
                    
                    Text("Unable to Load Profile")
                        .font(AMENFont.bold(18))
                    
                    Text("This user's profile is not available.")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showUserProfile = false
                    } label: {
                        Text("Close")
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.white)
                            .frame(width: 120)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(Color.black)
                            )
                    }
                }
                .padding(40)
            }
        }
        .task {
            // Load follow state when view appears
            await loadFollowState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .followStateChanged)) { notification in
            // ✅ SMART SYNC: Update follow state when it changes elsewhere
            guard let userInfo = notification.userInfo,
                  let userId = userInfo["userId"] as? String,
                  userId == post.authorId else {
                return
            }
            
            if let newFollowState = userInfo["isFollowing"] as? Bool {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    isFollowing = newFollowState
                }
                dlog("🔄 Follow state synced for \(authorName): \(newFollowState)")
            }
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 12) {
            // Avatar with Follow Button - Black & White
            avatarWithFollowButton
                .buttonStyle(PlainButtonStyle())
            
            authorNameSection
            
            Spacer()
            
            // Category badge - Keep colored banners
            categoryBadge
            
            // Three-dots menu
            postMenu
        }
    }
    
    @ViewBuilder
    private var topicTagSection: some View {
        if let topicTag = topicTag {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.systemScaled(10, weight: .semibold))
                    .foregroundStyle(prayerTopicTagColor)
                
                Text(topicTag)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(prayerTopicTagColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(prayerTopicTagColor.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(prayerTopicTagColor.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TranslatableTextBlock(
                text: content,
                contentType: .prayerRequest,
                contentId: post.firebaseId ?? post.id.uuidString,
                surface: .feed,
                isPublicContent: true,
                font: .custom("OpenSans-Regular", size: 15),
                foregroundColor: .black.opacity(0.9)
            )

            // ✅ Display post images with fast cached loading
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                if imageURLs.count == 1 {
                    // Single image - full width
                    CachedAsyncImage(url: URL(string: imageURLs[0])) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 300)
                            .overlay(
                                ProgressView()
                                    .tint(.gray)
                            )
                    }
                } else if imageURLs.count == 2 {
                    // Two images side by side
                    HStack(spacing: 8) {
                        ForEach(imageURLs.indices, id: \.self) { index in
                            CachedAsyncImage(url: URL(string: imageURLs[index])) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 200)
                                    .overlay(
                                        ProgressView()
                                            .tint(.gray)
                                    )
                            }
                        }
                    }
                } else {
                    // 3+ images in grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(imageURLs.prefix(4).indices, id: \.self) { index in
                            CachedAsyncImage(url: URL(string: imageURLs[index])) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 150)
                                    .overlay(
                                        ProgressView()
                                            .tint(.gray)
                                    )
                            }
                            .overlay(
                                // Show "+X more" badge on last image if there are more than 4
                                Group {
                                    if index == 3 && imageURLs.count > 4 {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.black.opacity(0.6))
                                            .overlay(
                                                Text("+\(imageURLs.count - 4)")
                                                    .font(AMENFont.bold(24))
                                                    .foregroundStyle(.white)
                                            )
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var reactionButtonsSection: some View {
        HStack(spacing: 8) {
            // Amen Button (Clapping Hands) - Optimistic Update
            amenButton
            
            // Comment Button - Opens Full Comment Sheet (✅ No count displayed - just illuminates)
            PrayerReactionButton(
                icon: "bubble.left.fill",
                count: nil,  // ✅ Changed: Don't show count, just illuminate
                isActive: commentCount > 0  // Illuminate if there are comments
            ) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showFullCommentSheet = true
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                }
            }
            
            // Repost Button (✅ No count displayed - just illuminates)
            PrayerReactionButton(
                icon: "arrow.2.squarepath",
                count: nil,  // ✅ Changed: Don't show count, just illuminate
                isActive: hasReposted
            ) {
                Task {
                    await toggleRepost()
                }
            }
            
            Spacer()
            
            // Save Button (✅ Already correct - no count)
            PrayerReactionButton(
                icon: hasSaved ? "bookmark.fill" : "bookmark",
                count: nil,
                isActive: hasSaved
            ) {
                Task {
                    await toggleSave()
                }
            }
        }
        .padding(.top, 4)
        .task {
            // Load interaction states when view appears
            await loadInteractionStates()
            
            // Start real-time listener for interaction counts
            startRealtimeListener()
        }
        .onDisappear {
            // Stop listener when view disappears
            stopRealtimeListener()
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
            .fill(Color.white)
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }

    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
            .stroke(Color.black.opacity(0.1), lineWidth: 1)
    }

    @ViewBuilder
    private var avatarWithFollowButton: some View {
        Button {
            dlog("👤 Opening profile for user ID: \(post.authorId)")
            dlog("   Author name: \(authorName)")
            showUserProfile = true
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                // 🖼️ Show profile picture if available, otherwise show initials
                if let profileImageURL = post.authorProfileImageURL, !profileImageURL.isEmpty {
                    CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                    } placeholder: {
                        // Fallback to initials while loading
                        Circle()
                            .fill(Color.black)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String(authorName.prefix(1)))
                                    .font(AMENFont.bold(18))
                                    .foregroundStyle(.white)
                            )
                    }
                } else {
                    // No profile picture - show initials
                    Circle()
                        .fill(Color.black)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(authorName.prefix(1)))
                                .font(AMENFont.bold(18))
                                .foregroundStyle(.white)
                        )
                }
                
                // Follow button - Only show if not own post
                if !isOwnPost {
                    followButtonOverlay
                }
            }
        }
    }
    
    @ViewBuilder
    private var followButtonOverlay: some View {
        Image(systemName: isFollowing ? "checkmark.circle.fill" : "plus.circle.fill")
            .font(.systemScaled(18, weight: .semibold))
            .foregroundStyle(isFollowing ? .black : .white)
            .background(
                Circle()
                    .fill(isFollowing ? Color.white : Color.black)
                    .frame(width: 18, height: 18)
            )
            .overlay(
                Circle()
                    .stroke(Color.black.opacity(0.15), lineWidth: isFollowing ? 1 : 0)
            )
            .symbolEffect(.bounce, value: isFollowing)
            .offset(x: 2, y: 2)
            .onTapGesture {
                Task {
                    await toggleFollow()
                }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            }
    }
    
    @ViewBuilder
    private var authorNameSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(authorName)
                .font(AMENFont.bold(15))
                .foregroundStyle(.primary)
            
            Text(timeAgo)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var postMenu: some View {
        Menu {
            if isOwnPost {
                ownPostMenuOptions
            }
            
            commonMenuOptions
            
            if !isOwnPost {
                Divider()
                moderationMenuOptions
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.systemScaled(18, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(width: 32, height: 32)
        }
    }
    
    @ViewBuilder
    private var ownPostMenuOptions: some View {
        Group {
            if canEditPost() {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit Post", systemImage: "pencil")
                }
            }
            
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete Post", systemImage: "trash")
            }
            
            Divider()
        }
    }
    
    @ViewBuilder
    private var commonMenuOptions: some View {
        Group {
            Button {
                onRepost()
            } label: {
                Label(hasReposted ? "Remove Repost" : "Repost", systemImage: "arrow.2.squarepath")
            }
            
            Button {
                hasSaved.toggle()
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } label: {
                Label(hasSaved ? "Unsave" : "Save", systemImage: hasSaved ? "bookmark.fill" : "bookmark")
            }
            
            Button {
                showShareSheet = true  // ✅ FIXED: Use SwiftUI state instead of UIKit
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            
            Button {
                copyLink()
            } label: {
                Label("Copy Link", systemImage: "link")
            }
        }
    }
    
    @ViewBuilder
    private var moderationMenuOptions: some View {
        Group {
            Button(role: .destructive) {
                showReportSheet = true
            } label: {
                Label("Report Post", systemImage: "exclamationmark.triangle")
            }
        
            Button(role: .destructive) {
                muteAuthor()
            } label: {
                Label("Mute \(authorName)", systemImage: "speaker.slash")
            }
            
            Button(role: .destructive) {
                blockAuthor()
            } label: {
                Label("Block \(authorName)", systemImage: "hand.raised")
            }
        }
    }
    
    // MARK: - Amen Button
    
    @ViewBuilder
    private var amenButton: some View {
        Button {
            handleAmenTap()
        } label: {
            amenButtonLabel
        }
    }
    
    @ViewBuilder
    private var amenButtonLabel: some View {
        let iconName = hasAmened ? "hands.clap.fill" : "hands.clap"
        let foregroundColor = hasAmened ? Color.black : Color.black.opacity(0.5)
        let backgroundColor = hasAmened ? Color.white : Color.black.opacity(0.05)
        let shadowColor = hasAmened ? Color.black.opacity(0.15) : Color.clear
        let strokeColor = hasAmened ? Color.black.opacity(0.2) : Color.black.opacity(0.1)
        let strokeWidth: CGFloat = hasAmened ? 1.5 : 1
        
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .scaleEffect(isAmenAnimating ? 1.2 : 1.0)
                .rotationEffect(.degrees(isAmenAnimating ? 12 : 0))
            
            // ✅ Removed count display - button just illuminates when active
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(amenButtonBackground(backgroundColor: backgroundColor, shadowColor: shadowColor))
        .overlay(amenButtonOverlay(strokeColor: strokeColor, strokeWidth: strokeWidth))
    }
    
    private func amenButtonBackground(backgroundColor: Color, shadowColor: Color) -> some View {
        Capsule()
            .fill(backgroundColor)
            .shadow(color: shadowColor, radius: 8, y: 2)
    }
    
    private func amenButtonOverlay(strokeColor: Color, strokeWidth: CGFloat) -> some View {
        Capsule()
            .stroke(strokeColor, lineWidth: strokeWidth)
    }
    
    private func handleAmenTap() {
        // P1 #8: OPTIMISTIC UPDATE — toggle UI immediately so feedback is instant
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
            hasAmened.toggle()
            amenCount = hasAmened ? amenCount + 1 : amenCount - 1
            isAmenAnimating = true
        }

        let haptic = UIImpactFeedbackGenerator(style: hasAmened ? .medium : .light)
        haptic.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isAmenAnimating = false
        }

        // P1 #8: Debounce — cancel any in-flight commit and wait 300 ms.
        // Only the final tap state within the window is written to the backend,
        // preventing inflated/negative counts from rapid double-taps.
        amenDebounceTask?.cancel()

        // Capture state before launching the task
        let postId = post.backendId
        let capturedInteractionsService = interactionsService

        amenDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                // Task was cancelled by another tap — don't commit this state
                return
            }
            guard !Task.isCancelled else { return }

            // Commit the current UI state to the backend
            let capturedHasAmened = hasAmened
            let capturedIsOwnPost = isOwnPost
            let capturedTopicTag = post.topicTag
            Task.detached(priority: .userInitiated) { [capturedInteractionsService] in
                do {
                    try await capturedInteractionsService.toggleAmen(postId: postId)
                    // Mirror PrayerFollowThroughBar: commit to pray + show encouragement
                    if capturedHasAmened && !capturedIsOwnPost && capturedTopicTag == "Prayer Request" {
                        try? await PrayerFollowThroughService.shared.commitToPray(prayerId: postId)
                        await MainActor.run {
                            withAnimation(reduceMotion ? nil : .default) { showEncouragementSheet = true }
                        }
                    }
                } catch {
                    // On error, revert the optimistic update
                    await MainActor.run {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                            hasAmened.toggle()
                            amenCount = hasAmened ? amenCount + 1 : amenCount - 1
                        }
                        dlog("❌ Failed to sync Amen: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Computed property for share text
    private var shareText: String {
        """
        🙏 Prayer Request from \(authorName)
        
        \(content)
        
        Join us in prayer on AMEN APP!
        """
    }
    
    private func deletePost() {
        postsManager.deletePost(postId: post.id)
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        
        dlog("🗑️ Prayer post deleted")
    }
    
    // MARK: - Follow Functions
    
    /// Load follow state from backend
    private func loadFollowState() async {
        guard !isOwnPost else { return }
        isFollowing = await followService.isFollowing(userId: post.authorId)
    }
    
    /// Toggle follow/unfollow
    private func toggleFollow() async {
        guard !isOwnPost else { return }
        
        // OPTIMISTIC UPDATE
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            isFollowing.toggle()
        }
        
        // ✅ BROADCAST: Notify all UIs about the follow state change
        NotificationCenter.default.post(
            name: .followStateChanged,
            object: nil,
            userInfo: [
                "userId": post.authorId,
                "isFollowing": isFollowing
            ]
        )
        
        // Background sync to Firebase
        let targetUserId = post.authorId
        let currentFollowState = isFollowing
        
        Task.detached(priority: .userInitiated) {
            do {
                let followService = await FollowService.shared
                if currentFollowState {
                    try await followService.followUser(userId: targetUserId)
                    dlog("✅ Followed user: \(targetUserId)")
                } else {
                    try await followService.unfollowUser(userId: targetUserId)
                    dlog("✅ Unfollowed user: \(targetUserId)")
                }
            } catch {
                dlog("❌ Failed to toggle follow: \(error)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        isFollowing = !currentFollowState
                    }
                    
                    // ✅ BROADCAST: Notify about the rollback
                    NotificationCenter.default.post(
                        name: .followStateChanged,
                        object: nil,
                        userInfo: [
                            "userId": targetUserId,
                            "isFollowing": !currentFollowState
                        ]
                    )
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    // MARK: - Interaction Functions
    
    /// Start real-time listener for interaction counts
    private func startRealtimeListener() {
        let postId = post.id.uuidString
        let ref = Database.database().reference()
        
        // Get current user ID for state checks
        guard let userId = Auth.auth().currentUser?.uid else {
            dlog("⚠️ Cannot start real-time listener: No authenticated user")
            return
        }
        
        // Listen to interaction counts in real-time
        ref.child("postInteractions").child(postId).observe(.value) { snapshot in
            guard let data = snapshot.value as? [String: Any] else { return }
            
            Task { @MainActor in
                // ✅ FIX: Update counts AND button states
                if let amenData = data["amens"] as? [String: Any] {
                    self.amenCount = amenData.count
                    // ✅ Check if current user has amened (fixes persistence bug)
                    self.hasAmened = amenData[userId] != nil
                }
                
                if let comments = data["comments"] as? [String: Any] {
                    self.commentCount = comments.count
                }
                
                if let reposts = data["reposts"] as? [String: Any] {
                    self.repostCount = reposts.count
                    // ✅ Check if current user has reposted (fixes persistence bug)
                    self.hasReposted = reposts[userId] != nil
                }
            }
        }
    }
    
    /// Stop real-time listener
    private func stopRealtimeListener() {
        let postId = post.id.uuidString
        let ref = Database.database().reference()
        ref.child("postInteractions").child(postId).removeAllObservers()
    }
    
    /// Load interaction states from backend
    private func loadInteractionStates() async {
        let postId = post.id.uuidString
        
        // Check if user has amened
        hasAmened = await interactionsService.hasAmened(postId: postId)
        
        // Check if user has saved
        hasSaved = (try? await savedPostsService.isPostSaved(postId: postId)) ?? false
        
        // Check if user has reposted
        hasReposted = await interactionsService.hasReposted(postId: postId)
        
        // Update counts from backend
        let counts = await interactionsService.getInteractionCounts(postId: postId)
        amenCount = counts.amenCount
        commentCount = counts.commentCount
        repostCount = counts.repostCount
    }
    
    // MARK: - Production-Ready Repost Functions
    
    /// Production-ready repost toggle with:
    /// ✅ Optimistic UI updates for instant feedback
    /// ✅ Automatic error rollback on failures
    /// ✅ User-friendly error messages
    /// ✅ Duplicate prevention (backend check)
    /// ✅ Real-time count updates
    /// ✅ Proper haptic feedback (success + error)
    /// ✅ Detailed console logging for debugging
    private func toggleRepost() async {
        // Store previous state for rollback
        let previousRepostState = hasReposted
        let previousRepostCount = repostCount
        
        // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
        await MainActor.run {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                hasReposted.toggle()
                repostCount += hasReposted ? 1 : -1
            }
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            dlog("🔄 Prayer \(hasReposted ? "reposted" : "unreposted") (optimistic)")
        }
        
        // Capture post ID before detaching
        let postId = post.id.uuidString
        
        // Background sync to Firebase using RepostService
        Task.detached(priority: .userInitiated) {
            do {
                let repostService = await RepostService.shared
                try await repostService.toggleRepost(postId: postId)
                
                await MainActor.run {
                    dlog("✅ Repost synced successfully to Firebase")
                }
            } catch {
                dlog("❌ Failed to toggle repost: \(error.localizedDescription)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        hasReposted = previousRepostState
                        repostCount = previousRepostCount
                    }
                    
                    // Error haptic feedback
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                    
                    // Show user-friendly error message
                    showRepostError(error)
                }
            }
        }
    }
    
    /// Display user-friendly repost error
    private func showRepostError(_ error: Error) {
        let errorMessage: String
        
        if error.localizedDescription.contains("already reposted") {
            errorMessage = "You've already reposted this prayer"
        } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("offline") {
            errorMessage = "Network error. Please check your connection and try again."
        } else {
            errorMessage = "Unable to repost. Please try again."
        }
        
        dlog("⚠️ Showing repost error to user: \(errorMessage)")
        ToastManager.shared.show(ToastNotification(message: errorMessage, style: .error))
    }
    
    // MARK: - Production-Ready Save Functions
    
    /// Production-ready save/bookmark toggle with:
    /// ✅ Optimistic UI updates for instant feedback
    /// ✅ Automatic error rollback on failures
    /// ✅ User-friendly error messages
    /// ✅ State persistence in Firebase
    /// ✅ Proper haptic feedback (medium for save, light for unsave)
    /// ✅ Detailed console logging for debugging
    private func toggleSave() async {
        // Store previous state for rollback
        let previousSavedState = hasSaved
        
        // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
        await MainActor.run {
            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                hasSaved.toggle()
            }
            
            // Haptic feedback
            let haptic = UIImpactFeedbackGenerator(style: hasSaved ? .medium : .light)
            haptic.impactOccurred()
            
            dlog("🔖 Prayer \(hasSaved ? "saved" : "unsaved") (optimistic)")
        }
        
        // Capture the current state and post ID before detaching
        let currentSavedState = hasSaved
        let postId = post.id.uuidString
        
        // Background sync to Firebase
        Task.detached(priority: .userInitiated) { [savedPostsService] in
            do {
                _ = try await savedPostsService.toggleSavePost(postId: postId)
                dlog("✅ Post \(currentSavedState ? "saved" : "unsaved") in Firebase")
            } catch {
                dlog("❌ Failed to toggle save: \(error.localizedDescription)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                        hasSaved = previousSavedState
                    }
                    
                    // Error haptic feedback
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                    
                    // Show user-friendly error
                    showSaveError(error)
                }
            }
        }
    }
    
    /// Display user-friendly save error
    private func showSaveError(_ error: Error) {
        let errorMessage: String
        
        if error.localizedDescription.contains("network") || error.localizedDescription.contains("offline") {
            errorMessage = "Network error. Please check your connection and try again."
        } else {
            errorMessage = "Unable to save post. Please try again."
        }
        
        dlog("⚠️ Showing save error to user: \(errorMessage)")
        ToastManager.shared.show(ToastNotification(message: errorMessage, style: .error))
    }
    
    private func onRepost() {
        Task {
            await toggleRepost()
        }
    }
    
    private func copyLink() {
        let postId = post.firebaseId ?? post.id.uuidString
        UIPasteboard.general.string = "https://amenapp.com/prayer/\(postId)"
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        ToastManager.shared.show(ToastNotification(message: "Prayer link copied", style: .success))
        dlog("🔗 Prayer link copied: \(postId)")
    }
    
    private func muteAuthor() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        dlog("🔇 Muting \(authorName)…")
        Task {
            do {
                try await ModerationService.shared.muteUser(userId: post.authorId)
                dlog("✅ Muted \(authorName)")
                ToastManager.shared.show(ToastNotification(message: "\(authorName) muted", style: .success))
            } catch {
                dlog("❌ Failed to mute \(authorName): \(error)")
                ToastManager.shared.show(ToastNotification(message: "Unable to mute user. Please try again.", style: .error))
            }
        }
    }

    private func blockAuthor() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        dlog("🚫 Blocking \(authorName)…")
        Task {
            do {
                try await BlockService.shared.blockUser(userId: post.authorId)
                dlog("✅ Blocked \(authorName)")
                ToastManager.shared.show(ToastNotification(message: "\(authorName) blocked", style: .success))
            } catch {
                dlog("❌ Failed to block \(authorName): \(error)")
                ToastManager.shared.show(ToastNotification(message: "Unable to block user. Please try again.", style: .error))
            }
        }
    }
    
    @ViewBuilder
    private var categoryBadge: some View {
        let config = categoryConfig
        
        HStack(spacing: 4) {
            Image(systemName: config.icon)
                .font(.systemScaled(10, weight: .semibold))
            
            Text(config.label)
                .font(AMENFont.bold(10))
        }
        .foregroundStyle(config.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: config.color.opacity(0.3), radius: 8, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(config.color, lineWidth: 1.5)
        )
    }
    
    private var categoryConfig: (icon: String, label: String, color: Color) {
        switch category {
        case .prayer:
            return ("hands.sparkles.fill", "PRAYER", Color(red: 0.4, green: 0.7, blue: 1.0))
        case .praise:
            return ("hands.clap.fill", "PRAISE", Color(red: 1.0, green: 0.7, blue: 0.4))
        case .answered:
            return ("checkmark.seal.fill", "ANSWERED", Color(red: 0.4, green: 0.85, blue: 0.7))
        }
    }
    
    // MARK: - Topic Tag Color
    
    private var prayerTopicTagColor: Color {
        switch category {
        case .prayer:
            return Color(red: 0.4, green: 0.6, blue: 1.0) // Soft blue for prayer
        case .praise:
            return Color(red: 1.0, green: 0.7, blue: 0.0) // Golden yellow for praise
        case .answered:
            return Color(red: 0.4, green: 0.85, blue: 0.7) // Soft teal for answered
        }
    }
}

// MARK: - Prayer Reaction Button

struct PrayerReactionButton: View {
    let icon: String
    let count: Int?
    let isActive: Bool
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.systemScaled(12, weight: .semibold))
                    .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                
                if let count = count {
                    Text("\(count)")
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Color.white : Color.black.opacity(0.05))
                    .shadow(color: isActive ? .black.opacity(0.15) : .clear, radius: 8, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: isActive ? 1.5 : 1)
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(reduceMotion ? nil : .easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Prayer Comment Section (Production-Ready & Interactive)

/// Production-ready comment section for Prayer posts with:
/// ✅ Optimistic UI updates for instant feedback
/// ✅ Automatic error rollback on failures
/// ✅ Real-time comment loading from Firebase
/// ✅ Loading states and error messages
/// ✅ Username fetching from Firestore
/// ✅ Comment deletion with confirmation
/// ✅ Quick prayer responses for easy interaction
/// ✅ Proper keyboard management
/// ✅ Submit state tracking to prevent double-posting
struct PrayerCommentSection: View {
    let prayerAuthor: String
    let prayerCategory: PrayerPostCard.PrayerCategory
    let post: Post  // Post parameter to get postId
    @Binding var commentCount: Int  // Bind to parent's count for real-time updates

    @State private var commentText = ""
    @State private var showQuickPrayers = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showVerseSelector = false
    @State private var isLoading = true
    @State private var isSubmitting = false  // NEW: Track submit state
    @FocusState private var isCommentFocused: Bool
    @ObservedObject private var commentService = CommentService.shared
    
    // Real comments from Firebase
    @State private var comments: [Comment] = []
    
    // Error handling
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            commentsHeader
            errorAlertView
            contentView
            inputSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .task {
            await loadComments()
        }
        .onAppear {
            commentService.startListening(to: post.id.uuidString)
        }
        // ✅ Verse picker: attaches selected verse text to the comment input
        .sheet(isPresented: $showVerseSelector) {
            VerseDrawerCoordinator(isPresented: $showVerseSelector) { verse in
                let verseText = "\"\(verse.text)\" — \(verse.reference)"
                commentText = commentText.isEmpty ? verseText : commentText + "\n" + verseText
                showVerseSelector = false
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(24)
        }
        // ✅ REMOVED: .onDisappear that stopped comment listeners
        // This allows comments to stay in real-time even when user navigates away
        // Minimal battery impact due to efficient Firebase WebSocket connections
        // .onDisappear {
        //     commentService.stopListening()
        // }
    }

    // MARK: - View Components
    
    private var commentsHeader: some View {
        HStack {
            Text("Prayer Responses")
                .font(AMENFont.bold(13))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("\(comments.count)")
                .font(AMENFont.bold(12))
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var errorAlertView: some View {
        if showError, let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.systemScaled(14))
                    .foregroundStyle(.orange)
                
                Text(error)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    withAnimation(reduceMotion ? nil : .default) {
                        showError = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(16))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            loadingView
        } else if comments.isEmpty {
            emptyStateView
        } else {
            commentsListView
        }
    }
    
    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Spacer()
        }
        .padding(.vertical, 20)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("Be the first to pray")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.secondary)
            Text("Share your prayer or encouragement")
                .font(AMENFont.regular(12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var commentsListView: some View {
        VStack(spacing: 12) {
            ForEach(comments) { comment in
                PrayerCommentRow(
                    comment: comment,
                    postCategory: prayerCategory,
                    onDelete: {
                        deleteComment(comment)
                    }
                )
            }
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 12) {
            quickPrayersRow
            commentInputRow
        }
    }
    
    @ViewBuilder
    private var quickPrayersRow: some View {
        if showQuickPrayers {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickPrayerChip(text: "🙏 Praying for you") {
                        addQuickComment("🙏 Praying for you")
                    }
                    QuickPrayerChip(text: "🙌 Amen!") {
                        addQuickComment("🙌 Amen!")
                    }
                    QuickPrayerChip(text: "💪 Standing with you") {
                        addQuickComment("💪 Standing with you")
                    }
                    QuickPrayerChip(text: "✨ God is faithful") {
                        addQuickComment("✨ God is faithful")
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .scale.combined(with: .opacity)
            ))
        }
    }
    
    private var commentInputRow: some View {
        HStack(spacing: 10) {
            commentInputField
            sendButton
        }
    }
    
    private var commentInputField: some View {
        HStack(spacing: 8) {
            TextField("Share encouragement...", text: $commentText, axis: .vertical)
                .font(AMENFont.regular(14))
                .foregroundStyle(.primary)
                .lineLimit(1...4)
                .focused($isCommentFocused)
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 10)
            
            quickActionsButtons
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isCommentFocused ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var quickActionsButtons: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    showQuickPrayers.toggle()
                }
            } label: {
                Image(systemName: showQuickPrayers ? "hand.raised.fill" : "hand.raised")
                    .font(.systemScaled(16))
                    .foregroundStyle(showQuickPrayers ? .black : .black.opacity(0.4))
            }
            
            Button {
                showVerseSelector = true
            } label: {
                Image(systemName: "book.closed")
                    .font(.systemScaled(16))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.trailing, 8)
    }
    
    @ViewBuilder
    private var sendButton: some View {
        if !commentText.isEmpty {
            Button {
                Task {
                    await postComment()
                }
            } label: {
                ZStack {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.systemScaled(32))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .disabled(isSubmitting)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    // MARK: - Post Comment (Production-Ready with Error Handling)
    
    private func postComment() async {
        guard !commentText.isEmpty else { return }
        guard !isSubmitting else { return }  // Prevent double-submission
        
        // Set submitting state
        await MainActor.run {
            isSubmitting = true
            showError = false
        }
        
        let tempCommentText = commentText
        
        // ✅ FIXED: Don't create optimistic comment - let real-time listener handle it
        // Clear UI immediately for instant feedback
        await MainActor.run {
            commentText = ""
            isCommentFocused = false  // Dismiss keyboard
            
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        }
        
        // Post to Firebase - real-time listener will add to UI
        do {
            _ = try await commentService.addComment(
                postId: post.id.uuidString,
                content: tempCommentText
            )
            
            await MainActor.run {
                isSubmitting = false
                dlog("✅ Comment posted successfully - will appear via listener")
            }
        } catch {
            dlog("❌ Failed to post comment: \(error)")
            
            // On error, restore comment text and show error
            await MainActor.run {
                commentText = tempCommentText  // Restore comment text
                isSubmitting = false
                
                // Show user-friendly error
                errorMessage = "Failed to post comment. Please try again."
                withAnimation(reduceMotion ? nil : .default) {
                    showError = true
                }

                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }
    }
    
    // MARK: - Load Comments (Production-Ready with Error Handling)
    
    private func loadComments() async {
        await MainActor.run {
            isLoading = true
            showError = false
        }
        
        do {
            let fetchedComments = try await commentService.fetchComments(for: post.id.uuidString)
            
            await MainActor.run {
                // Only show top-level comments (not replies), sort by newest first
                self.comments = fetchedComments
                    .filter { $0.parentCommentId == nil }
                    .sorted { $0.createdAt > $1.createdAt }
                self.commentCount = comments.count
                isLoading = false
                dlog("✅ Loaded \(comments.count) comments for post: \(post.id.uuidString)")
            }
        } catch {
            dlog("❌ Failed to load comments: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to load comments"
                showError = true
            }
        }
    }
    
    // MARK: - Helper: Fetch Username
    
    private func fetchCurrentUsername() async throws -> String? {
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            throw NSError(domain: "PrayerView", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        lazy var db = Firestore.firestore()
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        if let username = userDoc.data()?["username"] as? String {
            return username
        }
        
        return nil
    }
    
    // MARK: - Delete Comment (Production-Ready with Rollback)
    
    private func deleteComment(_ comment: Comment) {
        guard let commentId = comment.id else {
            dlog("⚠️ Cannot delete comment: Missing comment ID")
            return
        }
        
        // Store comment for potential rollback
        let deletedComment = comment
        let deletedIndex = comments.firstIndex(where: { $0.id == commentId }) ?? 0
        
        // OPTIMISTIC UPDATE: Remove from UI immediately
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            comments.removeAll { $0.id == commentId }
            commentCount = comments.count
        }
        
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // Capture postId before detaching
        let postId = post.id.uuidString
        
        // Background sync to Firebase
        Task.detached(priority: .userInitiated) {
            do {
                try await commentService.deleteComment(commentId: commentId, postId: postId)
                dlog("✅ Comment deleted successfully: \(commentId)")
            } catch {
                dlog("❌ Failed to delete comment: \(error.localizedDescription)")
                
                // On error, restore the comment at its original position
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        // Insert back at original index (or append if index out of bounds)
                        if deletedIndex < comments.count {
                            comments.insert(deletedComment, at: deletedIndex)
                        } else {
                            comments.append(deletedComment)
                        }
                        commentCount = comments.count
                        
                        errorMessage = "Failed to delete comment"
                        showError = true
                    }
                    
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        }
    }
    
    // MARK: - Quick Comment Helper
    
    private func addQuickComment(_ text: String) {
        commentText = text
        isCommentFocused = true
    }
}

// MARK: - Prayer Comment Row (Production-Ready)

/// Production-ready comment display row with:
/// ✅ Amen/prayer reaction with optimistic updates
/// ✅ Automatic state loading from Firebase
/// ✅ Error handling with rollback on failures
/// ✅ Delete functionality (owner-only)
/// ✅ Profile image support with fallback
/// ✅ Proper haptic feedback
/// ✅ Reply button (ready for future implementation)
struct PrayerCommentRow: View {
    let comment: Comment  // Use real Comment model
    let postCategory: PrayerPostCard.PrayerCategory
    let onDelete: () -> Void

    @State private var hasPrayed = false
    @State private var localPrayCount: Int
    @State private var showDeleteAlert = false
    @State private var showReplyField = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replyText = ""
    @State private var isSubmittingReply = false
    @FocusState private var replyFieldFocused: Bool
    @ObservedObject private var commentService = CommentService.shared
    @StateObject private var userService = UserService()
    
    init(comment: Comment, postCategory: PrayerPostCard.PrayerCategory, onDelete: @escaping () -> Void) {
        self.comment = comment
        self.postCategory = postCategory
        self.onDelete = onDelete
        _localPrayCount = State(initialValue: comment.amenCount)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar - ✅ FIXED: Using cached async image for faster loading
            if let profileImageURL = comment.authorProfileImageURL, !profileImageURL.isEmpty {
                CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                } placeholder: {
                    Circle()
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(comment.authorInitials)
                                .font(AMENFont.bold(12))
                                .foregroundStyle(.secondary)
                        )
                }
            } else {
                Circle()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(comment.authorInitials)
                            .font(AMENFont.bold(12))
                            .foregroundStyle(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.authorName)
                            .font(AMENFont.bold(13))
                            .foregroundStyle(.primary)
                        
                        Text(comment.authorUsername)
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("•")
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.tertiary)
                    
                    Text(comment.createdAt.timeAgoDisplay())
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Delete button (only show if user owns the comment)
                    if isOwnComment {
                        Menu {
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
                // Content
                Text(comment.content)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                
                // Actions (Production-Ready with Error Handling)
                HStack(spacing: 14) {
                    // Pray button (Amen reaction) - Production-Ready Optimistic Update
                    Button {
                        handleAmenToggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                                .font(.systemScaled(11, weight: .semibold))
                            
                            if localPrayCount > 0 {
                                Text("\(localPrayCount)")
                                    .font(AMENFont.semiBold(11))
                                    .contentTransition(.numericText())
                            }
                        }
                        .foregroundStyle(hasPrayed ? .black : .black.opacity(0.5))
                    }
                    .symbolEffect(.bounce, value: hasPrayed)
                    
                    // Reply button
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            showReplyField.toggle()
                        }
                        if showReplyField {
                            replyFieldFocused = true
                        }
                    } label: {
                        Text(showReplyField ? "Cancel" : "Reply")
                            .font(AMENFont.semiBold(11))
                            .foregroundStyle(showReplyField ? .blue.opacity(0.8) : .black.opacity(0.5))
                    }
                }
                .padding(.top, 2)

                // Inline reply field
                if showReplyField {
                    HStack(spacing: 8) {
                        TextField("Reply...", text: $replyText, axis: .vertical)
                            .font(AMENFont.regular(13))
                            .lineLimit(1...4)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .focused($replyFieldFocused)

                        Button {
                            submitReply()
                        } label: {
                            if isSubmittingReply {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.systemScaled(24))
                                    .foregroundStyle(replyText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                            }
                        }
                        .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmittingReply)
                    }
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .amenAlert(isPresented: $showDeleteAlert, config: LiquidGlassAlertConfig(
            title: "Delete Comment",
            icon: "bubble.slash",
            primaryButton: LiquidGlassAlertButton("Delete", tone: .destructive) {
                onDelete()
            },
            secondaryButton: .cancel()
        ))
        .task {
            // Load initial prayer state when view appears
            await loadInitialState()
        }
    }
    
    // MARK: - Production-Ready Methods
    
    /// Check if current user owns this comment
    private var isOwnComment: Bool {
        guard let currentUserId = userService.currentUser?.id else { return false }
        return comment.authorId == currentUserId
    }
    
    /// Load initial amen state from backend
    private func loadInitialState() async {
        guard let commentId = comment.id else {
            dlog("⚠️ Cannot load state: Missing comment ID")
            return
        }
        
        hasPrayed = await commentService.hasUserAmened(commentId: commentId, postId: comment.postId)
    }
    
    /// Handle amen toggle with optimistic update and error rollback
    private func handleAmenToggle() {
        guard let commentId = comment.id else {
            dlog("⚠️ Cannot toggle amen: Missing comment ID")
            return
        }
        
        // Store previous state for potential rollback
        let previousState = hasPrayed
        let previousCount = localPrayCount
        
        // OPTIMISTIC UPDATE: Update UI immediately
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
            hasPrayed.toggle()
            localPrayCount += hasPrayed ? 1 : -1
        }
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Capture postId before detaching
        let postId = comment.postId
        
        // Background sync to Firebase
        Task.detached(priority: .userInitiated) {
            do {
                try await commentService.toggleAmen(commentId: commentId, postId: postId, currentlyAmened: previousState)
                dlog("✅ Amen toggled successfully")
            } catch {
                dlog("❌ Failed to toggle amen: \(error.localizedDescription)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                        hasPrayed = previousState
                        localPrayCount = previousCount
                    }
                    
                    // Error haptic feedback
                    let errorHaptic = UINotificationFeedbackGenerator()
                    errorHaptic.notificationOccurred(.error)
                }
            }
        }
    }

    /// Submit an inline reply to this comment
    private func submitReply() {
        let trimmed = replyText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let commentId = comment.id else { return }
        isSubmittingReply = true

        Task {
            do {
                // Post reply as a child comment using CommentService
                _ = try await commentService.addReply(
                    postId: comment.postId,
                    parentCommentId: commentId,
                    content: trimmed
                )
                await MainActor.run {
                    replyText = ""
                    isSubmittingReply = false
                    withAnimation(reduceMotion ? nil : .default) { showReplyField = false }
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isSubmittingReply = false
                    // Show toast if available, otherwise keep field open
                    ToastManager.shared.show(ToastNotification(
                        message: "Failed to post reply. Please try again.",
                        style: .error
                    ))
                }
            }
        }
    }
}

// MARK: - Quick Prayer Chip

struct QuickPrayerChip: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(AMENFont.semiBold(12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - Prayer Wall View

struct PrayerWallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: PrayerWallFilter = .all
    @State private var searchText = ""
    @State private var prayerWallPosts: [PrayerWallPost] = []
    @State private var isLoading = false

    enum PrayerWallFilter: String, CaseIterable {
        case all = "All Prayers"
        case urgent = "Urgent"
        case answered = "Answered"
        case today = "Today"
    }

    private var filteredPosts: [PrayerWallPost] {
        let base: [PrayerWallPost]
        switch selectedFilter {
        case .all:      base = prayerWallPosts
        case .urgent:   base = prayerWallPosts.filter { $0.isUrgent }
        case .answered: base = prayerWallPosts.filter { $0.category == .answered }
        case .today:    base = prayerWallPosts.filter { Calendar.current.isDateInToday($0.createdAt) }
        }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter { $0.title.lowercased().contains(q) || $0.excerpt.lowercased().contains(q) }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Text("Prayer Wall")
                        .font(AMENFont.bold(28))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
                
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                    
                    TextField("Search prayers...", text: $searchText)
                        .font(AMENFont.regular(15))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.05))
                )
                .padding(.horizontal)
                
                // Filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(PrayerWallFilter.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                    selectedFilter = filter
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                Text(filter.rawValue)
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(selectedFilter == filter ? .white : .black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedFilter == filter ? Color.black : Color.black.opacity(0.08))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                
                // Prayer wall grid
                if isLoading && prayerWallPosts.isEmpty {
                    Spacer()
                    ProgressView().scaleEffect(0.9)
                    Spacer()
                } else if filteredPosts.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        AmenGlass3DIcon(systemName: "hands.sparkles", tint: AmenTheme.Colors.amenGold, size: 64)
                        Text(searchText.isEmpty ? "No prayers yet" : "No results for \"\(searchText)\"")
                            .font(AMENFont.semiBold(16))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(filteredPosts, id: \.id) { post in
                                PrayerWallCard(post: post)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationBarHidden(true)
            .task { await loadPrayerWall() }
        }
    }

    // MARK: - Firestore Loader

    private func loadPrayerWall() async {
        guard !isLoading else { return }
        isLoading = true
        do {
            let db = Firestore.firestore()
            // P1-1: query prayerWall collection directly instead of posts filtered by category
            let snap = try await db.collection("prayerWall")
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            let posts: [PrayerWallPost] = snap.documents.compactMap { doc in
                let data = doc.data()
                // prayerWall documents use "text" or "content" for the prayer body
                guard let content = (data["text"] as? String) ?? (data["content"] as? String),
                      let authorName = (data["authorName"] as? String) ?? (data["authorId"] as? String) else { return nil }
                let topicTag = data["topicTag"] as? String ?? "Prayer Request"
                let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                let status = data["status"] as? String ?? ""
                let category: PrayerPostCard.PrayerCategory = (topicTag == "Answered Prayer" || status == "answered") ? .answered
                    : topicTag == "Praise Report" ? .praise : .prayer
                return PrayerWallPost(
                    id: doc.documentID,
                    title: "\(authorName)'s Prayer",
                    author: authorName,
                    timeAgo: createdAt.timeAgoDisplay(),
                    createdAt: createdAt,
                    category: category,
                    prayCount: data["amenCount"] as? Int ?? 0,
                    isUrgent: data["isUrgent"] as? Bool ?? false,
                    excerpt: String(content.prefix(120))
                )
            }
            await MainActor.run {
                prayerWallPosts = posts
                isLoading = false
                dlog("✅ PrayerWall loaded \(posts.count) posts from Firestore")
            }
        } catch {
            await MainActor.run {
                isLoading = false
                dlog("❌ PrayerWall load failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Prayer Wall Card

struct PrayerWallCard: View {
    let post: PrayerWallPost
    @State private var hasPrayed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category and Urgent badges row
            HStack(spacing: 6) {
                // Category badge with color
                categoryBadge
                
                // Urgent badge
                if post.isUrgent {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.systemScaled(9))
                        Text("URGENT")
                            .font(AMENFont.bold(9))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.3), radius: 4, y: 2)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(red: 1.0, green: 0.3, blue: 0.3), lineWidth: 1.5)
                    )
                }
            }
            
            // Title
            Text(post.title)
                .font(AMENFont.bold(14))
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            // Excerpt
            Text(post.excerpt)
                .font(AMENFont.regular(12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            
            Spacer()
            
            // Footer
            VStack(spacing: 8) {
                Divider()
                
                HStack {
                    // Author
                    Text(post.author)
                        .font(AMENFont.semiBold(11))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Pray count
                    HStack(spacing: 3) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.systemScaled(10))
                        Text("\(post.prayCount + (hasPrayed ? 1 : 0))")
                            .font(AMENFont.bold(11))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            
            // Pray button
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                    hasPrayed.toggle()
                }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                        .font(.systemScaled(12, weight: .semibold))
                    Text(hasPrayed ? "Prayed" : "Pray Now")
                        .font(AMENFont.bold(12))
                }
                .foregroundStyle(hasPrayed ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(hasPrayed ? Color.black : Color.black.opacity(0.08))
                )
            }
        }
        .padding(14)
        .frame(height: 240)
        .background(
            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var categoryBadge: some View {
        let config = categoryConfig
        
        HStack(spacing: 3) {
            Image(systemName: config.icon)
                .font(.systemScaled(9, weight: .semibold))
            
            Text(config.label)
                .font(AMENFont.bold(9))
        }
        .foregroundStyle(config.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: config.color.opacity(0.3), radius: 4, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(config.color, lineWidth: 1.5)
        )
    }
    
    private var categoryConfig: (icon: String, label: String, color: Color) {
        switch post.category {
        case .prayer:
            return ("hands.sparkles.fill", "PRAYER", Color(red: 0.4, green: 0.7, blue: 1.0))
        case .praise:
            return ("hands.clap.fill", "PRAISE", Color(red: 1.0, green: 0.7, blue: 0.4))
        case .answered:
            return ("checkmark.seal.fill", "ANSWERED", Color(red: 0.4, green: 0.85, blue: 0.7))
        }
    }
}

// MARK: - Prayer Wall Post Model

struct PrayerWallPost: Identifiable {
    let id: String          // Firestore document ID
    let title: String
    let author: String
    let timeAgo: String
    let createdAt: Date     // Used for "Today" filter
    let category: PrayerPostCard.PrayerCategory
    let prayCount: Int
    let isUrgent: Bool
    let excerpt: String
}

// MARK: - Live Discussion View

struct LiveDiscussionView: View {
    @Binding var isShowing: Bool
    @State private var selectedTopic: DiscussionTopic = .general
    @State private var isMuted = true
    @State private var isHandRaised = false
    @State private var participantCount = Int.random(in: 45...234)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    enum DiscussionTopic: String, CaseIterable {
        case general = "General Prayer"
        case healing = "Healing & Health"
        case family = "Family Matters"
        case breakthrough = "Breakthrough"
    }
    
    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        isShowing = false
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.3, blue: 0.3))
                                .frame(width: 8, height: 8)

                            Text("LIVE")
                                .font(AMENFont.bold(12))
                                .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                        }

                        Text("Live Discussion")
                            .font(AMENFont.bold(26))
                            .foregroundStyle(.white)

                        Text("\(participantCount) people listening")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                            isShowing = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)

                // Topic selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DiscussionTopic.allCases, id: \.self) { topic in
                            Button {
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                                    selectedTopic = topic
                                }
                            } label: {
                                Text(topic.rawValue)
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(selectedTopic == topic ? .black : .white.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedTopic == topic ? Color.white : Color.white.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
                
                // Current speakers section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Speaking Now")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            LiveSpeakerCard(
                                name: "Pastor Michael",
                                topic: "Leading prayer for healing",
                                isSpeaking: true
                            )
                            
                            LiveSpeakerCard(
                                name: "Sister Grace",
                                topic: "Sharing testimony",
                                isSpeaking: false
                            )
                            
                            LiveSpeakerCard(
                                name: "Brother John",
                                topic: "Interceding for families",
                                isSpeaking: false
                            )
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                Spacer()
                
                // Control buttons
                HStack(spacing: 20) {
                    Button {
                        withAnimation(reduceMotion ? nil : .default) {
                            isMuted.toggle()
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(isMuted ? Color.white.opacity(0.15) : Color(red: 1.0, green: 0.3, blue: 0.3))
                                    .frame(width: 60, height: 60)

                                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                                    .font(.systemScaled(24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            Text(isMuted ? "Unmute" : "Muted")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65)) {
                            isHandRaised.toggle()
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        dlog("🖐️ [LiveDiscussion] Hand \(isHandRaised ? "raised" : "lowered")")
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(isHandRaised
                                          ? Color(red: 1.0, green: 0.85, blue: 0.2)
                                          : Color.white.opacity(0.15))
                                    .frame(width: 60, height: 60)

                                Image(systemName: "hand.raised.fill")
                                    .font(.systemScaled(24, weight: .semibold))
                                    .foregroundStyle(isHandRaised ? Color.black.opacity(0.8) : .white)
                                    .symbolEffect(.bounce, value: isHandRaised)
                            }

                            Text(isHandRaised ? "Lower Hand" : "Raise Hand")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .accessibilityLabel(isHandRaised ? "Lower your hand" : "Raise your hand to speak")

                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                            isShowing = false
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 1.0, green: 0.3, blue: 0.3))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "phone.down.fill")
                                    .font(.systemScaled(24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            
                            Text("Leave")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Live Speaker Card

struct LiveSpeakerCard: View {
    let name: String
    let topic: String
    let isSpeaking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(AMENFont.bold(20))
                            .foregroundStyle(.white)
                    )
                
                if isSpeaking {
                    Circle()
                        .stroke(Color(red: 0.4, green: 0.85, blue: 0.7), lineWidth: 3)
                        .frame(width: 56, height: 56)
                        .scaleEffect(isSpeaking ? 1.1 : 1.0)
                        .opacity(isSpeaking ? 0.8 : 0)
                        .animation(reduceMotion ? .none : .easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isSpeaking)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.white)
                
                HStack(spacing: 6) {
                    if isSpeaking {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.3, blue: 0.3))
                                .frame(width: 6, height: 6)
                            
                            Text("Speaking")
                                .font(AMENFont.semiBold(12))
                                .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                        }
                    }
                    
                    Text(topic)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
                        .stroke(isSpeaking ? Color(red: 0.4, green: 0.85, blue: 0.7).opacity(0.3) : Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

// MARK: - Collaboration Hub View

struct CollaborationHubView: View {
    @Binding var isShowing: Bool
    @State private var selectedFilter: CollabFilter = .all
    @State private var searchText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Real data — loaded from Firestore on .task
    @State private var collaborators: [Collaborator] = []
    @State private var isLoading = true
    @State private var loadError: String?

    private let db = Firestore.firestore()

    enum CollabFilter: String, CaseIterable {
        case all = "All"
        case available = "Available Now"
        case groups = "Prayer Groups"
        case partners = "Partners"
    }

    // Filtered + searched list shown in the list
    private var displayedCollaborators: [Collaborator] {
        let filtered: [Collaborator]
        switch selectedFilter {
        case .all:
            filtered = collaborators
        case .available:
            filtered = collaborators.filter { $0.isOnline }
        case .groups, .partners:
            // Future: filter by role tag. For now show all.
            filtered = collaborators
        }
        guard !searchText.isEmpty else { return filtered }
        let q = searchText.lowercased()
        return filtered.filter {
            $0.name.lowercased().contains(q) || $0.specialty.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                        isShowing = false
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Collaboration Hub")
                            .font(AMENFont.bold(26))
                            .foregroundStyle(.white)

                        Text("Find prayer partners & mentors")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Spacer()

                    Button {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                            isShowing = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)

                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.4))

                    TextField("Search by name or topic...", text: $searchText)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.white)
                        .tint(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.1))
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // Filter tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CollabFilter.allCases, id: \.self) { filter in
                            Button {
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                                    selectedFilter = filter
                                }
                            } label: {
                                Text(filter.rawValue)
                                    .font(AMENFont.semiBold(13))
                                    .foregroundStyle(selectedFilter == filter ? .black : .white.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(selectedFilter == filter ? Color.white : Color.white.opacity(0.1))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)

                // Collaborators list — loading / empty / loaded states
                if isLoading {
                    collaboratorsSkeleton
                } else if let err = loadError {
                    errorState(message: err)
                } else if displayedCollaborators.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(displayedCollaborators) { collaborator in
                                CollaboratorCard(collaborator: collaborator)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .task { await loadCollaborators() }
    }

    // MARK: - Firestore fetch

    /// Queries recent prayer posts (last 30 days), collects distinct authorIds,
    /// batch-fetches their user profiles, and maps them to Collaborator values.
    @MainActor
    private func loadCollaborators() async {
        dlog("🤝 [CollaborationHub] Loading prayer collaborators from Firestore")
        isLoading = true
        loadError = nil

        do {
            let currentUid = Auth.auth().currentUser?.uid
            let cutoff = Timestamp(date: Date().addingTimeInterval(-30 * 24 * 3600))

            // 1. Fetch recent prayer posts to discover active participants.
            //    PostCategory.prayer.rawValue == "prayer" (lowercase, Firebase-safe).
            let snapshot = try await db.collection("posts")
                .whereField("category", isEqualTo: "prayer")
                .whereField("createdAt", isGreaterThan: cutoff)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            dlog("🤝 [CollaborationHub] Got \(snapshot.documents.count) recent prayer posts")

            // 2. Collect distinct authorIds (excluding current user)
            var seen = Set<String>()
            var authorIds: [String] = []
            for doc in snapshot.documents {
                let authorId = doc.data()["authorId"] as? String ?? ""
                guard !authorId.isEmpty,
                      authorId != currentUid,
                      !seen.contains(authorId) else { continue }
                seen.insert(authorId)
                authorIds.append(authorId)
                if authorIds.count >= 20 { break } // cap at 20 collaborators
            }

            guard !authorIds.isEmpty else {
                dlog("🤝 [CollaborationHub] No prayer authors found")
                isLoading = false
                return
            }

            // 3. Batch-fetch user profiles (Firestore `in` max 10 per query)
            var profiles: [[String: Any]] = []
            let chunks = stride(from: 0, to: authorIds.count, by: 10).map {
                Array(authorIds[$0 ..< min($0 + 10, authorIds.count)])
            }
            for chunk in chunks {
                let usersSnap = try await db.collection("users")
                    .whereField(FieldPath.documentID(), in: chunk)
                    .getDocuments()
                profiles.append(contentsOf: usersSnap.documents.map { $0.data().merging(["uid": $0.documentID]) { $1 } })
            }

            dlog("🤝 [CollaborationHub] Fetched \(profiles.count) user profiles")

            // 4. Map to Collaborator model
            let now = Date()
            let mapped: [Collaborator] = profiles.compactMap { d in
                let uid = d["uid"] as? String ?? ""
                guard !uid.isEmpty else { return nil }
                let displayName = d["displayName"] as? String
                    ?? d["username"] as? String
                    ?? "Prayer Partner"
                let photoURL  = d["photoURL"] as? String ?? ""
                let prayerCount = d["prayerCount"] as? Int ?? 0

                // Rough availability heuristic — users active in the last hour
                let lastSeen: Date
                if let ts = d["lastSeen"] as? Timestamp {
                    lastSeen = ts.dateValue()
                } else {
                    lastSeen = .distantPast
                }
                let isOnline = now.timeIntervalSince(lastSeen) < 3600
                let availability = isOnline ? "Active now" : "Recently active"

                // Derive specialty from user bio or prayer focus tags
                let specialty = (d["bio"] as? String).flatMap { bio in
                    bio.isEmpty ? nil : String(bio.prefix(60))
                } ?? "Prayer & intercession"

                return Collaborator(
                    userId: uid,
                    name: displayName,
                    photoURL: photoURL,
                    specialty: specialty,
                    availability: availability,
                    isOnline: isOnline,
                    prayerCount: prayerCount,
                    rating: 0.0 // reserved for future peer rating feature
                )
            }

            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                collaborators = mapped
                isLoading = false
            }
            dlog("🤝 [CollaborationHub] Displayed \(mapped.count) collaborators")
        } catch {
            dlog("❌ [CollaborationHub] Load failed: \(error)")
            loadError = "Couldn't load prayer partners. Pull to retry."
            isLoading = false
        }
    }

    // MARK: - Loading skeleton

    private var collaboratorsSkeleton: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 120)
                        .overlay(
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 60, height: 60)
                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 120, height: 14)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.10))
                                        .frame(width: 180, height: 11)
                                }
                                Spacer()
                            }
                            .padding(20)
                        )
                        // Pulse animation serves as a lightweight shimmer substitute
                        .opacity(isLoading ? 1.0 : 0.0)
                        .animation(reduceMotion ? .none : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isLoading)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hands.sparkles")
                .font(.systemScaled(48))
                .foregroundStyle(.white.opacity(0.35))
            Text("No prayer partners found")
                .font(AMENFont.bold(18))
                .foregroundStyle(.white)
            Text("Be the first to post a prayer — your community will find you.")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Error state

    private func errorState(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.systemScaled(40))
                .foregroundStyle(.white.opacity(0.5))
            Text(message)
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                Task { await loadCollaborators() }
            } label: {
                Text("Retry")
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white))
            }
            Spacer()
        }
    }
}

// MARK: - Collaborator Model

struct Collaborator: Identifiable {
    let userId: String
    let name: String
    let photoURL: String
    let specialty: String
    let availability: String
    let isOnline: Bool
    let prayerCount: Int
    let rating: Double

    var id: String { userId }
}

// MARK: - Collaborator Card

struct CollaboratorCard: View {
    let collaborator: Collaborator
    @State private var isPressed = false
    @State private var showChat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Avatar with online indicator
                ZStack(alignment: .bottomTrailing) {
                    if let url = URL(string: collaborator.photoURL), !collaborator.photoURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            default:
                                collaboratorInitialAvatar
                            }
                        }
                    } else {
                        collaboratorInitialAvatar
                    }

                    if collaborator.isOnline {
                        Circle()
                            .fill(Color(red: 0.4, green: 0.85, blue: 0.7))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 2)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(collaborator.name)
                        .font(AMENFont.bold(17))
                        .foregroundStyle(.white)

                    Text(collaborator.specialty)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()
            }

            // Stats row
            HStack(spacing: 20) {
                if collaborator.prayerCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.systemScaled(12))
                            .foregroundStyle(.white.opacity(0.6))

                        Text("\(collaborator.prayerCount) prayers")
                            .font(AMENFont.semiBold(13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.systemScaled(12))
                        .foregroundStyle(collaborator.isOnline ? Color(red: 0.4, green: 0.85, blue: 0.7) : .white.opacity(0.5))

                    Text(collaborator.availability)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(collaborator.isOnline ? Color(red: 0.4, green: 0.85, blue: 0.7) : .white.opacity(0.5))
                }

                Spacer()
            }

            // "Pray Together" CTA — opens a DM thread with this partner
            AmenLiquidGlassPillButton(
                title: "Pray Together",
                systemImage: "message.fill",
                isLoading: false,
                isDisabled: false,
                hint: "Start a prayer conversation with \(collaborator.name)"
            ) {
                dlog("🤝 [CollaborationHub] Opening DM with \(collaborator.name) (\(collaborator.userId))")
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showChat = true
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: AmenTheme.CornerRadius.card) // P2-3: canonical token
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(isPressed ? 0.8 : 1.0)
        .onLongPressGesture(minimumDuration: 0.4, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
        .contextMenu {
            Button {
                showChat = true
            } label: {
                Label("Reply", systemImage: "arrow.turn.up.left")
            }

            Button {
                UIPasteboard.general.string = collaborator.userId
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                showChat = true
            } label: {
                Label("Pray for this", systemImage: "hands.sparkles")
            }
        }
        // Open DM using existing ChatConversationLoader (resolves/creates the conversation ID)
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatConversationLoader(
                    userId: collaborator.userId,
                    userName: collaborator.name
                )
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationCornerRadius(28)
        }
    }

    private var collaboratorInitialAvatar: some View {
        Circle()
            .fill(Color.black)
            .frame(width: 60, height: 60)
            .overlay(
                Text(String(collaborator.name.prefix(1)).uppercased())
                    .font(AMENFont.bold(24))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Prayer Group Model

struct PrayerGroup: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let memberCount: Int
    let activeNow: Int
    let description: String
    let color: Color
    let category: String

    var members: Int { memberCount }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        memberCount: Int,
        activeNow: Int,
        description: String,
        color: Color,
        category: String
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.memberCount = memberCount
        self.activeNow = activeNow
        self.description = description
        self.color = color
        self.category = category
    }
}

// MARK: - Prayer Group Detail View

struct PrayerGroupDetailView: View {
    let group: PrayerGroup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasJoined = false
    @State private var selectedTab: GroupDetailTab = .about
    @State private var showGroupDailyPrayer = false

    enum GroupDetailTab: String, CaseIterable {
        case about = "About"
        case members = "Members"
        case prayers = "Prayers"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Hero Header
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [group.color, group.color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 200)
                    
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: group.icon)
                                .font(.systemScaled(36, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(group.name)
                            .font(AMENFont.bold(24))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 30)
                }
                
                // Stats Row
                HStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Text("\(group.members)")
                            .font(AMENFont.bold(20))
                        Text("Members")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(group.activeNow)")
                            .font(AMENFont.bold(20))
                        Text("Active Now")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("24/7")
                            .font(AMENFont.bold(20))
                        Text("Support")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 20)
                
                // Tabs
                HStack(spacing: 8) {
                    ForEach(GroupDetailTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(reduceMotion ? nil : .default) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(selectedTab == tab ? .white : .black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.black : Color.gray.opacity(0.1))
                                )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .about:
                            AboutGroupView(group: group)
                        case .members:
                            MembersView(groupId: group.id.uuidString)
                        case .prayers:
                            GroupPrayersView(groupId: group.id.uuidString)
                        }
                    }
                    .padding()
                }
                
                // Join Button
                Group {
                    if !hasJoined {
                        joinButton
                    } else {
                        joinedButtonsRow
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        // P1-4: route to EnhancedDailyPrayerView
        .sheet(isPresented: $showGroupDailyPrayer) {
            EnhancedDailyPrayerView()
        }
    }

    // MARK: - Extracted View Components
    
    private var joinButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                hasJoined = true
            }
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } label: {
            Text("Join Prayer Group")
                .font(AMENFont.bold(17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(group.color)
                )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private var joinedButtonsRow: some View {
        HStack(spacing: 12) {
            messageGroupButton
            startPrayingButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    private var messageGroupButton: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            // Navigate to Messages tab filtered to this group's discussion thread
            MessagingCoordinator.shared.openMessagesTab()
            dlog("💬 [PrayerGroup] Opening messages for group: \(group.name)")
        } label: {
            Image(systemName: "message.fill")
                .font(.systemScaled(18))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(group.color))
        }
        .accessibilityLabel("Message group members")
    }

    private var startPrayingButton: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            showGroupDailyPrayer = true
            dlog("🙏 [PrayerGroup] Starting prayer session for group: \(group.name)")
        } label: {
            HStack {
                Image(systemName: "hands.sparkles.fill")
                Text("Start Praying")
                    .font(AMENFont.bold(16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(group.color)
            )
        }
        .accessibilityLabel("Start a guided prayer session")
    }
}

// MARK: - About Group View
struct AboutGroupView: View {
    let group: PrayerGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(AMENFont.bold(18))
                
                Text(group.description)
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Group Rules")
                    .font(AMENFont.bold(18))
                
                GroupRuleRow(icon: "hands.sparkles.fill", rule: "Pray together daily", color: group.color)
                GroupRuleRow(icon: "heart.fill", rule: "Respect all members", color: group.color)
                GroupRuleRow(icon: "shield.checkmark.fill", rule: "Keep prayers confidential", color: group.color)
                GroupRuleRow(icon: "clock.fill", rule: "Active participation expected", color: group.color)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting Times")
                    .font(AMENFont.bold(18))
                
                Text("Daily Prayer: 6:00 AM, 12:00 PM, 9:00 PM EST")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                
                Text("Weekly Zoom: Every Sunday at 7:00 PM EST")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct GroupRuleRow: View {
    let icon: String
    let rule: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(18))
                .foregroundStyle(color)
                .frame(width: 30)
            
            Text(rule)
                .font(AMENFont.regular(15))
        }
    }
}

// MARK: - Members View
struct MembersView: View {
    let groupId: String

    struct GroupMember: Identifiable {
        let id: String
        let displayName: String
        let username: String
        let isOnline: Bool
    }

    @State private var members: [GroupMember] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 12) {
            if isLoading && members.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if members.isEmpty {
                Text("No members yet")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(member.displayName.prefix(1)))
                                        .font(AMENFont.bold(16))
                                        .foregroundStyle(.white)
                                )

                            if member.isOnline {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(AMENFont.bold(15))
                            Text("@\(member.username)")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                            // Open DM with this member via the messaging coordinator
                            Task {
                                if let conversationId = try? await FirebaseMessagingService.shared
                                    .getOrCreateDirectConversation(withUserId: member.id, userName: member.displayName) {
                                    MessagingCoordinator.shared.openConversation(conversationId)
                                }
                            }
                        } label: {
                            Image(systemName: "message")
                                .font(.systemScaled(16))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Message \(member.displayName)")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                    )
                }
            }
        }
        .task { await loadMembers() }
    }

    private func loadMembers() async {
        guard !groupId.isEmpty, !isLoading else { return }
        isLoading = true
        do {
            let db = Firestore.firestore()
            let snap = try await db.collection("prayerGroups")
                .document(groupId)
                .collection("members")
                .limit(to: 30)
                .getDocuments()

            let now = Date()
            let fetched: [GroupMember] = snap.documents.compactMap { doc in
                let d = doc.data()
                guard let displayName = d["displayName"] as? String else { return nil }
                let lastSeen = (d["lastSeen"] as? Timestamp)?.dateValue() ?? .distantPast
                return GroupMember(
                    id: doc.documentID,
                    displayName: displayName,
                    username: d["username"] as? String ?? displayName.lowercased(),
                    isOnline: now.timeIntervalSince(lastSeen) < 3600
                )
            }
            await MainActor.run {
                members = fetched
                isLoading = false
                dlog("✅ MembersView: loaded \(fetched.count) members for group \(groupId)")
            }
        } catch {
            await MainActor.run {
                isLoading = false
                dlog("❌ MembersView: load failed — \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Group Prayers View
struct GroupPrayersView: View {
    let groupId: String

    @State private var posts: [Post] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 16) {
            if isLoading && posts.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if posts.isEmpty {
                Text("No prayers posted yet")
                    .font(AMENFont.regular(15))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(posts) { post in
                    PostCard(post: post, isUserPost: post.authorId == Auth.auth().currentUser?.uid)
                }
            }
        }
        .task { await loadGroupPrayers() }
    }

    private func loadGroupPrayers() async {
        guard !groupId.isEmpty, !isLoading else { return }
        isLoading = true
        do {
            let db = Firestore.firestore()
            let snap = try await db.collection("posts")
                .whereField("category", isEqualTo: "prayer")
                .whereField("prayerGroupId", isEqualTo: groupId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            let fetched = snap.documents.compactMap { try? $0.data(as: Post.self) }
            await MainActor.run {
                posts = fetched
                isLoading = false
                dlog("✅ GroupPrayersView: loaded \(fetched.count) posts for group \(groupId)")
            }
        } catch {
            await MainActor.run {
                isLoading = false
                dlog("❌ GroupPrayersView: load failed — \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Create Prayer Group View
// NOTE: CreatePrayerGroupView has been moved to PrayerGroupsView.swift

// MARK: - ShareSheet
// NOTE: ShareSheet is defined in ShareSheet.swift - no need to redefine here

#Preview {
    PrayerView()
}
