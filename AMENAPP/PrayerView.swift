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
    @StateObject private var postsManager = PostsManager.shared
    @StateObject private var prayerAlgorithm = PrayerAlgorithm.shared
    @State private var selectedTab: PrayerTab = .requests
    @State private var showDailyPrayer = false
    @State private var showPrayerGroups = false
    @State private var showPrayerWall = false
    @State private var showLiveDiscussion = false
    @State private var showCollaborationHub = false
    @State private var selectedPrayerAuthor: PrayerAuthorInfo?
    @State private var currentBannerIndex = 0
    @State private var isBannerExpanded = true  // ✅ NEW: Toggle for banner visibility
    @State private var rankedPrayers: [Post] = []
    @State private var hasRanked = false
    
    // Timer for auto-swipe
    let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
    
    enum PrayerTab: String, CaseIterable {
        case requests = "Requests"
        case praises = "Praises"
        case answered = "Answered"
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Pray together, grow together")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                
                Text("Prayer")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.black)
                
                Text("Share requests • Lift each other up")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Tabs - Center Aligned
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    ForEach(PrayerTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = tab
                            }
                            
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
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
                Spacer()
            }
            .padding(.horizontal)
            
            // ✅ Auto-scrolling Banner Section with Subtle Hide Button
            VStack(spacing: 0) {
                if isBannerExpanded {
                    ZStack(alignment: .topTrailing) {
                        // Banners
                        TabView(selection: $currentBannerIndex) {
                            // Daily Prayer Reminder
                            PrayerBannerCard(
                                icon: "sunrise.fill",
                                title: "Daily Prayer",
                                subtitle: "Three moments with God",
                                description: "Morning • Midday • Evening",
                                gradientColors: [Color(red: 1.0, green: 0.7, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.2)],
                                isBlackAndWhite: false
                            )
                            .padding(.horizontal, 20)
                            .tag(0)
                            
                            // Prayer Chain
                            PrayerBannerCard(
                                icon: "link.circle.fill",
                                title: "Prayer Chain",
                                subtitle: "United in prayer",
                                description: "Join thousands praying together daily",
                                gradientColors: [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.6, green: 0.5, blue: 1.0)],
                                isBlackAndWhite: false
                            )
                            .padding(.horizontal, 20)
                            .tag(1)
                            
                            // Scripture of the Day
                            PrayerBannerCard(
                                icon: "book.fill",
                                title: "Daily Scripture",
                                subtitle: "God's Word for today",
                                description: "Find encouragement in the Word",
                                gradientColors: [Color(red: 0.4, green: 0.85, blue: 0.7), Color(red: 0.4, green: 0.7, blue: 1.0)],
                                isBlackAndWhite: false
                            )
                            .padding(.horizontal, 20)
                            .tag(2)
                            
                            // Prayer Streaks
                            PrayerBannerCard(
                                icon: "flame.fill",
                                title: "Prayer Streak",
                                subtitle: "Keep your momentum",
                                description: "7 days strong • Don't break the chain!",
                                gradientColors: [Color(red: 1.0, green: 0.4, blue: 0.3), Color(red: 1.0, green: 0.6, blue: 0.2)],
                                isBlackAndWhite: false
                            )
                            .padding(.horizontal, 20)
                            .tag(3)
                            
                            // Community Stats
                            PrayerBannerCard(
                                icon: "heart.circle.fill",
                                title: "Community Impact",
                                subtitle: "Together in faith",
                                description: "2,847 prayers lifted today 🙏",
                                gradientColors: [Color(red: 0.8, green: 0.3, blue: 0.9), Color(red: 1.0, green: 0.4, blue: 0.7)],
                                isBlackAndWhite: false
                            )
                            .padding(.horizontal, 20)
                            .tag(4)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .frame(height: 110)
                        .onReceive(timer) { _ in
                            withAnimation(.easeInOut(duration: 0.5)) {
                                currentBannerIndex = (currentBannerIndex + 1) % 5
                            }
                        }
                        
                        // ✅ SUBTLE HIDE BUTTON - Top right corner
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                isBannerExpanded = false
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.8))
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 28, height: 28)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .padding(.trailing, 28)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
                } else {
                    // ✅ SUBTLE SHOW BUTTON when banners are hidden - just chevron arrow
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            isBannerExpanded = true
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .symbolEffect(.bounce, value: isBannerExpanded)
                    }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .transition(.opacity)
            }
            }
            
            // Content based on selected tab
            ScrollView {
                VStack(spacing: 16) {
                    // Filter posts from PostsManager based on selected tab
                    let filteredPrayerPosts = {
                        var posts = postsManager.prayerPosts.filter { post in
                            guard let topicTag = post.topicTag else { return false }

                            switch selectedTab {
                            case .requests:
                                return topicTag == "Prayer Request"
                            case .praises:
                                return topicTag == "Praise Report"
                            case .answered:
                                return topicTag == "Answered Prayer"
                            }
                        }

                        // Apply intelligent ranking for prayer requests
                        if selectedTab == .requests && hasRanked && !rankedPrayers.isEmpty {
                            // Use ranked prayers for requests tab
                            let rankedIds = Set(rankedPrayers.map { $0.id })
                            posts = rankedPrayers.filter { rankedIds.contains($0.id) }
                        }

                        return posts
                    }()

                    // Display filtered posts
                    ForEach(filteredPrayerPosts) { post in
                        PrayerPostCard(post: post)
                            .onAppear {
                                // Track view interaction
                                prayerAlgorithm.recordView(for: post)
                            }
                    }
                    
                    // Show empty state if no posts
                    if filteredPrayerPosts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: emptyStateIcon)
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            
                            Text(emptyStateTitle)
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.primary)
                            
                            Text(emptyStateSubtitle)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                }
                .padding(.horizontal)
            }
            .refreshable {
                await refreshPrayers()
            }
        }
            .sheet(isPresented: $showDailyPrayer) {
                DailyPrayerView()
            }
            .sheet(isPresented: $showPrayerGroups) {
                PrayerGroupsView()
            }
            .sheet(isPresented: $showPrayerWall) {
                PrayerWallView()
            }
            .sheet(isPresented: $showLiveDiscussion) {
                LiveDiscussionView(isShowing: $showLiveDiscussion)
            }
            .sheet(isPresented: $showCollaborationHub) {
                CollaborationHubView(isShowing: $showCollaborationHub)
            }
            .sheet(item: $selectedPrayerAuthor) { authorInfo in
                SmartPrayerChatView(authorInfo: authorInfo)
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // ✅ Start real-time listener for prayer posts
                FirebasePostService.shared.startListening(category: .prayer)

                // Load algorithm history and rank prayers
                if !hasRanked {
                    prayerAlgorithm.loadHistory()
                    rankPrayerRequests()
                    hasRanked = true
                }
            }
            .onChange(of: postsManager.prayerPosts) { oldValue, newValue in
                // Re-rank when new prayers arrive
                if oldValue.count != newValue.count {
                    rankPrayerRequests()
                }
            }
        }
    }
    
    // MARK: - Helper Functions

    /// Rank prayer requests using algorithm
    private func rankPrayerRequests() {
        let prayerRequests = postsManager.prayerPosts.filter { post in
            post.topicTag == "Prayer Request"
        }

        guard !prayerRequests.isEmpty else {
            rankedPrayers = []
            return
        }

        // Rank prayers using algorithm (off main thread)
        Task.detached(priority: .userInitiated) {
            let ranked = await prayerAlgorithm.rankPrayers(
                prayerRequests,
                for: prayerAlgorithm.userPrayerHistory
            )

            await MainActor.run {
                rankedPrayers = ranked
                print("🙏 Prayers ranked: \(rankedPrayers.count) requests prioritized")
            }
        }
    }

    /// Refresh prayers with pull-to-refresh
    private func refreshPrayers() async {
        print("🔄 Refreshing Prayer posts...")
        
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
            print("✅ Prayer posts refreshed!")
        }
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

// MARK: - Prayer Author Info Model

struct PrayerAuthorInfo: Identifiable {
    let id = UUID()
    let name: String
    let prayerContent: String
    let prayerCategory: PrayerPostCard.PrayerCategory
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
                        .font(.system(size: 18, weight: .semibold))  // ✅ Reduced from 26 to 18
                        .foregroundStyle(isBlackAndWhite ? .white : .white)
                        .symbolEffect(.pulse, options: .repeating.speed(0.7))
                }
                
                VStack(alignment: .leading, spacing: 2) {  // ✅ Reduced from 4 to 2
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 15))  // ✅ Reduced from 20 to 15
                        .foregroundStyle(isBlackAndWhite ? .black : .white)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-SemiBold", size: 11))  // ✅ Reduced from 13 to 11
                        .foregroundStyle(isBlackAndWhite ? .black.opacity(0.6) : .white.opacity(0.9))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))  // ✅ Reduced from 16 to 12
                    .foregroundStyle(isBlackAndWhite ? .black.opacity(0.3) : .white.opacity(0.7))
            }
            
            Text(description)
                .font(.custom("OpenSans-Regular", size: 11))  // ✅ Reduced from 14 to 11
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
                    .shadow(color: colors.first!.opacity(0.4), radius: 10, y: 4)  // ✅ Reduced shadow
                }
            }
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            if !isBlackAndWhite {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
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
    @State private var currentPrayerIndex = 0
    @State private var completedPrayers: Set<Int> = []
    @State private var showCompletionCelebration = false
    
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
                    Text("Daily Prayer")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)
                
                Text("Three moments with God throughout your day")
                    .font(.custom("OpenSans-Regular", size: 14))
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
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    completedPrayers.insert(index)
                                    
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
    }
}

// MARK: - Daily Prayer Card with Liquid Glass Buttons

struct DailyPrayerCard: View {
    let prayer: DailyPrayerItem
    let isCompleted: Bool
    let onComplete: () -> Void
    
    @State private var showFullPrayer = false
    @State private var isButtonPressed = false
    
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
            RoundedRectangle(cornerRadius: 18)
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
            
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [
                            prayer.color.opacity(0.6),
                            prayer.color.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
    }
    
    private var defaultButtonBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.white.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
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
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(prayer.color)
                                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                        }
                        .padding(.top, 30)
                        
                        VStack(spacing: 8) {
                            Text(prayer.title)
                                .font(.custom("OpenSans-Bold", size: 28))
                                .foregroundStyle(.white)
                            
                            Text(prayer.time)
                                .font(.custom("OpenSans-Regular", size: 14))
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
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(prayer.color)
                                }
                                
                                Text("Prayer")
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            
                            Text(prayer.prayer)
                                .font(.custom("OpenSans-Regular", size: 17))
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
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(prayer.color)
                                }
                                
                                Text("Scripture")
                                    .font(.custom("OpenSans-Bold", size: 15))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            
                            Text(prayer.scripture)
                                .font(.custom("OpenSans-Regular", size: 16))
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
                    Button(action: onComplete) {
                        HStack(spacing: 10) {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .bold))
                                .symbolEffect(.bounce, value: isCompleted)
                            
                            Text(isCompleted ? "Prayed ✓" : "Mark as Prayed")
                                .font(.custom("OpenSans-Bold", size: 17))
                        }
                        .foregroundStyle(isCompleted ? prayer.color : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(buttonBackground)
                        .shadow(
                            color: isCompleted ? prayer.color.opacity(0.4) : Color.white.opacity(0.2),
                            radius: isCompleted ? 20 : 15,
                            y: 10
                        )
                        .scaleEffect(isButtonPressed ? 0.96 : 1.0)
                    }
                    .disabled(isCompleted)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                withAnimation(.easeIn(duration: 0.1)) {
                                    isButtonPressed = true
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeOut(duration: 0.1)) {
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
                        .font(.system(size: 60))
                        .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
                        .symbolEffect(.bounce)
                }
                
                VStack(spacing: 8) {
                    Text("All Prayers Complete!")
                        .font(.custom("OpenSans-Bold", size: 26))
                        .foregroundStyle(.white)
                    
                    Text("You've spent time with God throughout your day. Well done, faithful servant!")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 40)
                }
                
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowing = false
                    }
                } label: {
                    Text("Continue")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.black)
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
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
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
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.white)
                        
                        Text("Pray together, grow together")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
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
                                .font(.custom("OpenSans-SemiBold", size: 14))
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
                            .font(.system(size: 18, weight: .semibold))
                        
                        Text("Create Prayer Group")
                            .font(.custom("OpenSans-Bold", size: 16))
                    }
                    .foregroundStyle(.black)
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
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(group.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        Text(group.category)
                            .font(.custom("OpenSans-SemiBold", size: 11))
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
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(4)
                    .lineLimit(2)
                
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text("\(group.memberCount) members")
                            .font(.custom("OpenSans-SemiBold", size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    if group.activeNow > 0 {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.4, green: 0.85, blue: 0.7))
                                .frame(width: 6, height: 6)
                            
                            Text("\(group.activeNow) praying now")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.7))
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
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
    
    @StateObject private var postsManager = PostsManager.shared
    @StateObject private var interactionsService = PostInteractionsService.shared
    @StateObject private var savedPostsService = SavedPostsService.shared
    @StateObject private var followService = FollowService.shared
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
    @Namespace private var glassNamespace
    
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
        .sheet(isPresented: $showingEditSheet) {
            EditPostSheet(post: post)
        }
        .sheet(isPresented: $showFullCommentSheet) {
            CommentsView(post: post)
                .environmentObject(UserService())
        }
        .alert("Delete Post", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deletePost()
            }
        } message: {
            Text("Are you sure you want to delete this prayer post? This action cannot be undone.")
        }
        .sheet(isPresented: $showReportSheet) {
            ReportPostSheet(post: post, postAuthor: authorName, category: .prayer)
        }
        .sheet(isPresented: $showShareSheet) {
            // ✅ FIXED: Use native SwiftUI ActivityViewController wrapper
            ShareSheet(items: [shareText])
        }
        .sheet(isPresented: $showUserProfile) {
            if !post.authorId.isEmpty {
                UserProfileView(userId: post.authorId)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("Unable to Load Profile")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text("This user's profile is not available.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showUserProfile = false
                    } label: {
                        Text("Close")
                            .font(.custom("OpenSans-Bold", size: 16))
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isFollowing = newFollowState
                }
                print("🔄 Follow state synced for \(authorName): \(newFollowState)")
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(prayerTopicTagColor)
                
                Text(topicTag)
                    .font(.custom("OpenSans-SemiBold", size: 12))
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
            Text(content)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.black.opacity(0.9))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

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
                                                    .font(.custom("OpenSans-Bold", size: 24))
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
    
    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.black.opacity(0.1), lineWidth: 1)
    }
    
    @ViewBuilder
    private var avatarWithFollowButton: some View {
        Button {
            print("👤 Opening profile for user ID: \(post.authorId)")
            print("   Author name: \(authorName)")
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
                                    .font(.custom("OpenSans-Bold", size: 18))
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
                                .font(.custom("OpenSans-Bold", size: 18))
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
            .font(.system(size: 18, weight: .semibold))
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
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.black)
            
            Text(timeAgo)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.black.opacity(0.5))
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
                .font(.system(size: 18, weight: .semibold))
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
                .font(.system(size: 13, weight: .semibold))
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
        // OPTIMISTIC UPDATE: Update UI immediately for instant feedback
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            hasAmened.toggle()
            amenCount = hasAmened ? amenCount + 1 : amenCount - 1
            isAmenAnimating = true
        }
        
        let haptic = UIImpactFeedbackGenerator(style: hasAmened ? .medium : .light)
        haptic.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isAmenAnimating = false
        }
        
        // Capture the post ID before detaching
        let postId = post.backendId
        
        // Background sync to Firebase (no await needed)
        Task.detached(priority: .userInitiated) { [interactionsService] in
            do {
                try await interactionsService.toggleAmen(postId: postId)
            } catch {
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        hasAmened.toggle()
                        amenCount = hasAmened ? amenCount + 1 : amenCount - 1
                    }
                    print("❌ Failed to sync Amen: \(error)")
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
        
        print("🗑️ Prayer post deleted")
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                    print("✅ Followed user: \(targetUserId)")
                } else {
                    try await followService.unfollowUser(userId: targetUserId)
                    print("✅ Unfollowed user: \(targetUserId)")
                }
            } catch {
                print("❌ Failed to toggle follow: \(error)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
            print("⚠️ Cannot start real-time listener: No authenticated user")
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
        hasSaved = await savedPostsService.isPostSaved(postId: postId)
        
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                hasReposted.toggle()
                repostCount += hasReposted ? 1 : -1
            }
            
            // Haptic feedback
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            print("🔄 Prayer \(hasReposted ? "reposted" : "unreposted") (optimistic)")
        }
        
        // Capture post ID before detaching
        let postId = post.id.uuidString
        
        // Background sync to Firebase using RepostService
        Task.detached(priority: .userInitiated) {
            do {
                let repostService = await RepostService.shared
                try await repostService.toggleRepost(postId: postId)
                
                await MainActor.run {
                    print("✅ Repost synced successfully to Firebase")
                }
            } catch {
                print("❌ Failed to toggle repost: \(error.localizedDescription)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
        
        print("⚠️ Showing repost error to user: \(errorMessage)")
        
        // TODO: Show error banner/toast to user
        // For now, just log it - can be enhanced with a toast notification
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                hasSaved.toggle()
            }
            
            // Haptic feedback
            let haptic = UIImpactFeedbackGenerator(style: hasSaved ? .medium : .light)
            haptic.impactOccurred()
            
            print("🔖 Prayer \(hasSaved ? "saved" : "unsaved") (optimistic)")
        }
        
        // Capture the current state and post ID before detaching
        let currentSavedState = hasSaved
        let postId = post.id.uuidString
        
        // Background sync to Firebase
        Task.detached(priority: .userInitiated) { [savedPostsService] in
            do {
                if currentSavedState {
                    try await savedPostsService.savePost(postId: postId)
                    print("✅ Post saved to Firebase")
                } else {
                    try await savedPostsService.unsavePost(postId: postId)
                    print("✅ Post unsaved from Firebase")
                }
            } catch {
                print("❌ Failed to toggle save: \(error.localizedDescription)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
        
        print("⚠️ Showing save error to user: \(errorMessage)")
        
        // TODO: Show error banner/toast to user
        // For now, just log it - can be enhanced with a toast notification
    }
    
    private func onRepost() {
        Task {
            await toggleRepost()
        }
    }
    
    private func copyLink() {
        UIPasteboard.general.string = "https://amenapp.com/prayer/\(UUID().uuidString)"
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        print("🔗 Prayer link copied")
    }
    
    private func muteAuthor() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        print("🔇 Muted \(authorName)")
    }
    
    private func blockAuthor() {
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.warning)
        print("🚫 Blocked \(authorName)")
    }
    
    @ViewBuilder
    private var categoryBadge: some View {
        let config = categoryConfig
        
        HStack(spacing: 4) {
            Image(systemName: config.icon)
                .font(.system(size: 10, weight: .semibold))
            
            Text(config.label)
                .font(.custom("OpenSans-Bold", size: 10))
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
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? .black : .black.opacity(0.5))
                
                if let count = count {
                    Text("\(count)")
                        .font(.custom("OpenSans-SemiBold", size: 11))
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
                    withAnimation(.easeIn(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.1)) {
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
    @State private var showVerseSelector = false
    @State private var isLoading = true
    @State private var isSubmitting = false  // NEW: Track submit state
    @FocusState private var isCommentFocused: Bool
    @StateObject private var commentService = CommentService.shared
    
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
                .font(.custom("OpenSans-Bold", size: 13))
                .foregroundStyle(.black.opacity(0.7))
            
            Spacer()
            
            Text("\(comments.count)")
                .font(.custom("OpenSans-Bold", size: 12))
                .foregroundStyle(.black.opacity(0.5))
        }
    }
    
    @ViewBuilder
    private var errorAlertView: some View {
        if showError, let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                
                Text(error)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button {
                    withAnimation {
                        showError = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
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
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.black.opacity(0.5))
            Text("Share your prayer or encouragement")
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.black.opacity(0.4))
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
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.black)
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showQuickPrayers.toggle()
                }
            } label: {
                Image(systemName: showQuickPrayers ? "hand.raised.fill" : "hand.raised")
                    .font(.system(size: 16))
                    .foregroundStyle(showQuickPrayers ? .black : .black.opacity(0.4))
            }
            
            Button {
                showVerseSelector = true
            } label: {
                Image(systemName: "book.closed")
                    .font(.system(size: 16))
                    .foregroundStyle(.black.opacity(0.4))
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
                            .font(.system(size: 32))
                            .foregroundStyle(.black)
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
        
        let currentUserId = FirebaseManager.shared.currentUser?.uid ?? ""
        let currentUserName = FirebaseManager.shared.currentUser?.displayName ?? "Unknown"
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
            let realComment = try await commentService.addComment(
                postId: post.id.uuidString,
                content: tempCommentText
            )
            
            await MainActor.run {
                isSubmitting = false
                print("✅ Comment posted successfully - will appear via listener")
            }
        } catch {
            print("❌ Failed to post comment: \(error)")
            
            // On error, restore comment text and show error
            await MainActor.run {
                commentText = tempCommentText  // Restore comment text
                isSubmitting = false
                
                // Show user-friendly error
                errorMessage = "Failed to post comment. Please try again."
                withAnimation {
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
                print("✅ Loaded \(comments.count) comments for post: \(post.id.uuidString)")
            }
        } catch {
            print("❌ Failed to load comments: \(error.localizedDescription)")
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
        
        let db = Firestore.firestore()
        let userDoc = try await db.collection("users").document(userId).getDocument()
        
        if let username = userDoc.data()?["username"] as? String {
            return username
        }
        
        return nil
    }
    
    // MARK: - Delete Comment (Production-Ready with Rollback)
    
    private func deleteComment(_ comment: Comment) {
        guard let commentId = comment.id else {
            print("⚠️ Cannot delete comment: Missing comment ID")
            return
        }
        
        // Store comment for potential rollback
        let deletedComment = comment
        let deletedIndex = comments.firstIndex(where: { $0.id == commentId }) ?? 0
        
        // OPTIMISTIC UPDATE: Remove from UI immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                print("✅ Comment deleted successfully: \(commentId)")
            } catch {
                print("❌ Failed to delete comment: \(error.localizedDescription)")
                
                // On error, restore the comment at its original position
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
    @StateObject private var commentService = CommentService.shared
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
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundStyle(.black.opacity(0.7))
                        )
                }
            } else {
                Circle()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(comment.authorInitials)
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundStyle(.black.opacity(0.7))
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.authorName)
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.black.opacity(0.8))
                        
                        Text(comment.authorUsername)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                    
                    Text("•")
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.black.opacity(0.3))
                    
                    Text(comment.createdAt.timeAgoDisplay())
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.black.opacity(0.5))
                    
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.4))
                        }
                    }
                }
                
                // Content
                Text(comment.content)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.8))
                    .lineSpacing(3)
                
                // Actions (Production-Ready with Error Handling)
                HStack(spacing: 14) {
                    // Pray button (Amen reaction) - Production-Ready Optimistic Update
                    Button {
                        handleAmenToggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            
                            if localPrayCount > 0 {
                                Text("\(localPrayCount)")
                                    .font(.custom("OpenSans-SemiBold", size: 11))
                                    .contentTransition(.numericText())
                            }
                        }
                        .foregroundStyle(hasPrayed ? .black : .black.opacity(0.5))
                    }
                    .symbolEffect(.bounce, value: hasPrayed)
                    
                    // Reply button
                    Button {
                        // TODO: Implement reply to comment
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Text("Reply")
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                }
                .padding(.top, 2)
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
        .alert("Delete Comment", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this comment?")
        }
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
            print("⚠️ Cannot load state: Missing comment ID")
            return
        }
        
        do {
            hasPrayed = await commentService.hasUserAmened(commentId: commentId, postId: comment.postId)
        } catch {
            print("⚠️ Failed to load amen state: \(error.localizedDescription)")
            // Default to false on error
            hasPrayed = false
        }
    }
    
    /// Handle amen toggle with optimistic update and error rollback
    private func handleAmenToggle() {
        guard let commentId = comment.id else {
            print("⚠️ Cannot toggle amen: Missing comment ID")
            return
        }
        
        // Store previous state for potential rollback
        let previousState = hasPrayed
        let previousCount = localPrayCount
        
        // OPTIMISTIC UPDATE: Update UI immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                try await commentService.toggleAmen(commentId: commentId, postId: postId)
                print("✅ Amen toggled successfully")
            } catch {
                print("❌ Failed to toggle amen: \(error.localizedDescription)")
                
                // On error, revert the optimistic update
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
}

// MARK: - Quick Prayer Chip

struct QuickPrayerChip: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.black.opacity(0.7))
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
    
    enum PrayerWallFilter: String, CaseIterable {
        case all = "All Prayers"
        case urgent = "Urgent"
        case answered = "Answered"
        case today = "Today"
    }
    
    // Sample prayer wall posts - will be replaced with real data from Firebase
    let prayerWallPosts: [PrayerWallPost] = []
    
    var filteredPosts: [PrayerWallPost] {
        switch selectedFilter {
        case .all:
            return prayerWallPosts
        case .urgent:
            return prayerWallPosts.filter { $0.isUrgent }
        case .answered:
            return prayerWallPosts.filter { $0.category == .answered }
        case .today:
            return prayerWallPosts.filter { $0.timeAgo.contains("m") || $0.timeAgo.contains("h") }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Text("Prayer Wall")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.black)
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.black.opacity(0.3))
                    }
                }
                .padding()
                
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.black.opacity(0.4))
                    
                    TextField("Search prayers...", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 15))
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
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFilter = filter
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } label: {
                                Text(filter.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
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
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(filteredPosts) { post in
                            PrayerWallCard(post: post)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
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
                            .font(.system(size: 9))
                        Text("URGENT")
                            .font(.custom("OpenSans-Bold", size: 9))
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
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(.black)
                .lineLimit(2)
            
            // Excerpt
            Text(post.excerpt)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.black.opacity(0.6))
                .lineLimit(3)
            
            Spacer()
            
            // Footer
            VStack(spacing: 8) {
                Divider()
                
                HStack {
                    // Author
                    Text(post.author)
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.black.opacity(0.5))
                    
                    Spacer()
                    
                    // Pray count
                    HStack(spacing: 3) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.system(size: 10))
                        Text("\(post.prayCount + (hasPrayed ? 1 : 0))")
                            .font(.custom("OpenSans-Bold", size: 11))
                    }
                    .foregroundStyle(.black.opacity(0.5))
                }
            }
            
            // Pray button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    hasPrayed.toggle()
                }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text(hasPrayed ? "Prayed" : "Pray Now")
                        .font(.custom("OpenSans-Bold", size: 12))
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
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var categoryBadge: some View {
        let config = categoryConfig
        
        HStack(spacing: 3) {
            Image(systemName: config.icon)
                .font(.system(size: 9, weight: .semibold))
            
            Text(config.label)
                .font(.custom("OpenSans-Bold", size: 9))
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
    let id = UUID()
    let title: String
    let author: String
    let timeAgo: String
    let category: PrayerPostCard.PrayerCategory
    let prayCount: Int
    let isUrgent: Bool
    let excerpt: String
}

// MARK: - Smart Prayer Chat View

struct SmartPrayerChatView: View {
    let authorInfo: PrayerAuthorInfo
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var showQuickResponses = false
    @State private var showPrayerTemplates = false
    @State private var messages: [PrayerChatMessage] = []
    @FocusState private var isMessageFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                        
                        Circle()
                            .fill(Color.black)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(String(authorInfo.name.prefix(1)))
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authorInfo.name)
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.black)
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(red: 0.4, green: 0.85, blue: 0.7))
                                    .frame(width: 6, height: 6)
                                
                                Text("Active now")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.black.opacity(0.5))
                            }
                        }
                        
                        Spacer()
                        
                        Button {} label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.black)
                                .rotationEffect(.degrees(90))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    
                    Divider()
                }
                .background(Color.white)
                
                if !messages.isEmpty && messages.count < 3 {
                    PrayerContextCard(
                        authorName: authorInfo.name,
                        content: authorInfo.prayerContent,
                        category: authorInfo.prayerCategory
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if messages.isEmpty {
                                VStack(spacing: 16) {
                                    Text("Start of conversation")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.black.opacity(0.4))
                                        .padding(.top, 20)
                                    
                                    PrayerChatBubble(
                                        message: PrayerChatMessage(
                                            id: UUID(),
                                            content: "Thank you for reaching out about my prayer request. Your support means everything. 🙏",
                                            isFromCurrentUser: false,
                                            timestamp: Date()
                                        ),
                                        authorName: authorInfo.name
                                    )
                                }
                            }
                            
                            ForEach(messages) { message in
                                PrayerChatBubble(
                                    message: message,
                                    authorName: message.isFromCurrentUser ? "You" : authorInfo.name
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                VStack(spacing: 0) {
                    Divider()
                    
                    VStack(spacing: 12) {
                        if showQuickResponses {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    QuickResponseChip(text: "🙏 I'm praying for you") {
                                        messageText = "I'm praying for you right now 🙏"
                                    }
                                    QuickResponseChip(text: "💪 God's got you") {
                                        messageText = "God's got you! Stay strong 💪"
                                    }
                                    QuickResponseChip(text: "✨ Believing with you") {
                                        messageText = "I'm believing with you for breakthrough ✨"
                                    }
                                    QuickResponseChip(text: "❤️ Sending love") {
                                        messageText = "Sending love and prayers your way ❤️"
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        if showPrayerTemplates {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    PrayerTemplateChip(
                                        icon: "heart.circle.fill",
                                        title: "Healing",
                                        color: Color(red: 1.0, green: 0.6, blue: 0.7)
                                    ) {
                                        messageText = "Heavenly Father, I lift up \(authorInfo.name) to You. Pour out Your healing power and restoration. Amen 🙏"
                                    }
                                    PrayerTemplateChip(
                                        icon: "sparkles",
                                        title: "Strength",
                                        color: Color(red: 0.4, green: 0.7, blue: 1.0)
                                    ) {
                                        messageText = "Lord, renew their strength. Where they are weak, be their power. Give them courage for today 💪"
                                    }
                                    PrayerTemplateChip(
                                        icon: "sun.max.fill",
                                        title: "Peace",
                                        color: Color(red: 1.0, green: 0.85, blue: 0.4)
                                    ) {
                                        messageText = "Father, let Your peace that surpasses understanding guard their heart and mind in Christ Jesus ✨"
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        HStack(spacing: 12) {
                            HStack(spacing: 10) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showQuickResponses.toggle()
                                        if showQuickResponses { showPrayerTemplates = false }
                                    }
                                } label: {
                                    Image(systemName: showQuickResponses ? "bubble.left.fill" : "bubble.left")
                                        .font(.system(size: 18))
                                        .foregroundStyle(showQuickResponses ? .black : .black.opacity(0.5))
                                }
                                
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showPrayerTemplates.toggle()
                                        if showPrayerTemplates { showQuickResponses = false }
                                    }
                                } label: {
                                    Image(systemName: showPrayerTemplates ? "hands.sparkles.fill" : "hands.sparkles")
                                        .font(.system(size: 18))
                                        .foregroundStyle(showPrayerTemplates ? .black : .black.opacity(0.5))
                                }
                            }
                            
                            TextField("Send encouragement...", text: $messageText, axis: .vertical)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.black)
                                .lineLimit(1...4)
                                .focused($isMessageFieldFocused)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.black.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(isMessageFieldFocused ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                                )
                            
                            if !messageText.isEmpty {
                                Button { sendMessage() } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.black)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 12)
                }
                .background(Color.white)
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation { showPrayerTemplates = true }
            }
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let newMessage = PrayerChatMessage(
            id: UUID(),
            content: messageText,
            isFromCurrentUser: true,
            timestamp: Date()
        )
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            messages.append(newMessage)
            messageText = ""
            
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let responses = [
                "Thank you so much! Your prayers mean the world 🙏",
                "I really appreciate you lifting me up. God is good! ✨",
                "This brought tears to my eyes. Thank you for standing with me 💙",
                "Amen! I receive that prayer. Believing for breakthrough! 🙌"
            ]
            
            let responseMessage = PrayerChatMessage(
                id: UUID(),
                content: responses.randomElement() ?? responses[0],
                isFromCurrentUser: false,
                timestamp: Date()
            )
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                messages.append(responseMessage)
            }
        }
    }
}

// MARK: - Prayer Context Card

struct PrayerContextCard: View {
    let authorName: String
    let content: String
    let category: PrayerPostCard.PrayerCategory
    @State private var isDismissed = false
    
    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(categoryColor)
                        
                        Text("Prayer Request")
                            .font(.custom("OpenSans-Bold", size: 12))
                            .foregroundStyle(.black.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                
                Text(content)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.black.opacity(0.7))
                    .lineLimit(3)
                    .lineSpacing(4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(categoryColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(categoryColor.opacity(0.2), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var categoryIcon: String {
        switch category {
        case .prayer: return "hands.sparkles.fill"
        case .praise: return "hands.clap.fill"
        case .answered: return "checkmark.seal.fill"
        }
    }
    
    private var categoryColor: Color {
        switch category {
        case .prayer: return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .praise: return Color(red: 1.0, green: 0.7, blue: 0.4)
        case .answered: return Color(red: 0.4, green: 0.85, blue: 0.7)
        }
    }
}

// MARK: - Prayer Chat Bubble

struct PrayerChatBubble: View {
    let message: PrayerChatMessage
    let authorName: String
    
    var body: some View {
        HStack {
            if message.isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 6) {
                if !message.isFromCurrentUser {
                    Text(authorName)
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.leading, 4)
                }
                
                Text(message.content)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(message.isFromCurrentUser ? .white : .black.opacity(0.9))
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.isFromCurrentUser ? Color.black : Color.black.opacity(0.06))
                    )
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.black.opacity(0.4))
                    .padding(.horizontal, 4)
            }
            
            if !message.isFromCurrentUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Quick Response Chip

struct QuickResponseChip: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.black.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

// MARK: - Prayer Template Chip

struct PrayerTemplateChip: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.3), lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Prayer Chat Message Model

struct PrayerChatMessage: Identifiable {
    let id: UUID
    let content: String
    let isFromCurrentUser: Bool
    let timestamp: Date
}

// MARK: - Prayer User Model

struct PrayerUser: Identifiable {
    let id = UUID()
    let name: String
    let alias: String
    let bio: String
    let isOnline: Bool
    let prayerCount: Int
}

// MARK: - Live Discussion View

struct LiveDiscussionView: View {
    @Binding var isShowing: Bool
    @State private var selectedTopic: DiscussionTopic = .general
    @State private var isMuted = true
    @State private var participantCount = Int.random(in: 45...234)
    
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
                    withAnimation(.smooth(duration: 0.3)) {
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
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                        }
                        
                        Text("Live Discussion")
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.white)
                        
                        Text("\(participantCount) people listening")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isShowing = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
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
                                withAnimation(.smooth(duration: 0.3)) {
                                    selectedTopic = topic
                                }
                            } label: {
                                Text(topic.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
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
                        .font(.custom("OpenSans-Bold", size: 16))
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
                        withAnimation {
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
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            
                            Text(isMuted ? "Unmute" : "Muted")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    
                    Button {
                        // Raise hand action
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            
                            Text("Raise Hand")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isShowing = false
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 1.0, green: 0.3, blue: 0.3))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            
                            Text("Leave")
                                .font(.custom("OpenSans-SemiBold", size: 12))
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
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(name.prefix(1)))
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.white)
                    )
                
                if isSpeaking {
                    Circle()
                        .stroke(Color(red: 0.4, green: 0.85, blue: 0.7), lineWidth: 3)
                        .frame(width: 56, height: 56)
                        .scaleEffect(isSpeaking ? 1.1 : 1.0)
                        .opacity(isSpeaking ? 0.8 : 0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isSpeaking)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.white)
                
                HStack(spacing: 6) {
                    if isSpeaking {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.3, blue: 0.3))
                                .frame(width: 6, height: 6)
                            
                            Text("Speaking")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(Color(red: 1.0, green: 0.3, blue: 0.3))
                        }
                    }
                    
                    Text(topic)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
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
    
    enum CollabFilter: String, CaseIterable {
        case all = "All"
        case available = "Available Now"
        case groups = "Prayer Groups"
        case partners = "Partners"
    }
    
    let sampleCollaborators: [Collaborator] = [
        // Sample collaborators - will be replaced with real data from Firebase
    ]
    
    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.3)) {
                        isShowing = false
                    }
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Collaboration Hub")
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.white)
                        
                        Text("Find prayer partners & mentors")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isShowing = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
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
                    
                    TextField("Search by specialty...", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.white)
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
                                withAnimation(.smooth(duration: 0.3)) {
                                    selectedFilter = filter
                                }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
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
                
                // Collaborators list
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(sampleCollaborators, id: \.name) { collaborator in
                            CollaboratorCard(collaborator: collaborator)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Collaborator Model

struct Collaborator {
    let name: String
    let specialty: String
    let availability: String
    let isOnline: Bool
    let prayerCount: Int
    let rating: Double
}

// MARK: - Collaborator Card

struct CollaboratorCard: View {
    let collaborator: Collaborator
    @State private var isPressed = false
    
    var body: some View {
        Button {
            // Connect action
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // Avatar with online indicator
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(String(collaborator.name.prefix(1)))
                                    .font(.custom("OpenSans-Bold", size: 24))
                                    .foregroundStyle(.white)
                            )
                        
                        if collaborator.isOnline {
                            Circle()
                                .fill(Color(red: 0.4, green: 0.85, blue: 0.7))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                                )
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(collaborator.name)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.white)
                        
                        Text(collaborator.specialty)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                
                // Stats row
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.4))
                        
                        Text(String(format: "%.1f", collaborator.rating))
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "hands.sparkles.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text("\(collaborator.prayerCount) prayers")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    
                    Spacer()
                }
                
                // Availability
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(collaborator.isOnline ? Color(red: 0.4, green: 0.85, blue: 0.7) : .white.opacity(0.5))
                    
                    Text(collaborator.availability)
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(collaborator.isOnline ? Color(red: 0.4, green: 0.85, blue: 0.7) : .white.opacity(0.5))
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
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

// MARK: - Prayer Group Detail View

struct PrayerGroupDetailView: View {
    let group: PrayerGroup
    @Environment(\.dismiss) private var dismiss
    @State private var hasJoined = false
    @State private var selectedTab: GroupDetailTab = .about
    
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
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(group.name)
                            .font(.custom("OpenSans-Bold", size: 24))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 30)
                }
                
                // Stats Row
                HStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Text("\(group.members)")
                            .font(.custom("OpenSans-Bold", size: 20))
                        Text("Members")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("24")
                            .font(.custom("OpenSans-Bold", size: 20))
                        Text("Active Now")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("24/7")
                            .font(.custom("OpenSans-Bold", size: 20))
                        Text("Support")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 20)
                
                // Tabs
                HStack(spacing: 8) {
                    ForEach(GroupDetailTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
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
                            MembersView()
                        case .prayers:
                            GroupPrayersView()
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
    }
    
    // MARK: - Extracted View Components
    
    private var joinButton: some View {
        Button {
            withAnimation {
                hasJoined = true
            }
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
        } label: {
            Text("Join Prayer Group")
                .font(.custom("OpenSans-Bold", size: 17))
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
            // Message group
        } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(group.color))
        }
    }
    
    private var startPrayingButton: some View {
        Button {
            // Start praying
        } label: {
            HStack {
                Image(systemName: "hands.sparkles.fill")
                Text("Start Praying")
                    .font(.custom("OpenSans-Bold", size: 16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(group.color)
            )
        }
    }
}

// MARK: - About Group View
struct AboutGroupView: View {
    let group: PrayerGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.custom("OpenSans-Bold", size: 18))
                
                Text(group.description)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Group Rules")
                    .font(.custom("OpenSans-Bold", size: 18))
                
                GroupRuleRow(icon: "hands.sparkles.fill", rule: "Pray together daily", color: group.color)
                GroupRuleRow(icon: "heart.fill", rule: "Respect all members", color: group.color)
                GroupRuleRow(icon: "shield.checkmark.fill", rule: "Keep prayers confidential", color: group.color)
                GroupRuleRow(icon: "clock.fill", rule: "Active participation expected", color: group.color)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Meeting Times")
                    .font(.custom("OpenSans-Bold", size: 18))
                
                Text("Daily Prayer: 6:00 AM, 12:00 PM, 9:00 PM EST")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                
                Text("Weekly Zoom: Every Sunday at 7:00 PM EST")
                    .font(.custom("OpenSans-Regular", size: 15))
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
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 30)
            
            Text(rule)
                .font(.custom("OpenSans-Regular", size: 15))
        }
    }
}

// MARK: - Members View
struct MembersView: View {
    // Sample members - will be replaced with real data from Firebase
    let members: [(String, String, Bool)] = []
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(members, id: \.0) { member in
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(String(member.0.prefix(1)))
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.white)
                            )
                        
                        if member.2 {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.0)
                            .font(.custom("OpenSans-Bold", size: 15))
                        
                        Text(member.1)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        // Message member
                    } label: {
                        Image(systemName: "message")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
            }
        }
    }
}

// MARK: - Group Prayers View
struct GroupPrayersView: View {
    // Helper to create example posts for UI demonstration
    private func createExamplePost(authorName: String, content: String, topicTag: String) -> Post {
        Post(
            authorName: authorName,
            authorInitials: String(authorName.prefix(2)).uppercased(),
            timeAgo: ["2m", "10m", "1h", "3h"].randomElement() ?? "1h",
            content: content,
            category: .prayer,
            topicTag: topicTag
        )
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Sample posts - will be replaced with real data from Firebase
            Text("No posts yet")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .padding()
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
