//
//  ResourcesView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI

struct ResourcesView: View {
    @State private var searchText = ""
    @State private var selectedCategory: ResourceCategory = .all
    @State private var dailyVerse: DailyVerse = .sample
    @State private var bibleFact: BibleFact = .sample
    @State private var isRefreshingVerse = false
    @State private var isRefreshingFact = false
    
    enum ResourceCategory: String, CaseIterable {
        case all = "All"
        case reading = "Reading"
        case listening = "Listening"
        case community = "Community"
        case tools = "Tools"
        case learning = "Learning"
    }
    
    var filteredResources: [ResourceItem] {
        guard selectedCategory != .all else {
            return allResources
        }
        return allResources.filter { $0.category == selectedCategory.rawValue }
    }
    
    var searchFilteredResources: [ResourceItem] {
        guard !searchText.isEmpty else {
            return filteredResources
        }
        return filteredResources.filter { resource in
            resource.title.localizedCaseInsensitiveContains(searchText) ||
            resource.description.localizedCaseInsensitiveContains(searchText) ||
            resource.category.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header that stays at top
                headerView
                
                ScrollView {
                    contentView
                }
            }
            .navigationBarHidden(true)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: searchFilteredResources.count)
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Resources")
                    .font(.custom("OpenSans-Bold", size: 34))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Active filters badge
                if selectedCategory != .all || !searchText.isEmpty {
                    activeFiltersBadge
                }
            }
            .padding(.horizontal)
            
            searchBarView
            categoryPillsView
        }
        .padding(.top)
        .background(Color(.systemBackground))
    }
    
    private var activeFiltersBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 14))
            Text("\(searchFilteredResources.count)")
                .font(.custom("OpenSans-Bold", size: 14))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.blue)
        )
        .transition(.scale.combined(with: .opacity))
    }
    
    private var searchBarView: some View {
        HStack(spacing: 14) {
            // Circular icon container with glass effect
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
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
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .scaleEffect(searchText.isEmpty ? 1.0 : 1.1)
                    .symbolEffect(.bounce, value: searchText.isEmpty)
            }
            
            // Text field with custom styling
            TextField("Search", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 17))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
            
            // Clear button with glass effect
            if !searchText.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        searchText = ""
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            ZStack {
                // Glass background
                Capsule()
                    .fill(.ultraThinMaterial)
                
                // Subtle gradient overlay
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Border with gradient
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(searchText.isEmpty ? 0.2 : 0.4),
                                Color.white.opacity(searchText.isEmpty ? 0.1 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: searchText.isEmpty)
    }
    
    private var categoryPillsView: some View {
        LiquidGlassSegmentedControl(
            selection: $selectedCategory,
            categories: ResourceCategory.allCases
        )
        .padding(.horizontal)
    }
    
    // MARK: - Content View
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 20) {
                    
                    // Daily Bible Verse Card
                    DailyVerseCard(verse: dailyVerse, isRefreshing: $isRefreshingVerse) {
                        refreshDailyVerse()
                    }
                    
                    // Fun Bible Fact Card
                    BibleFactCard(fact: bibleFact, isRefreshing: $isRefreshingFact) {
                        refreshBibleFact()
                    }
                    
                    // AMEN | Connect Section with Banners
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("AMEN | Connect")
                                .font(.custom("OpenSans-Bold", size: 20))
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .symbolEffect(.bounce, value: selectedCategory)
                        }
                        .padding(.horizontal)
                        
                        // Private Communities - Featured Banner
                        NavigationLink(destination: PrivateCommunitiesView()) {
                            FeaturedCommunityBanner()
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Christian Dating - Compact Banner
                        ChristianDatingBannerButton()
                        
                        // Find Friends - Compact Banner
                        FindFriendsBannerButton()
                        
                        // Find a Local Church - Smaller Banner
                        NavigationLink(destination: FindChurchView()) {
                            CompactConnectBanner(
                                icon: "building.2.fill",
                                iconColor: .white,
                                title: "Find a Local Church",
                                subtitle: "Connect with your faith community",
                                badge: nil,
                                gradientColors: [Color.blue, Color.purple]
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Church Notes - Last, Smaller Banner
                        NavigationLink(destination: ChurchNotesView()) {
                            CompactConnectBanner(
                                icon: "note.text",
                                iconColor: .white,
                                title: "Church Notes",
                                subtitle: "Premium - Take notes & share",
                                badge: "Premium",
                                gradientColors: [Color.orange, Color.pink]
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Faith Apps & Tools
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Faith Apps & Tools")
                                .font(.custom("OpenSans-Bold", size: 20))
                            Image(systemName: "app.badge.fill")
                                .foregroundStyle(.blue)
                                .symbolEffect(.pulse, options: .repeating, value: selectedCategory)
                        }
                        .padding(.horizontal)
                        
                        // Bible App Integration
                        BibleAppCard()
                        
                        // Pray.com Integration
                        PrayComCard()
                        
                        // Essential Books (implemented)
                        NavigationLink(destination: EssentialBooksView()) {
                            ResourceCard(
                                icon: "book.pages.fill",
                                iconColor: .green,
                                title: "Essential Books",
                                description: "Foundational reading for new Christians",
                                category: "Reading"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Recommended Sermons (implemented)
                        NavigationLink(destination: RecommendedSermonsView()) {
                            ResourceCard(
                                icon: "mic.fill",
                                iconColor: .red,
                                title: "Recommended Sermons",
                                description: "Powerful messages to strengthen your faith",
                                category: "Listening"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Faith Podcasts (implemented)
                        NavigationLink(destination: FaithPodcastsView()) {
                            ResourceCard(
                                icon: "headphones",
                                iconColor: .purple,
                                title: "Faith Podcasts",
                                description: "Grow on-the-go with inspiring podcasts",
                                category: "Listening"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Faith & Tech (implemented)
                        NavigationLink(destination: FaithTechView()) {
                            ResourceCard(
                                icon: "lightbulb.fill",
                                iconColor: .orange,
                                title: "Faith & Technology",
                                description: "Navigating tech with biblical wisdom",
                                category: "Learning"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Smart Resources Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Smart Resources")
                                .font(.custom("OpenSans-Bold", size: 20))
                            Image(systemName: "brain.fill")
                                .foregroundStyle(.cyan)
                                .symbolEffect(.variableColor, options: .repeating, value: selectedCategory)
                        }
                        .padding(.horizontal)
                        
                        if searchFilteredResources.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(searchFilteredResources) { resource in
                                ResourceCard(
                                    icon: resource.icon,
                                    iconColor: resource.iconColor,
                                    title: resource.title,
                                    description: resource.description,
                                    category: resource.category
                                )
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
    
    private func refreshDailyVerse() {
        Task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isRefreshingVerse = true
            }
            
            // First, try to load from cache (instant!)
            if let cachedVerse = CacheManager.shared.loadCachedDailyVerse() {
                await MainActor.run {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        dailyVerse = cachedVerse
                        isRefreshingVerse = false
                    }
                }
                return // Use cached verse, no need to fetch
            }
            
            do {
                // Call Bible API for real verse
                let verse = try await BibleAPIService.shared.getVerseOfTheDay()
                
                // Cache the verse for today
                let dailyVerse = DailyVerse(text: verse.text, reference: verse.reference)
                CacheManager.shared.saveDailyVerse(dailyVerse)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        self.dailyVerse = dailyVerse
                        isRefreshingVerse = false
                    }
                }
            } catch {
                print("❌ Bible API Error: \(error.localizedDescription)")
                
                // Fallback to sample verses if API fails
                await MainActor.run {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        dailyVerse = DailyVerse.random()
                        isRefreshingVerse = false
                    }
                }
            }
        }
    }
    
    private func refreshBibleFact() {
        Task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isRefreshingFact = true
            }
            
            // Try to get AI-generated fact first
            do {
                let aiFact = try await BereanGenkitService.shared.generateFunBibleFact(category: nil)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        bibleFact = BibleFact(text: aiFact)
                        isRefreshingFact = false
                    }
                }
                
                print("✅ AI-generated Bible fact loaded")
                
            } catch {
                print("⚠️ AI fact generation failed, using fallback: \(error.localizedDescription)")
                
                // Fallback to static random facts if AI fails
                await MainActor.run {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        bibleFact = BibleFact.random()
                        isRefreshingFact = false
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: searchText.isEmpty ? "tray.fill" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
                .symbolEffect(.pulse, options: .repeating)
            
            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No resources in this category" : "No results found")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text(searchText.isEmpty ? 
                     "Try selecting 'All' to see all resources" : 
                     "Try adjusting your search or filter")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if !searchText.isEmpty || selectedCategory != .all {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        searchText = ""
                        selectedCategory = .all
                    }
                } label: {
                    Text("Clear Filters")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                        )
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal)
    }
}

// MARK: - Daily Verse Card
struct DailyVerseCard: View {
    let verse: DailyVerse
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Bible Verse")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(verse.reference)
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.blue)
                } else {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Text(verse.text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .opacity(isRefreshing ? 0.5 : 1.0)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(verse.id)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRefreshing)
    }
}

// MARK: - Bible Fact Card
struct BibleFactCard: View {
    let fact: BibleFact
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, value: fact.id)
                    
                    Text("Fun Bible Fact")
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(.linear(duration: 1).repeatCount(isRefreshing ? 100 : 0, autoreverses: false), value: isRefreshing)
                }
                .disabled(isRefreshing)
            }
            
            Text(fact.text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(fact.id)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.1), Color.yellow.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

// MARK: - Featured Banner with Liquid Glass Spatial Aesthetic
struct FeaturedBanner: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let gradientColors: [Color]
    
    @State private var shimmerPhase: CGFloat = 0
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [iconColor.opacity(0.6), iconColor.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.pulse, options: .repeating.speed(0.7))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
            }
            
            Text(description)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
            
            HStack {
                Spacer()
                
                HStack(spacing: 6) {
                    Text("Explore Now")
                        .font(.custom("OpenSans-Bold", size: 14))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.4), lineWidth: 1.5)
                        )
                )
            }
        }
        .padding(20)
        .background(
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Glass overlay
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
                
                // Shimmer effect
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.2),
                        Color.white.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: shimmerPhase)
                .blur(radius: 30)
                
                // Noise texture for depth
                Rectangle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.05), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 300
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: gradientColors[0].opacity(0.3), radius: 20, x: 0, y: 10)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                shimmerPhase = 400
            }
        }
    }
}

// MARK: - Liquid Glass Connect Card with Advanced Features
struct LiquidGlassConnectCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let category: String
    let badge: String?
    let features: [String]
    
    @State private var isPressed = false
    @State private var isExpanded = false
    @State private var showOnboarding = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // Icon with glass effect
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: icon)
                            .font(.system(size: 24))
                            .foregroundStyle(iconColor)
                            .symbolEffect(.bounce, value: isExpanded)
                    }
                    .glassEffect(.regular)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundStyle(.primary)
                            
                            if let badge = badge {
                                badgeView(badge: badge)
                            }
                        }
                        
                        Text(description)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                
                // Expandable Features Section
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                            .transition(.opacity)
                        
                        ForEach(features, id: \.self) { feature in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(iconColor)
                                
                                Text(feature)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.primary)
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        
                        Button {
                            showOnboarding = true
                        } label: {
                            HStack {
                                Spacer()
                                
                                getStartedButton
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.top, 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
            )
            .glassEffect(.regular)
            .shadow(color: iconColor.opacity(isPressed ? 0.2 : 0.15), radius: isPressed ? 6 : 12, y: isPressed ? 2 : 4)
            .padding(.horizontal)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            }
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
            .sheet(isPresented: $showOnboarding) {
                if title == "Christian Dating" {
                    ChristianDatingOnboardingView()
                } else if title == "Find Friends" {
                    FindFriendsOnboardingView()
                }
            }
    }
    
    // Helper views to reduce complexity
    @ViewBuilder
    private func badgeView(badge: String) -> some View {
        Text(badge)
            .font(.custom("OpenSans-Bold", size: 10))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(iconColor)
            )
    }
    
    private var getStartedButton: some View {
        HStack(spacing: 6) {
            Text("Get Started")
                .font(.custom("OpenSans-Bold", size: 14))
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 16))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(iconColor)
        )
        .shadow(color: iconColor.opacity(0.3), radius: 8, y: 2)
    }
}

struct ResourceCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let category: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                Text(category)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(iconColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(iconColor.opacity(0.1))
                    )
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
        .padding(.horizontal)
    }
}

// MARK: - Bible App Integration Card

struct BibleAppCard: View {
    @State private var showAlert = false
    
    var body: some View {
        Button {
            openBibleApp()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "book.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Bible App")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        Text("YOUVERSION")
                            .font(.custom("OpenSans-Bold", size: 10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                    
                    Text("Read, study, and share scripture")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text("External App")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .alert("Open Bible App?", isPresented: $showAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open App Store") {
                openAppStore(appID: "id282935706") // YouVersion Bible App
            }
            Button("Try Opening") {
                if let url = URL(string: "bible://") {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("This will open the YouVersion Bible app if installed, or take you to the App Store.")
        }
    }
    
    private func openBibleApp() {
        // Try to open the Bible app using its URL scheme
        if let url = URL(string: "bible://") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // If app not installed, show alert
                showAlert = true
            }
        }
    }
    
    private func openAppStore(appID: String) {
        if let url = URL(string: "https://apps.apple.com/app/\(appID)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Pray.com Integration Card

struct PrayComCard: View {
    @State private var showAlert = false
    
    var body: some View {
        Button {
            openPrayApp()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Pray.com")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.primary)
                        
                        Text("FEATURED")
                            .font(.custom("OpenSans-Bold", size: 10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.purple)
                            )
                    }
                    
                    Text("Guided prayers, sleep stories, and worship")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text("External App")
                        .font(.custom("OpenSans-SemiBold", size: 11))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.1))
                        )
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.purple)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
        .alert("Open Pray.com?", isPresented: $showAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open App Store") {
                openAppStore(appID: "id1447106941") // Pray.com app
            }
        } message: {
            Text("This will take you to the App Store to download Pray.com.")
        }
    }
    
    private func openPrayApp() {
        // Pray.com doesn't have a public URL scheme, so go to App Store
        showAlert = true
    }
    
    private func openAppStore(appID: String) {
        if let url = URL(string: "https://apps.apple.com/app/\(appID)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Placeholder Resource View
struct PlaceholderResourceView: View {
    let title: String
    let description: String
    let icon: String
    let iconColor: Color
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 40)
                
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [iconColor.opacity(0.3), iconColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(iconColor)
                }
                
                VStack(spacing: 12) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Coming Soon")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    
                    Text("This feature is currently under development. Check back soon for updates!")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(iconColor.opacity(0.1))
                )
                .padding(.horizontal)
                
                Spacer()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data Models
struct DailyVerse: Identifiable {
    let id = UUID()
    let text: String
    let reference: String
    
    static let sample = DailyVerse(
        text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.",
        reference: "John 3:16"
    )
    
    static func random() -> DailyVerse {
        let verses = [
            DailyVerse(text: "Trust in the Lord with all your heart and lean not on your own understanding.", reference: "Proverbs 3:5"),
            DailyVerse(text: "I can do all things through Christ who strengthens me.", reference: "Philippians 4:13"),
            DailyVerse(text: "The Lord is my shepherd; I shall not want.", reference: "Psalm 23:1"),
            DailyVerse(text: "Be still, and know that I am God.", reference: "Psalm 46:10"),
            DailyVerse(text: "And we know that in all things God works for the good of those who love him.", reference: "Romans 8:28")
        ]
        return verses.randomElement() ?? sample
    }
}

struct BibleFact: Identifiable {
    let id = UUID()
    let text: String
    
    static let sample = BibleFact(
        text: "The Bible was written over approximately 1,500 years by more than 40 different authors from various backgrounds!"
    )
    
    static func random() -> BibleFact {
        let facts = [
            BibleFact(text: "The longest verse in the Bible is Esther 8:9 with 90 words in English."),
            BibleFact(text: "The Bible has been translated into over 3,000 languages!"),
            BibleFact(text: "The word 'Christian' appears only 3 times in the entire Bible."),
            BibleFact(text: "The shortest verse in the Bible is 'Jesus wept.' - John 11:35"),
            BibleFact(text: "Psalm 117 is the shortest chapter in the Bible with only 2 verses."),
            BibleFact(text: "The Bible was the first book ever printed on the Gutenberg press in 1455.")
        ]
        return facts.randomElement() ?? sample
    }
}

struct ResourceItem: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let category: String
}

// MARK: - Resource Data (Cleaned - Only Implemented Features)
let allResources: [ResourceItem] = [
    // Articles & Guides
    ResourceItem(
        icon: "newspaper.fill",
        iconColor: .blue,
        title: "Faith Articles",
        description: "Curated articles on faith, culture, and technology",
        category: "Reading"
    ),
    ResourceItem(
        icon: "book.closed.fill",
        iconColor: .indigo,
        title: "Study Guides",
        description: "In-depth Bible study resources and guides",
        category: "Reading"
    ),
    
    // Community Features (implemented via banners)
    ResourceItem(
        icon: "person.2.fill",
        iconColor: .green,
        title: "Christian Community",
        description: "Connect with believers in your area",
        category: "Community"
    ),
    
    // Digital Tools
    ResourceItem(
        icon: "app.badge.fill",
        iconColor: .purple,
        title: "Recommended Apps",
        description: "Top Christian apps for your spiritual journey",
        category: "Tools"
    )
]

// MARK: - Compact Connect Banner (Smaller, Streamlined)

struct CompactConnectBanner: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String?
    let gradientColors: [Color]
    
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [iconColor.opacity(0.6), iconColor.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.white)
                    
                    if let badge = badge {
                        Text(badge)
                            .font(.custom("OpenSans-Bold", size: 9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.3))
                            )
                    }
                }
                
                Text(subtitle)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(16)
        .background(
            ZStack {
                // Base gradient
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Glass overlay
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.25)
                
                // Shimmer effect
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
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: gradientColors[0].opacity(0.25), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                shimmerPhase = 400
            }
        }
    }
}

// MARK: - Liquid Glass Segmented Control with Morph + Slide

struct LiquidGlassSegmentedControl: View {
    @Binding var selection: ResourcesView.ResourceCategory
    let categories: [ResourcesView.ResourceCategory]
    
    @Namespace private var segmentAnimation
    @State private var sizes: [ResourcesView.ResourceCategory: CGSize] = [:]
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { category in
                    segmentButton(for: category)
                }
            }
            .padding(6)
            .background(
                ZStack {
                    // Liquid glass background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                    
                    // Glass highlight overlay
                    RoundedRectangle(cornerRadius: 16)
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
                    
                    // Border
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
    }
    
    @ViewBuilder
    private func segmentButton(for category: ResourcesView.ResourceCategory) -> some View {
        let isSelected = selection == category
        
        Button {
            selectCategory(category)
        } label: {
            Text(category.rawValue)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            // Morphing selected capsule with matched geometry
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black,
                                            Color.black.opacity(0.9)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    // Glass shine on selected
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.2),
                                                    Color.white.opacity(0)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .center
                                            )
                                        )
                                )
                                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                                .matchedGeometryEffect(
                                    id: "selectedSegment",
                                    in: segmentAnimation,
                                    properties: .frame,
                                    isSource: true
                                )
                                // Springy scale morph
                                .scaleEffect(isAnimating ? 1.05 : 1.0)
                        }
                    }
                )
                // Smooth color cross-fade
                .animation(.easeInOut(duration: 0.25), value: isSelected)
        }
        .buttonStyle(SegmentButtonStyle())
    }
    
    private func selectCategory(_ category: ResourcesView.ResourceCategory) {
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Trigger springy scale animation
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            isAnimating = true
            selection = category
        }
        
        // Reset scale after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isAnimating = false
            }
        }
    }
}

// MARK: - Segment Button Style

struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Christian Dating Banner Button (Coming Soon)

struct ChristianDatingBannerButton: View {
    @State private var showComingSoon = false
    
    var body: some View {
        Button {
            showComingSoon = true
        } label: {
            CompactConnectBanner(
                icon: "heart.text.square.fill",
                iconColor: .pink,
                title: "Christian Dating",
                subtitle: "Find your match in faith",
                badge: "Coming Soon",
                gradientColors: [Color.pink, Color.red]
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showComingSoon) {
            ResourceComingSoonPlaceholder(
                title: "Christian Dating",
                icon: "heart.text.square.fill",
                iconColor: .pink,
                description: "Meet fellow believers looking for meaningful relationships built on shared faith and values. Our Christian dating feature will help you find your match in Christ."
            )
        }
    }
}

// MARK: - Find Friends Banner Button (Coming Soon)

struct FindFriendsBannerButton: View {
    @State private var showComingSoon = false
    
    var body: some View {
        Button {
            showComingSoon = true
        } label: {
            CompactConnectBanner(
                icon: "person.2.fill",
                iconColor: .blue,
                title: "Find Friends",
                subtitle: "Build meaningful connections",
                badge: "Coming Soon",
                gradientColors: [Color.blue, Color.cyan]
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showComingSoon) {
            ResourceComingSoonPlaceholder(
                title: "Find Friends",
                icon: "person.2.fill",
                iconColor: .blue,
                description: "Connect with fellow believers in your area. Build authentic friendships rooted in faith through shared interests, Bible studies, and community activities."
            )
        }
    }
}

// MARK: - Featured Community Banner
struct FeaturedCommunityBanner: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Hero section with animated gradient
            ZStack {
                // Animated gradient background
                LinearGradient(
                    colors: [
                        Color.purple,
                        Color.blue,
                        Color.cyan
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .hueRotation(.degrees(isAnimating ? 30 : 0))
                .animation(
                    Animation.easeInOut(duration: 3)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
                
                // Overlay pattern
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.15))
                        Spacer()
                    }
                    .padding(20)
                }
                
                // Content
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.yellow)
                                
                                Text("NEW")
                                    .font(.custom("OpenSans-Bold", size: 12))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(.white.opacity(0.2))
                                    )
                            }
                            
                            Text("Private Communities")
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.white)
                            
                            Text("Join your church, university, or organization")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(2)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            // Quick stats bar
            HStack(spacing: 0) {
                CommunityStatBadge(icon: "graduationcap.fill", text: "Universities", color: .blue)
                
                Divider()
                    .frame(height: 20)
                
                CommunityStatBadge(icon: "building.2.fill", text: "Churches", color: .purple)
                
                Divider()
                    .frame(height: 20)
                
                CommunityStatBadge(icon: "person.3.fill", text: "Organizations", color: .cyan)
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .offset(y: -8)
        }
        .padding(.horizontal, 20)
        .shadow(color: .purple.opacity(0.3), radius: 20, y: 10)
        .onAppear {
            isAnimating = true
        }
    }
}

struct CommunityStatBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Resource Coming Soon Placeholder

struct ResourceComingSoonPlaceholder: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let icon: String
    let iconColor: Color
    let description: String
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        iconColor.opacity(0.15),
                        iconColor.opacity(0.05),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 40)
                        
                        // Icon with glow effect
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            iconColor.opacity(0.3),
                                            iconColor.opacity(0.1),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 80
                                    )
                                )
                                .frame(width: 160, height: 160)
                                .blur(radius: 10)
                            
                            Circle()
                                .fill(iconColor.opacity(0.15))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Circle()
                                        .stroke(iconColor.opacity(0.3), lineWidth: 2)
                                )
                            
                            Image(systemName: icon)
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(iconColor)
                                .symbolEffect(.pulse, options: .repeating)
                        }
                        
                        VStack(spacing: 16) {
                            // Coming Soon Badge
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.orange)
                                
                                Text("COMING SOON")
                                    .font(.custom("OpenSans-Bold", size: 14))
                                    .foregroundStyle(.orange)
                                    .tracking(2)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
                                    )
                            )
                            
                            Text(title)
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text(description)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(6)
                                .padding(.horizontal, 40)
                        }
                        
                        // What to expect section
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(iconColor)
                                Text("We're Working On It")
                                    .font(.custom("OpenSans-Bold", size: 18))
                            }
                            
                            Text("This feature is currently under development and will be available in a future update. We're building something amazing for you!")
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                            
                            // Feature highlights
                            VStack(spacing: 12) {
                                ResourceFeatureHighlightRow(
                                    icon: "checkmark.circle.fill",
                                    text: "Full functionality coming soon",
                                    color: iconColor
                                )
                                ResourceFeatureHighlightRow(
                                    icon: "bell.fill",
                                    text: "You'll be notified when it's ready",
                                    color: iconColor
                                )
                                ResourceFeatureHighlightRow(
                                    icon: "sparkles",
                                    text: "Built with your feedback in mind",
                                    color: iconColor
                                )
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(iconColor.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                        
                        // CTA Button
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Back to Resources")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(iconColor)
                            )
                            .shadow(color: iconColor.opacity(0.3), radius: 12, y: 4)
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer()
                    }
                    .padding(.vertical)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Resource Feature Highlight Row

struct ResourceFeatureHighlightRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    ResourcesView()
}
