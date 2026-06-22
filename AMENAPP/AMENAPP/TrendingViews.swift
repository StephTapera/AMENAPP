import SwiftUI
// MARK: - Premium Trending Card (Smaller & Refined)

struct SmartTrendingCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let backgroundColor: Color
    
    @State private var isPressed = false
    @State private var showDetails = false
    
    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) {
                showDetails = true
            }
            
            HapticManager.impact(style: .light)
        } label: {
            HStack(spacing: 16) {
                // Premium Icon with Glass Effect
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    iconColor.opacity(0.2),
                                    iconColor.opacity(0.05),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 30
                            )
                        )
                        .frame(width: 60, height: 60)
                        .blur(radius: 8)
                    
                    // Glass circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.4),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: iconColor.opacity(0.3), radius: 12, y: 6)
                    
                    Image(systemName: icon)
                        .font(.systemScaled(22, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isPressed)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AMENFont.bold(17))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.white.opacity(0.85))
                }
                
                Spacer()
                
                // Premium Arrow
                Image(systemName: "arrow.right")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // Premium gradient background
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    backgroundColor,
                                    backgroundColor.opacity(0.85)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Glass overlay
                    RoundedRectangle(cornerRadius: 20)
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
                    
                    // Premium border
                    RoundedRectangle(cornerRadius: 20)
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
                }
            )
            .shadow(color: backgroundColor.opacity(0.3), radius: 16, y: 8)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.smooth(duration: 0.2)) {
                isPressed = pressing
            }
        }, perform: {})
        .sheet(isPresented: $showDetails) {
            TrendingTopicDetailView(title: title, icon: icon)
        }
    }
}

// MARK: - Top Ideas View

struct TopIdeasView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var trendingService = TrendingService.shared
    @ObservedObject private var filteringService = SmartIdeaFilteringService.shared
    @State private var selectedTimeframe: IdeaTimeframe = .week
    @State private var selectedCategory: TopIdea.IdeaCategory = .all
    @State private var showFilters = false
    
    enum IdeaTimeframe: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case allTime = "All Time"
        
        var timeInterval: TimeInterval {
            switch self {
            case .today: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .month: return 30 * 24 * 3600
            case .allTime: return 365 * 24 * 3600
            }
        }
    }
    
    var filteredTopIdeas: [TopIdea] {
        // Use smart filtering algorithm for accurate categorization
        filteringService.filterIdeas(
            trendingService.topIdeas,
            category: selectedCategory,
            timeframe: selectedTimeframe.timeInterval,
            minEngagement: 0
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Top Ideas")
                                    .font(AMENFont.bold(32))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.black, .black.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                
                                Text("The brightest ideas from our community")
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.yellow.opacity(0.3),
                                                Color.orange.opacity(0.1)
                                            ],
                                            center: .center,
                                            startRadius: 5,
                                            endRadius: 30
                                        )
                                    )
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "lightbulb.fill")
                                    .font(.systemScaled(40, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .symbolEffect(.pulse, options: .repeating)
                            }
                        }
                        
                        // Timeframe Selector
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(IdeaTimeframe.allCases, id: \.self) { timeframe in
                                    Button {
                                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                            selectedTimeframe = timeframe
                                        }
                                        Task {
                                            try? await trendingService.fetchTopIdeas(
                                                timeframe: timeframe.timeInterval,
                                                category: selectedCategory
                                            )
                                        }
                                    } label: {
                                        Text(timeframe.rawValue)
                                            .font(AMENFont.semiBold(13))
                                            .foregroundStyle(selectedTimeframe == timeframe ? .white : .primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(
                                                        selectedTimeframe == timeframe ? 
                                                            LinearGradient(
                                                                colors: [Color.yellow.opacity(0.9), Color.orange.opacity(0.9)],
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            ) :
                                                            LinearGradient(
                                                                colors: [Color.gray.opacity(0.15)],
                                                                startPoint: .top,
                                                                endPoint: .bottom
                                                            )
                                                    )
                                                    .shadow(
                                                        color: selectedTimeframe == timeframe ? Color.yellow.opacity(0.3) : .clear,
                                                        radius: 8,
                                                        y: 4
                                                    )
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Category Filter
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TopIdea.IdeaCategory.allCases, id: \.self) { category in
                                    Button {
                                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                            selectedCategory = category
                                        }
                                        Task {
                                            try? await trendingService.fetchTopIdeas(
                                                timeframe: selectedTimeframe.timeInterval,
                                                category: category
                                            )
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: category.icon)
                                                .font(.systemScaled(10, weight: .semibold))
                                            
                                            Text(category.rawValue)
                                                .font(AMENFont.semiBold(12))
                                        }
                                        .foregroundStyle(selectedCategory == category ? .white : category.color)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    selectedCategory == category ?
                                                        category.color :
                                                        category.color.opacity(0.12)
                                                )
                                                .shadow(
                                                    color: selectedCategory == category ? category.color.opacity(0.3) : .clear,
                                                    radius: 6,
                                                    y: 3
                                                )
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(
                                                    selectedCategory == category ? Color.clear : category.color.opacity(0.3),
                                                    lineWidth: 1
                                                )
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Ideas List
                    if trendingService.isLoading {
                        VStack(spacing: 12) {
                            AMENLoadingIndicator()
                            Text("Finding the brightest ideas...")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if filteredTopIdeas.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "lightbulb.slash")
                                .font(.systemScaled(48))
                                .foregroundStyle(.secondary)
                            Text("No featured ideas yet")
                                .font(AMENFont.bold(18))
                            Text("Be the first to share a brilliant idea!")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(filteredTopIdeas) { idea in
                                TopIdeaCard(idea: idea)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                }
            }
            .task {
                // Fetch top ideas when view appears
                try? await trendingService.fetchTopIdeas(
                    timeframe: selectedTimeframe.timeInterval,
                    category: selectedCategory
                )
            }
        }
    }
    
    // MARK: - Community Covenant Check
    /*
    private func checkCovenantAgreement() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let doc = try await Firestore.firestore()
                .collection("users").document(userId)
                .collection("communityStandards").document("agreement")
                .getDocument()
            
            if !doc.exists {
                await MainActor.run {
                    needsCovenantAgreement = true
                    // Delay showing to avoid conflicting with welcome screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        showCommunityCovenant = true
                    }
                }
            } else {
                // Check if re-affirmation needed (90 days)
                if let nextReaffirmation = (doc.data()?["nextReaffirmation"] as? Timestamp)?.dateValue() {
                    if Date() > nextReaffirmation {
                        await MainActor.run {
                            needsCovenantAgreement = true
                            showCommunityCovenant = true
                        }
                    }
                }
            }
        } catch {
            dlog("❌ Failed to check covenant agreement: \(error)")
        }
    }
    */
}

// MARK: - Top Idea Model (Now in TrendingService.swift)

// MARK: - Top Idea Card

struct TopIdeaCard: View {
    let idea: TopIdea
    @State private var hasLightbulbed = false
    @State private var localLightbulbCount: Int
    @State private var showComments = false
    @State private var isAnimating = false
    @Namespace private var glassNamespace
    
    init(idea: TopIdea) {
        self.idea = idea
        _localLightbulbCount = State(initialValue: idea.lightbulbCount)
    }
    
    // Rank gradient computed property
    private var rankGradient: LinearGradient {
        switch idea.rank {
        case 1:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.65, blue: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 2:
            return LinearGradient(
                colors: [Color(red: 0.75, green: 0.75, blue: 0.75), Color(red: 0.5, green: 0.5, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 3:
            return LinearGradient(
                colors: [Color(red: 0.8, green: 0.5, blue: 0.2), Color(red: 0.6, green: 0.3, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Rank Badge
            HStack {
                ZStack {
                    Circle()
                        .fill(rankGradient)
                        .frame(width: 40, height: 40)
                    
                    Text("#\(idea.rank)")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.authorName)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                    
                    Text(idea.timeAgo)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Badges
                HStack(spacing: 4) {
                    ForEach(idea.badges, id: \.self) { badge in
                        Text(badge)
                            .font(AMENFont.semiBold(10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                    }
                }
            }
            
            // Content
            Text(idea.content)
                .font(AMENFont.regular(15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Interactive Reactions
            GlassEffectContainer {
                HStack(spacing: 12) {
                    // Lightbulb Reaction with Animation
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.5))) {
                            hasLightbulbed.toggle()
                            localLightbulbCount += hasLightbulbed ? 1 : -1
                            isAnimating = true
                        }
                        
                        HapticManager.impact(style: hasLightbulbed ? .heavy : .light)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            isAnimating = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack {
                                // Glow effect when active
                                if hasLightbulbed {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.systemScaled(16, weight: .bold))
                                        .foregroundStyle(.yellow)
                                        .blur(radius: 8)
                                        .scaleEffect(isAnimating ? 1.5 : 1.0)
                                        .opacity(isAnimating ? 0 : 0.6)
                                }
                                
                                Image(systemName: hasLightbulbed ? "lightbulb.fill" : "lightbulb")
                                    .font(.systemScaled(16, weight: .semibold))
                                    .foregroundStyle(hasLightbulbed ? 
                                        LinearGradient(
                                            colors: [.yellow, .orange],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ) :
                                        LinearGradient(
                                            colors: [.black.opacity(0.5), .black.opacity(0.5)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                                    .rotationEffect(.degrees(isAnimating ? 15 : 0))
                            }
                            
                            Text("\(localLightbulbCount)")
                                .font(AMENFont.semiBold(13))
                                .foregroundStyle(hasLightbulbed ? .orange : .black.opacity(0.5))
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(hasLightbulbed ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.1))
                                
                                if hasLightbulbed {
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.yellow, .orange],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1.5
                                        )
                                }
                            }
                        )
                    }
                    
                    // Comment Button
                    ReactionButton(
                        icon: "bubble.left.fill",
                        count: idea.commentCount,
                        isActive: showComments,
                        activeColor: .blue,
                        namespace: glassNamespace
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            showComments.toggle()
                        }
                    }
                    
                    Spacer()
                    
                    // Share Button
                    Button {
                        // Share action
                        HapticManager.impact(style: .light)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(14, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.5))
                            .padding(8)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
    }
}

// MARK: - Notification Badge Component

struct NotificationBadge: View {
    let count: Int
    let pulse: Bool
    
    var body: some View {
        ZStack {
            // Pulse circle background (appears when new notification arrives)
            if pulse {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulse ? 1.5 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.6), value: pulse)
            }
            
            // Main badge
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.red, Color.red.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: max(14, count > 9 ? 18 : 14), height: max(14, 14))
                .shadow(color: .red.opacity(0.5), radius: 4, x: 0, y: 2)
            
            if count <= 99 {
                Text("\(count)")
                    .font(.systemScaled(count > 9 ? 8 : 9, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            } else {
                Text("99+")
                    .font(.systemScaled(7, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .scaleEffect(pulse ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulse)
        .transition(.scale.combined(with: .opacity))
    }
}
