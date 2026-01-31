//
//  SearchViewComponents.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

// MARK: - Supporting Types

/// Namespace for SearchView-related types
enum SearchViewTypes {
    enum SearchFilter: String, CaseIterable {
        case all = "All"
        case people = "People"
        case groups = "Groups"
        case posts = "Posts"
        case events = "Events"
        
        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .people: return "person.2"
            case .groups: return "person.3"
            case .posts: return "doc.text"
            case .events: return "calendar"
            }
        }
    }
    
    enum SortOption: String, CaseIterable {
        case relevance = "Relevance"
        case recent = "Recent"
        case popular = "Popular"
        
        var icon: String {
            switch self {
            case .relevance: return "star.fill"
            case .recent: return "clock.fill"
            case .popular: return "flame.fill"
            }
        }
    }
}

// Note: SearchResult model (AppSearchResult) and TrendingItem are in SearchService.swift

// MARK: - Soft Neumorphic Search Filter Chip
struct SoftSearchFilterChip: View {
    let filter: SearchViewTypes.SearchFilter
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 13, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(isSelected ? .black : .black.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(
                        color: isSelected ? .black.opacity(0.12) : .black.opacity(0.06), 
                        radius: isSelected ? 10 : 6, 
                        x: 0, 
                        y: isSelected ? 5 : 3
                    )
            )
            .overlay(
                Capsule()
                    .stroke(Color.black.opacity(isSelected ? 0.08 : 0.04), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.92 : (isSelected ? 1.02 : 1.0))
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Production-Ready Button Styles

/// Custom button style for discover buttons with scale animation
struct DiscoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Custom button style with press animation
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Discover People Section (Liquid Glass Design)
struct DiscoverPeopleSection: View {
    @StateObject private var userSearchService = UserSearchService.shared
    @State private var suggestedUsers: [FirebaseSearchUser] = []
    @State private var isLoading = true
    @State private var showAllPeople = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with liquid glass effect
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Let's Stay Connected")
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Text("Discover believers in the community")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Horizontal scrolling people cards with liquid glass (Production-Ready)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    // Add new connection button
                    AddConnectionCard {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        showAllPeople = true
                    }
                    
                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in
                            LiquidGlassPersonCardSkeleton()
                        }
                    } else {
                        ForEach(suggestedUsers.prefix(8)) { user in
                            LiquidGlassPersonCard(user: user)
                                .id(user.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .frame(height: 180)
            
            // View all button (Production-Ready with Haptics & Animation)
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showAllPeople = true
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Discover More Believers")
                        .font(.custom("OpenSans-Bold", size: 15))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1.5)
                        )
                )
            }
            .buttonStyle(DiscoverButtonStyle())
            .padding(.horizontal, 20)
        }
        .sheet(isPresented: $showAllPeople) {
            DiscoverPeopleFullView()
        }
        .task {
            await loadSuggestedUsers()
        }
    }
    
    @MainActor
    private func loadSuggestedUsers() async {
        isLoading = true
        
        do {
            // Fetch suggested users (you can implement smart suggestions based on interests, location, etc.)
            suggestedUsers = try await userSearchService.fetchSuggestedUsers()
            isLoading = false
        } catch {
            print("❌ Error loading suggested users: \(error)")
            isLoading = false
        }
    }
}

// MARK: - Add Connection Card
struct AddConnectionCard: View {
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.15),
                                    Color.purple.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.4), .purple.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    
                    Image(systemName: "plus")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text("Add")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.8), .white.opacity(0.4)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Liquid Glass Person Card
struct LiquidGlassPersonCard: View {
    let user: FirebaseSearchUser
    @State private var isPressed = false
    @State private var showProfile = false
    @StateObject private var followService = FollowService.shared
    @State private var isFollowing = false
    
    var body: some View {
        Button {
            showProfile = true
        } label: {
            VStack(spacing: 12) {
                // Avatar with liquid glass effect
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.blue.opacity(0.2),
                                    Color.blue.opacity(0.0)
                                ],
                                center: .center,
                                startRadius: 40,
                                endRadius: 50
                            )
                        )
                        .frame(width: 100, height: 100)
                    
                    // Avatar
                    if let photoURL = user.profileImageURL, let url = URL(string: photoURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            liquidGlassAvatarPlaceholder
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.8), .white.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    } else {
                        liquidGlassAvatarPlaceholder
                    }
                    
                    // Verification badge
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.blue)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 20, height: 20)
                            )
                            .offset(x: -28, y: -28)
                    }
                }
                
                // User info
                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text("@\(user.username)")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 100)
            .padding(.vertical, 12)
            .background(liquidGlassBackground)
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(pressGesture)
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: user.id)
        }
        .task {
            isFollowing = await followService.isFollowing(userId: user.id)
        }
    }
    
    private var liquidGlassAvatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            
            Text(String(user.displayName.prefix(1)))
                .font(.custom("OpenSans-Bold", size: 32))
                .foregroundStyle(.white)
        }
    }
    
    private var liquidGlassBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                Color(.systemBackground)
                    .opacity(0.85)
            )
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.8),
                                Color.white.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
    
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isPressed = true
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
    }
}

// MARK: - Liquid Glass Person Card Skeleton
struct LiquidGlassPersonCardSkeleton: View {
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.3),
                            Color.gray.opacity(0.2),
                            Color.gray.opacity(0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
            
            // Name skeleton
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 70, height: 12)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 10)
            }
        }
        .frame(width: 100)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
    }
}

// MARK: - Auto-Scrolling Banners Section
struct AutoScrollingBannersSection: View {
    @State private var currentIndex = 0
    @State private var timer: Timer?
    
    let banners: [FeatureBanner] = [
        FeatureBanner(
            icon: "book.closed.fill",
            title: "Bible Study Groups",
            subtitle: "Join active discussions today",
            gradient: LinearGradient(
                colors: [Color.orange, Color(red: 1.0, green: 0.6, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
        FeatureBanner(
            icon: "sparkles",
            title: "AI Bible Study",
            subtitle: "Ask questions, get instant answers",
            gradient: LinearGradient(
                colors: [Color.purple, Color(red: 0.8, green: 0.3, blue: 0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
        FeatureBanner(
            icon: "hands.sparkles.fill",
            title: "Prayer Circles",
            subtitle: "24/7 prayer support network",
            gradient: LinearGradient(
                colors: [Color(red: 0.4, green: 0.85, blue: 0.7), Color(red: 0.3, green: 0.7, blue: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        ),
        FeatureBanner(
            icon: "person.3.fill",
            title: "Small Groups",
            subtitle: "Find your faith community",
            gradient: LinearGradient(
                colors: [Color.pink, Color(red: 1.0, green: 0.4, blue: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentIndex) {
                ForEach(Array(banners.enumerated()), id: \.offset) { index, banner in
                    FeatureBannerCard(banner: banner)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 160)
            .onAppear {
                startAutoScroll()
            }
            .onDisappear {
                stopAutoScroll()
            }
            
            // Custom page indicator
            HStack(spacing: 6) {
                ForEach(0..<banners.count, id: \.self) { index in
                    Circle()
                        .fill(currentIndex == index ? Color.black : Color.black.opacity(0.2))
                        .frame(width: currentIndex == index ? 8 : 6, height: currentIndex == index ? 8 : 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentIndex)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
    
    private func startAutoScroll() {
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentIndex = (currentIndex + 1) % banners.count
            }
        }
    }
    
    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}

struct FeatureBanner: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let gradient: LinearGradient
}

struct FeatureBannerCard: View {
    let banner: FeatureBanner
    @State private var isPressed = false
    @State private var showFeatureInfo = false
    
    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            showFeatureInfo = true
        } label: {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: banner.icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(banner.title)
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.white)
                    
                    Text(banner.subtitle)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                    
                    HStack(spacing: 6) {
                        Text("Learn More")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.white)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(banner.gradient)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 20)
            .scaleEffect(isPressed ? 0.97 : 1.0)
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
        .sheet(isPresented: $showFeatureInfo) {
            FeatureInfoSheet(banner: banner)
        }
    }
}

// MARK: - Feature Info Sheet
struct FeatureInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let banner: FeatureBanner
    
    var featureDetails: (description: String, features: [String], howTo: String) {
        switch banner.title {
        case "Bible Study Groups":
            return (
                description: "Connect with believers in focused Bible study groups. Dive deep into scripture, share insights, and grow together in faith.",
                features: [
                    "Join existing study groups on various topics",
                    "Create your own Bible study community",
                    "Weekly discussion threads and verse analysis",
                    "Share reflections and prayer requests",
                    "Track your reading progress"
                ],
                howTo: "Navigate to the Groups tab to discover and join Bible study communities that match your interests."
            )
        case "AI Bible Study":
            return (
                description: "Your AI-powered companion for exploring scripture. Ask questions, get biblical context, and discover deeper meanings.",
                features: [
                    "Ask questions about any Bible passage",
                    "Get historical and cultural context",
                    "Explore cross-references and themes",
                    "Generate study guides and devotionals",
                    "Multi-translation comparisons"
                ],
                howTo: "Tap the AI Assistant icon or use the search bar to ask biblical questions and explore scripture."
            )
        case "Prayer Circles":
            return (
                description: "Join 24/7 prayer support networks. Share requests, offer prayers, and witness answered prayers in real-time.",
                features: [
                    "Share prayer requests with the community",
                    "Pray for others and offer encouragement",
                    "Join focused prayer circles (healing, guidance, etc.)",
                    "Celebrate answered prayers together",
                    "Set prayer reminders and notifications"
                ],
                howTo: "Navigate to the Prayer tab to join prayer circles and share your requests with the community."
            )
        case "Small Groups":
            return (
                description: "Find your faith family. Connect with local believers, join small groups, and build meaningful relationships.",
                features: [
                    "Discover groups by location and interests",
                    "Meet regularly with your group",
                    "Share life experiences and grow together",
                    "Organize events and meetups",
                    "Private group messaging and resources"
                ],
                howTo: "Go to the Groups tab and filter by 'Small Groups' to find communities near you or matching your interests."
            )
        default:
            return (
                description: "Discover more features to enhance your faith journey.",
                features: ["Explore the app to find more"],
                howTo: "Navigate through different tabs to discover features."
            )
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header with icon
                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(banner.gradient)
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: banner.icon)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(banner.title)
                                .font(.custom("OpenSans-Bold", size: 26))
                                .foregroundStyle(.primary)
                            
                            Text(banner.subtitle)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        Text(featureDetails.description)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                    
                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Features")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        ForEach(featureDetails.features, id: \.self) { feature in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(banner.gradient)
                                
                                Text(feature)
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    
                    // How to access
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to Get Started")
                            .font(.custom("OpenSans-Bold", size: 18))
                            .foregroundStyle(.primary)
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                            
                            Text(featureDetails.howTo)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
                .padding(24)
            }
            .navigationTitle("Feature Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}



// MARK: - Neumorphic Smart Search Bar Component with Suggestions
struct NeumorphicSearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Neumorphic search icon circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 5, y: 5)
                    .shadow(color: .white.opacity(0.8), radius: 10, x: -5, y: -5)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.black.opacity(0.5), Color.black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            TextField("Search", text: $text)
                .font(.custom("OpenSans-SemiBold", size: 17))
                .foregroundStyle(.primary)
                .focused($isFocused)
                .submitLabel(.search)
            
            if !text.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onClear()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.systemBackground).opacity(0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.15), radius: 15, x: 8, y: 8)
                .shadow(color: .white.opacity(0.7), radius: 15, x: -8, y: -8)
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - Loading Results View
struct LoadingResultsView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Searching...")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

// MARK: - No Results View
struct NoResultsView: View {
    let query: String
    let onSuggestionTap: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No results for \"\(query)\"")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
            
            Text("Try different keywords or browse suggested topics")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Suggestions
            VStack(spacing: 12) {
                Text("You might be interested in:")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 10) {
                    SuggestionTag(text: "#Prayer", onTap: onSuggestionTap)
                    SuggestionTag(text: "#Testimony", onTap: onSuggestionTap)
                    SuggestionTag(text: "#BibleStudy", onTap: onSuggestionTap)
                }
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct SuggestionTag: View {
    let text: String
    let onTap: (String) -> Void
    
    var body: some View {
        Button {
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            onTap(text)
        } label: {
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                )
        }
    }
}

// MARK: - Enhanced Search Results View
struct SearchResultsView: View {
    let query: String
    let filter: SearchViewTypes.SearchFilter
    let results: [AppSearchResult]
    let sortOption: SearchViewTypes.SortOption
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Results for '\(query)'")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text("\(results.count) found")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.06))
                    )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            VStack(spacing: 12) {
                ForEach(results) { result in
                    SoftSearchResultCard(result: result)
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Soft Neumorphic Search Result Card
struct SoftSearchResultCard: View {
    let result: AppSearchResult
    @State private var isPressed = false
    @State private var showUserProfile = false
    @State private var isFollowing = false
    @StateObject private var followService = FollowService.shared
    
    var body: some View {
        Button {
            handleCardTap()
        } label: {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(pressGesture)
        .sheet(isPresented: $showUserProfile) {
            userProfileSheet
        }
    }
    
    // MARK: - Subviews
    
    private var cardContent: some View {
        HStack(spacing: 14) {
            resultIcon
            resultInfo
            Spacer(minLength: 0)
            trailingContent
        }
        .padding(14)
        .background(cardBackground)
        .scaleEffect(isPressed ? 0.98 : 1.0)
    }
    
    private var resultIcon: some View {
        ZStack {
            Circle()
                .fill(result.type.color.opacity(0.15))
                .frame(width: 52, height: 52)
            
            Image(systemName: result.type.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(result.type.color)
        }
    }
    
    private var resultInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleWithVerification
            
            Text(result.subtitle)
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text(result.metadata)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
    
    private var titleWithVerification: some View {
        HStack(spacing: 6) {
            Text(result.title)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            if result.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
            }
        }
    }
    
    @ViewBuilder
    private var trailingContent: some View {
        if result.type == .person {
            followButton
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
    
    private var followButton: some View {
        Button {
            handleFollowTap()
        } label: {
            followButtonLabel
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            await loadFollowStatus()
        }
    }
    
    private var followButtonLabel: some View {
        Text(isFollowing ? "Following" : "Follow")
            .font(.custom("OpenSans-Bold", size: 13))
            .foregroundStyle(isFollowing ? Color.primary : Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(followButtonBackground)
            .overlay(followButtonOverlay)
    }
    
    private var followButtonBackground: some View {
        Capsule()
            .fill(isFollowing ? Color.clear : Color.blue)
    }
    
    private var followButtonOverlay: some View {
        Capsule()
            .stroke(isFollowing ? Color.primary.opacity(0.3) : Color.clear, lineWidth: 1)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var pressGesture: some Gesture {
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
    }
    
    @ViewBuilder
    private var userProfileSheet: some View {
        if let userId = result.firestoreId {
            UserProfileView(userId: userId)
        }
    }
    
    // MARK: - Actions
    
    private func handleCardTap() {
        if result.type == .person {
            showUserProfile = true
        }
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
    
    private func handleFollowTap() {
        Task {
            guard let userId = result.firestoreId else { return }
            do {
                try await followService.toggleFollow(userId: userId)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isFollowing.toggle()
                }
            } catch {
                print("❌ Follow error: \(error)")
            }
        }
    }
    
    private func loadFollowStatus() async {
        if let userId = result.firestoreId {
            isFollowing = await followService.isFollowing(userId: userId)
        }
    }
}

// MARK: - Recent Searches Section (Production-Ready with Swipe & Icons)
struct RecentSearchesSection: View {
    @Binding var searches: [String]
    let onSelect: (String) -> Void
    let onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                Text("Recent Searches")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        onClear()
                    }
                } label: {
                    Text("Clear All")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(searches, id: \.self) { search in
                        EnhancedSearchHistoryChip(
                            search: search,
                            onTap: {
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                                onSelect(search)
                            },
                            onRemove: {
                                let haptic = UINotificationFeedbackGenerator()
                                haptic.notificationOccurred(.success)
                                
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    searches.removeAll { $0 == search }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Enhanced Search History Chip (Production-Ready with Swipe-to-Delete)
struct EnhancedSearchHistoryChip: View {
    let search: String
    let onTap: () -> Void
    let onRemove: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isPressed = false
    @State private var showDeleteButton = false
    
    // Detect search category for smart icons
    private var searchCategory: SearchCategory {
        if search.hasPrefix("#") {
            return .hashtag
        } else if search.hasPrefix("@") {
            return .user
        } else if search.contains("prayer") || search.contains("pray") {
            return .prayer
        } else if search.contains("bible") || search.contains("scripture") {
            return .bible
        } else if search.contains("testimony") {
            return .testimony
        } else if search.contains("group") {
            return .group
        } else {
            return .general
        }
    }
    
    private enum SearchCategory {
        case hashtag, user, prayer, bible, testimony, group, general
        
        var icon: String {
            switch self {
            case .hashtag: return "number"
            case .user: return "person.circle.fill"
            case .prayer: return "hands.sparkles.fill"
            case .bible: return "book.closed.fill"
            case .testimony: return "star.fill"
            case .group: return "person.3.fill"
            case .general: return "magnifyingglass"
            }
        }
        
        var color: Color {
            switch self {
            case .hashtag: return .blue
            case .user: return .purple
            case .prayer: return .orange
            case .bible: return .green
            case .testimony: return .yellow
            case .group: return .pink
            case .general: return .gray
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button background (revealed on swipe)
            if offset < -10 {
                deleteButtonBackground
            }
            
            // Main chip content
            mainChipContent
                .offset(x: offset)
                .gesture(swipeGesture)
        }
        .frame(height: 44)
    }
    
    // MARK: - Delete Button Background
    
    private var deleteButtonBackground: some View {
        HStack {
            Spacer()
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 44)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Main Chip Content
    
    private var mainChipContent: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Smart icon based on search type
                ZStack {
                    Circle()
                        .fill(searchCategory.color.opacity(0.15))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: searchCategory.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(searchCategory.color)
                }
                
                // Search text
                Text(search)
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                // Remove button (always visible)
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(Color(.systemGray5))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(chipBackground)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.96 : 1.0)
    }
    
    private var chipBackground: some View {
        Capsule()
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                searchCategory.color.opacity(0.3),
                                searchCategory.color.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
    }
    
    // MARK: - Swipe Gesture
    
    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Only allow left swipe
                if value.translation.width < 0 {
                    offset = max(value.translation.width, -80)
                }
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if value.translation.width < -50 {
                        // Swipe threshold reached - delete
                        onRemove()
                    } else {
                        // Reset position
                        offset = 0
                    }
                }
            }
    }
}

// MARK: - Smart People Discovery Components

// Smart Loading View with Animated Avatars
struct SmartLoadingPeopleView: View {
    @State private var animateGradient = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Animated avatar placeholders
            HStack(spacing: -12) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                                endPoint: animateGradient ? .bottomTrailing : .topLeading
                            )
                        )
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        )
                        .offset(y: CGFloat(index) * 4)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animateGradient
                        )
                }
            }
            
            VStack(spacing: 8) {
                Text("Finding believers...")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                
                Text("Searching the faith community")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            // Animated search indicators
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animateGradient ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: animateGradient
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
        .onAppear {
            animateGradient = true
        }
    }
}

// Error State with Retry
struct PeopleSearchErrorView: View {
    let error: String
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.2), .orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.red)
            }
            
            VStack(spacing: 8) {
                Text("Connection Issue")
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)
                
                Text(error)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button {
                // Retry action
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Try Again")
                        .font(.custom("OpenSans-Bold", size: 16))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// No Results with Suggestions
struct NoPeopleFoundView: View {
    let query: String
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated empty state
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.gray.opacity(0.1), .gray.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 12) {
                Text("No believers found")
                    .font(.custom("OpenSans-Bold", size: 24))
                    .foregroundStyle(.primary)
                
                Text("for '\(query)'")
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .foregroundStyle(.secondary)
                
                Text("Try a different name or username")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.tertiary)
            }
            
            // Search tips
            VStack(alignment: .leading, spacing: 16) {
                Text("Search Tips")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                SearchTipRow(icon: "at", text: "Try searching by @username")
                SearchTipRow(icon: "person.fill", text: "Search full names like 'John Smith'")
                SearchTipRow(icon: "globe", text: "Check spelling and try again")
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6).opacity(0.5))
            )
            .padding(.horizontal, 32)
        }
        .padding(.top, 60)
    }
}

struct SearchTipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// Smart People Results View with Categories
struct SmartPeopleResultsView: View {
    let results: [FirebaseSearchUser]
    let onUserTap: (FirebaseSearchUser) -> Void
    
    @State private var showFilters = false
    
    // Categorize results
    var verifiedUsers: [FirebaseSearchUser] {
        results.filter { $0.isVerified }
    }
    
    var regularUsers: [FirebaseSearchUser] {
        results.filter { !$0.isVerified }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Results header with stats
                resultsHeader
                
                // Verified users section
                if !verifiedUsers.isEmpty {
                    verifiedUsersSection
                }
                
                // Regular users
                if !regularUsers.isEmpty {
                    regularUsersSection
                }
            }
            .padding(.vertical, 16)
        }
    }
    
    private var resultsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(results.count) believers found")
                    .font(.custom("OpenSans-Bold", size: 20))
                    .foregroundStyle(.primary)
                
                if !verifiedUsers.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.blue)
                        Text("\(verifiedUsers.count) verified")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    private var verifiedUsersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
                
                Text("Verified Believers")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            
            LazyVStack(spacing: 12) {
                ForEach(verifiedUsers) { user in
                    EnhancedUserCard(user: user, onTap: {
                        onUserTap(user)
                    })
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var regularUsersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !verifiedUsers.isEmpty {
                Text("All Believers")
                    .font(.custom("OpenSans-Bold", size: 18))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            
            LazyVStack(spacing: 12) {
                ForEach(regularUsers) { user in
                    EnhancedUserCard(user: user, onTap: {
                        onUserTap(user)
                    })
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

// Enhanced User Card with Smart Interactions
struct EnhancedUserCard: View {
    let user: FirebaseSearchUser
    let onTap: () -> Void
    
    @StateObject private var followService = FollowService.shared
    @State private var isFollowing = false
    @State private var isPressed = false
    @State private var showFollowAnimation = false
    
    var body: some View {
        Button {
            onTap()
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 16) {
                // Profile Image with Status Ring
                ZStack(alignment: .bottomTrailing) {
                    // Avatar
                    if let photoURL = user.profileImageURL, let url = URL(string: photoURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            avatarPlaceholder
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder
                    }
                    
                    // Verification badge
                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                            .background(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 22, height: 22)
                            )
                            .offset(x: 2, y: 2)
                    }
                }
                
                // User Info
                VStack(alignment: .leading, spacing: 6) {
                    // Name with badge
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    
                    // Username
                    Text("@\(user.username)")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    // Bio preview
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                
                Spacer(minLength: 8)
                
                // Follow Button
                followButton
            }
            .padding(16)
            .background(cardBackground)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(pressGesture)
        .task {
            await loadFollowStatus()
        }
        .overlay(followAnimationOverlay)
    }
    
    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
            
            Text(String(user.displayName.prefix(1)))
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
        }
    }
    
    private var followButton: some View {
        Button {
            handleFollowTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isFollowing ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(isFollowing ? .blue : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(followButtonBackground)
            .clipShape(Capsule())
            .overlay(followButtonOverlay)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var followButtonBackground: some View {
        Group {
            if isFollowing {
                Capsule()
                    .fill(Color.blue.opacity(0.1))
            } else {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
            }
        }
    }
    
    private var followButtonOverlay: some View {
        Capsule()
            .stroke(isFollowing ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1.5)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        user.isVerified ?
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: user.isVerified ? 1.5 : 0
                    )
            )
    }
    
    private var pressGesture: some Gesture {
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
    }
    
    @ViewBuilder
    private var followAnimationOverlay: some View {
        if showFollowAnimation {
            ZStack {
                Color.black.opacity(0.3)
                
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(.white)
                    .scaleEffect(showFollowAnimation ? 1.2 : 0.5)
                    .opacity(showFollowAnimation ? 1.0 : 0.0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
    
    private func handleFollowTap() {
        Task {
            do {
                try await followService.toggleFollow(userId: user.id)
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isFollowing.toggle()
                }
                
                // Show success animation
                if isFollowing {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showFollowAnimation = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation {
                            showFollowAnimation = false
                        }
                    }
                }
                
                // Haptic feedback
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(isFollowing ? .success : .warning)
                
            } catch {
                print("❌ Follow error: \(error)")
                // Show error alert
            }
        }
    }
    
    private func loadFollowStatus() async {
        isFollowing = await followService.isFollowing(userId: user.id)
    }
}



// MARK: - Discover People Full View (Liquid Glass Design)
struct DiscoverPeopleFullView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userSearchService = UserSearchService.shared
    @State private var searchText = ""
    @State private var selectedCategory: PeopleCategory = .all
    @FocusState private var isSearchFocused: Bool
    @State private var suggestedUsers: [FirebaseSearchUser] = []
    @State private var isLoadingSuggestions = true
    
    enum PeopleCategory: String, CaseIterable {
        case all = "All"
        case verified = "Verified"
        
        var icon: String {
            switch self {
            case .all: return "person.3.fill"
            case .verified: return "checkmark.seal.fill"
            }
        }
        
        var gradient: LinearGradient {
            switch self {
            case .all:
                return LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .verified:
                return LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    var filteredResults: [FirebaseSearchUser] {
        var results = searchText.isEmpty ? suggestedUsers : userSearchService.searchResults
        
        switch selectedCategory {
        case .all:
            return results
        case .verified:
            return results.filter { $0.isVerified }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Liquid glass background
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.03),
                        Color(.systemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Liquid Glass Search Bar
                    liquidGlassSearchBar
                    
                    // Category Pills with Liquid Glass
                    liquidGlassCategoryPills
                    
                    // Content
                    if searchText.isEmpty {
                        discoverContentView
                    } else {
                        searchResultsView
                    }
                }
            }
            .navigationTitle("Discover Believers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty {
                userSearchService.debouncedSearch(query: newValue, searchType: .both)
            } else {
                userSearchService.clearSearch()
            }
        }
        .task {
            await loadSuggestedUsers()
        }
    }
    
    // MARK: - Liquid Glass Search Bar
    
    private var liquidGlassSearchBar: some View {
        HStack(spacing: 14) {
            // Search icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            TextField("Search believers...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
                .focused($isSearchFocused)
                .submitLabel(.search)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(liquidGlassEffect)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private var liquidGlassEffect: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                Color(.systemBackground)
                    .opacity(0.7)
            )
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Liquid Glass Category Pills
    
    private var liquidGlassCategoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PeopleCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = category
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(category.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(
                            selectedCategory == category ?
                                .white :
                                    .primary
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if selectedCategory == category {
                                    Capsule()
                                        .fill(category.gradient)
                                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                                } else {
                                    Capsule()
                                        .fill(
                                            Color(.systemBackground)
                                                .opacity(0.7)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [.white.opacity(0.8), .white.opacity(0.3)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }
    
    // MARK: - Discover Content View
    
    @ViewBuilder
    private var discoverContentView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if isLoadingSuggestions {
                    ForEach(0..<6, id: \.self) { _ in
                        LiquidGlassPersonCardLargeSkeleton()
                            .padding(.horizontal, 20)
                    }
                } else if filteredResults.isEmpty {
                    emptyDiscoverState
                } else {
                    ForEach(filteredResults) { user in
                        LiquidGlassPersonCardLarge(user: user)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Search Results View
    
    @ViewBuilder
    private var searchResultsView: some View {
        if userSearchService.isSearching {
            SmartLoadingPeopleView()
        } else if let error = userSearchService.searchError {
            PeopleSearchErrorView(error: error)
        } else if filteredResults.isEmpty {
            NoPeopleFoundView(query: searchText)
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(filteredResults) { user in
                        LiquidGlassPersonCardLarge(user: user)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }
    
    private var emptyDiscoverState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.3.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 60)
            
            VStack(spacing: 12) {
                Text("No Believers Yet")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Be the first to discover the community")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Load Suggested Users
    
    @MainActor
    private func loadSuggestedUsers() async {
        isLoadingSuggestions = true
        
        do {
            suggestedUsers = try await userSearchService.fetchSuggestedUsers()
            isLoadingSuggestions = false
        } catch {
            print("❌ Error loading suggested users: \(error)")
            suggestedUsers = []
            isLoadingSuggestions = false
        }
    }
}

// MARK: - Liquid Glass Person Card Large
struct LiquidGlassPersonCardLarge: View {
    let user: FirebaseSearchUser
    @State private var isPressed = false
    @State private var showProfile = false
    @StateObject private var followService = FollowService.shared
    @State private var isFollowing = false
    @State private var showFollowAnimation = false
    
    var body: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: 16) {
                // Avatar
                avatarSection
                
                // User Info
                userInfoSection
                
                Spacer(minLength: 8)
                
                // Follow Button
                followButton
            }
            .padding(16)
            .background(liquidGlassCardBackground)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(pressGesture)
        .sheet(isPresented: $showProfile) {
            UserProfileView(userId: user.id)
        }
        .task {
            isFollowing = await followService.isFollowing(userId: user.id)
        }
    }
    
    private var avatarSection: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photoURL = user.profileImageURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            } else {
                avatarPlaceholder
            }
            
            // Online/Verification Badge
            if user.isVerified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                    .background(
                        Circle()
                            .fill(.white)
                            .frame(width: 22, height: 22)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.8), .white.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            
            Text(String(user.displayName.prefix(1)))
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.white)
        }
    }
    
    private var userInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(user.displayName)
                .font(.custom("OpenSans-Bold", size: 17))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Text("@\(user.username)")
                .font(.custom("OpenSans-SemiBold", size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            if let bio = user.bio, !bio.isEmpty {
                Text(bio)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }
    
    private var followButton: some View {
        Button {
            handleFollowTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isFollowing ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundStyle(isFollowing ? .blue : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(followButtonBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var followButtonBackground: some View {
        if isFollowing {
            Capsule()
                .fill(
                    Color(.systemBackground)
                        .opacity(0.8)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.5), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        } else {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
        }
    }
    
    private var liquidGlassCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                Color(.systemBackground)
                    .opacity(0.7)
            )
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
    
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isPressed = true
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
    }
    
    private func handleFollowTap() {
        Task {
            do {
                try await followService.toggleFollow(userId: user.id)
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isFollowing.toggle()
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(isFollowing ? .success : .warning)
                
            } catch {
                print("❌ Follow error: \(error)")
            }
        }
    }
}

// MARK: - Liquid Glass Person Card Large Skeleton
struct LiquidGlassPersonCardLargeSkeleton: View {
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar skeleton
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 64, height: 64)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 100, height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 200, height: 12)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground).opacity(0.7))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
    }
}

// MARK: - Forward Declaration Wrapper
// This wrapper allows PeopleDiscoveryView to be referenced before it's defined
struct PeopleDiscoveryViewWrapper: View {
    var body: some View {
        DiscoverPeopleFullView()
    }
}

// MARK: - Main SearchView
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = SearchService.shared
    @StateObject private var userSearchService = UserSearchService.shared  // NEW: User search integration
    @State private var searchText = ""
    @State private var selectedFilter: SearchViewTypes.SearchFilter = .all
    @State private var selectedSort: SearchViewTypes.SortOption = .relevance
    @State private var showSortOptions = false
    @State private var showDiscoverPeople = false  // NEW: Discover People toggle
    @FocusState private var isSearchFieldFocused: Bool
    
    // Results from backend
    @State private var searchResults: [AppSearchResult] = []
    
    // NEW: AI-Powered Search
    @State private var aiSuggestions: SearchSuggestions?
    @State private var biblicalResult: BiblicalSearchResult?
    @State private var filterSuggestion: FilterSuggestion?
    @State private var isLoadingAI = false
    private let genkitService = BereanGenkitService.shared
    
    var filteredResults: [AppSearchResult] {
        guard !searchText.isEmpty else { return [] }
        return searchResults.filter { result in
            selectedFilter == .all || filterMatches(result: result, filter: selectedFilter)
        }
    }
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        backButton
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenuButton
                    }
                }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty {
                // Perform appropriate search based on filter
                if selectedFilter == .people {
                    // Use UserSearchService for people search
                    userSearchService.debouncedSearch(query: newValue, searchType: .both)
                } else {
                    // Use regular SearchService for other content
                    performSearch(query: newValue)
                }
                
                // NEW: Trigger AI search with debounce
                if newValue.count >= 3 {
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
                        if searchText == newValue { // Still same query
                            await performAISearch()
                        }
                    }
                }
            } else {
                searchResults = []
                userSearchService.clearSearch()  // NEW: Clear user search results
                // Clear AI results when search cleared
                aiSuggestions = nil
                biblicalResult = nil
                filterSuggestion = nil
            }
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            // When switching to People filter, trigger user search
            if newValue == .people && !searchText.isEmpty {
                userSearchService.debouncedSearch(query: searchText, searchType: .both)
            } else if !searchText.isEmpty {
                performSearch(query: searchText)
            }
        }
        .onAppear {
            // Load recent searches from service
            searchService.loadRecentSearches()
        }
        .sheet(isPresented: $showUserProfileSheet) {
            if let user = selectedUserForProfile {
                UserProfileView(userId: user.id)
            }
        }
    }
    
    // MARK: - Main Content View
    
    private var mainContent: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            mainContentVStack
        }
    }
    
    private var mainContentVStack: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBar
            
            // Filter Chips
            if !searchText.isEmpty {
                filterSection
            }
            
            // Content
            searchContentScroll
        }
    }
    
    // MARK: - Search Content Scroll
    
    private var searchContentScroll: some View {
        ScrollView {
            VStack(spacing: 24) {
                contentBasedOnSearchState
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Content Based on Search State
    
    @ViewBuilder
    private var contentBasedOnSearchState: some View {
        if searchText.isEmpty {
            // Empty state - show suggestions with smooth transition
            emptyStateContent
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if selectedFilter == .people {
            // NEW: Show user search results from UserSearchService with smooth transition
            peopleSearchResults
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if searchService.isSearching {
            // Loading state with smooth transition
            LoadingResultsView()
                .transition(.opacity)
        } else if filteredResults.isEmpty {
            // No results with smooth transition
            NoResultsView(query: searchText) { suggestion in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    searchText = suggestion
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            // Search results with AI enhancements and smooth transition
            VStack(spacing: 16) {
                // NEW: Smart Filter Banner
                if let filterSuggestion = filterSuggestion {
                    SmartFilterBanner(
                        suggestion: filterSuggestion,
                        onApplyFilters: { filters in
                            applyAISuggestedFilters(filters)
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // NEW: Biblical Context Card
                if let biblical = biblicalResult {
                    BiblicalSearchCard(result: biblical)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // NEW: AI Suggestions Panel
                if let suggestions = aiSuggestions {
                    AISearchSuggestionsPanel(
                        query: searchText,
                        suggestions: suggestions.suggestions,
                        relatedTopics: suggestions.relatedTopics,
                        onSuggestionTap: { suggestion in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                searchText = suggestion
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Regular Search Results
                SearchResultsView(
                    query: searchText,
                    filter: selectedFilter,
                    results: filteredResults,
                    sortOption: selectedSort
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
    
    // MARK: - People Search Results (Smart & Interactive)
    
    private var peopleSearchResults: some View {
        Group {
            if userSearchService.isSearching {
                SmartLoadingPeopleView()
            } else if let error = userSearchService.searchError {
                PeopleSearchErrorView(error: error)
            } else if userSearchService.searchResults.isEmpty {
                NoPeopleFoundView(query: searchText)
            } else {
                SmartPeopleResultsView(
                    results: userSearchService.searchResults,
                    onUserTap: { user in
                        navigateToUserProfile(user)
                    }
                )
            }
        }
    }
    
    // MARK: - Navigation Helper
    
    @State private var selectedUserForProfile: FirebaseSearchUser?
    @State private var showUserProfileSheet = false
    
    private func navigateToUserProfile(_ user: FirebaseSearchUser) {
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Show user profile
        selectedUserForProfile = user
        showUserProfileSheet = true
        
        print("👤 Navigate to user profile: @\(user.username)")
    }
    
    // MARK: - Toolbar Components
    
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("Back")
                    .font(.custom("OpenSans-SemiBold", size: 16))
            }
            .foregroundStyle(.primary)
        }
    }
    
    @ViewBuilder
    private var sortMenuButton: some View {
        if !searchText.isEmpty {
            Menu {
                Picker("Sort By", selection: $selectedSort) {
                    ForEach(SearchViewTypes.SortOption.allCases, id: \.self) { option in
                        Label(option.rawValue, systemImage: option.icon)
                            .tag(option)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
        }
    }
    
    // MARK: - Smart Search Bar (Neumorphic Design)
    
    private var searchBar: some View {
        VStack(spacing: 0) {
            NeumorphicSearchBar(
                text: $searchText,
                isFocused: $isSearchFieldFocused,
                onClear: {
                    searchText = ""
                }
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            isSearchFieldFocused = true
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SearchViewTypes.SearchFilter.allCases, id: \.self) { filter in
                    SoftSearchFilterChip(
                        filter: filter,
                        isSelected: selectedFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedFilter = filter
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    // MARK: - Empty State Content (Minimal & Smart)
    
    private var emptyStateContent: some View {
        VStack(spacing: 28) {
            // Discover People Section - Liquid Glass Design
            DiscoverPeopleSection()
                .transition(.opacity.combined(with: .move(edge: .top)))
            
            // Recent searches from service
            if !searchService.recentSearches.isEmpty {
                RecentSearchesSection(
                    searches: $searchService.recentSearches,
                    onSelect: { search in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            searchText = search
                        }
                    },
                    onClear: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            searchService.clearRecentSearches()
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            
            // Auto-scrolling banners
            AutoScrollingBannersSection()
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
    
    // MARK: - Helper Methods
    
    private func filterMatches(result: AppSearchResult, filter: SearchViewTypes.SearchFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .people:
            return result.type == .person
        case .groups:
            return result.type == .group
        case .posts:
            return result.type == .post
        case .events:
            return result.type == .event
        }
    }
    
    private func performSearch(query: String) {
        Task {
            do {
                // Use real backend search service
                searchResults = try await searchService.search(query: query, filter: selectedFilter)
            } catch {
                print("❌ Search error: \(error.localizedDescription)")
                searchResults = []
            }
        }
    }
    
    // MARK: - AI-Powered Search
    
    private func performAISearch() async {
        guard searchText.count >= 3 else { return }
        
        isLoadingAI = true
        
        do {
            // Get smart suggestions
            let suggestions = try await genkitService.generateSearchSuggestions(
                query: searchText,
                context: selectedFilter.rawValue.lowercased()
            )
            
            // Get smart filter suggestions
            let filters = try await genkitService.suggestSearchFilters(query: searchText)
            
            // Check if query looks biblical (person, place, or event)
            var biblical: BiblicalSearchResult?
            let biblicalKeywords = ["david", "paul", "peter", "moses", "jesus", "mary", 
                                   "jerusalem", "bethlehem", "egypt", "rome",
                                   "exodus", "genesis", "revelation", "pentecost"]
            
            if biblicalKeywords.contains(where: { searchText.lowercased().contains($0) }) {
                // Detect type (simple heuristic)
                let type: BiblicalSearchType
                if ["jerusalem", "bethlehem", "egypt", "rome"].contains(where: { searchText.lowercased().contains($0) }) {
                    type = .place
                } else if ["exodus", "genesis", "pentecost", "crucifixion"].contains(where: { searchText.lowercased().contains($0) }) {
                    type = .event
                } else {
                    type = .person
                }
                
                biblical = try await genkitService.enhanceBiblicalSearch(
                    query: searchText,
                    type: type
                )
            }
            
            await MainActor.run {
                aiSuggestions = suggestions
                filterSuggestion = filters
                biblicalResult = biblical
                isLoadingAI = false
            }
            
            print("✅ AI search completed: \(suggestions.suggestions.count) suggestions")
            
        } catch {
            print("❌ AI search error: \(error.localizedDescription)")
            await MainActor.run {
                isLoadingAI = false
            }
        }
    }
    
    private func applyAISuggestedFilters(_ filters: [String]) {
        // Map filter strings to SearchFilter enum
        if let firstFilter = filters.first,
           let filter = SearchViewTypes.SearchFilter.allCases.first(where: { 
               $0.rawValue.lowercased() == firstFilter.lowercased() 
           }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedFilter = filter
            }
        }
    }
}



// MARK: - People Discovery View (Standalone)

struct PeopleDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var userSearchService = UserSearchService.shared
    @State private var searchText = ""
    @State private var selectedCategory: PeopleCategory = .all
    @FocusState private var isSearchFocused: Bool
    
    enum PeopleCategory: String, CaseIterable {
        case all = "All"
        case verified = "Verified"
        
        var icon: String {
            switch self {
            case .all: return "person.3.fill"
            case .verified: return "checkmark.seal.fill"
            }
        }
    }
    
    var filteredResults: [FirebaseSearchUser] {
        var results = userSearchService.searchResults
        
        switch selectedCategory {
        case .all:
            return results
        case .verified:
            return results.filter { $0.isVerified }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search Bar
                    peopleSearchBar
                    
                    // Category Pills
                    categoryPills
                    
                    // Content
                    if searchText.isEmpty {
                        suggestedPeopleView
                    } else {
                        searchResultsView
                    }
                }
            }
            .navigationTitle("Discover Believers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            if !newValue.isEmpty {
                userSearchService.debouncedSearch(query: newValue, searchType: .both)
            } else {
                userSearchService.clearSearch()
            }
        }
    }
    
    private var peopleSearchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                
                TextField("Search believers by name or @username", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PeopleCategory.allCases, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedCategory = category
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(category.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(selectedCategory == category ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(selectedCategory == category ? Color.blue : Color(.systemGray6))
                                .shadow(
                                    color: selectedCategory == category ? .blue.opacity(0.3) : .clear,
                                    radius: 8,
                                    y: 4
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 12)
    }
    
    private var suggestedPeopleView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suggested Believers")
                            .font(.custom("OpenSans-Bold", size: 22))
                        
                        Text("Connect with the faith community")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                // Categories
                VStack(spacing: 20) {
                    SuggestedPeopleCategorySection(
                        title: "Prayer Partners",
                        icon: "hands.sparkles.fill",
                        iconColor: .purple,
                        description: "Connect for prayer support"
                    )
                    
                    SuggestedPeopleCategorySection(
                        title: "Bible Study Leaders",
                        icon: "book.closed.fill",
                        iconColor: .orange,
                        description: "Learn from experienced teachers"
                    )
                    
                    SuggestedPeopleCategorySection(
                        title: "Worship Leaders",
                        icon: "music.note",
                        iconColor: .pink,
                        description: "Engage in worship together"
                    )
                    
                    SuggestedPeopleCategorySection(
                        title: "Mission Volunteers",
                        icon: "globe.americas.fill",
                        iconColor: .green,
                        description: "Join mission opportunities"
                    )
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    private var searchResultsView: some View {
        Group {
            if userSearchService.isSearching {
                SmartLoadingPeopleView()
            } else if let error = userSearchService.searchError {
                PeopleSearchErrorView(error: error)
            } else if filteredResults.isEmpty {
                NoPeopleFoundView(query: searchText)
            } else {
                SmartPeopleResultsView(results: filteredResults) { user in
                    // Navigate to profile
                    print("👤 Navigate to: \(user.username)")
                }
            }
        }
    }
}

struct SuggestedPeopleCategorySection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let description: String
    @State private var isPressed = false
    
    var body: some View {
        Button {
            // Navigate to category
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [iconColor.opacity(0.2), iconColor.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
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
        .padding(.horizontal, 20)
    }
}

// MARK: - AI Search Enhancement Components
// Note: SmartFilterBanner, BiblicalSearchCard, and AISearchSuggestionsPanel
// are defined in AISearchExamples.swift and are used here via import

// MARK: - Preview
#Preview {
    SearchView()
}

