//
//  PrivateCommunitiesView.swift
//  AMENAPP
//
//  Created by Steph on 1/18/26.
//
//  Smart private communities for universities, churches, and organizations
//

import SwiftUI

struct PrivateCommunitiesView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: CommunityTab = .discover
    @State private var searchText = ""
    @State private var showCreateCommunity = false
    @State private var joinedCommunities: Set<UUID> = []
    @State private var showOnboarding = true
    @State private var hasCompletedOnboarding = false
    @State private var selectedCommunityToJoin: PrivateCommunity?
    @State private var selectedCommunityToView: PrivateCommunity?
    @State private var showCodeEntry = false
    @State private var showCommunityDetail = false
    @State private var showContactSales = false
    @State private var showCommunityInsights = false
    @State private var showEventCalendar = false
    @State private var showModerationDashboard = false
    @State private var showDonationCenter = false
    @State private var showVolunteerHub = false
    @State private var showLanguageSettings = false
    @Namespace private var tabAnimation
    
    enum CommunityTab: String, CaseIterable {
        case discover = "Discover"
        case myCommunities = "My Communities"
        case featured = "Featured"
        
        var icon: String {
            switch self {
            case .discover: return "compass.fill"
            case .myCommunities: return "person.2.fill"
            case .featured: return "star.fill"
            }
        }
    }
    
    var filteredCommunities: [PrivateCommunity] {
        var communities = allCommunities
        
        if selectedTab == .myCommunities {
            communities = communities.filter { joinedCommunities.contains($0.id) }
        } else if selectedTab == .featured {
            communities = communities.filter { $0.isFeatured }
        }
        
        if !searchText.isEmpty {
            communities = communities.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                $0.type.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return communities
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Custom Header with Liquid Glass
                communityHeader
                
                // Search Bar
                searchBar
                
                // Tab Selector
                tabSelector
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        // Show insights and CTA only on Discover tab
                        if selectedTab == .discover {
                            // Smart insights card
                            SmartInsightsCard()
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                ))
                            
                            // Contact Sales CTA
                            ContactSalesCTACard(onTap: {
                                showContactSales = true
                            })
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                        
                        // My Communities stats header
                        if selectedTab == .myCommunities && !joinedCommunities.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Your Communities")
                                        .font(.custom("OpenSans-Bold", size: 20))
                                    
                                    Text("\(joinedCommunities.count) joined")
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            ))
                        }
                        
                        // Communities grid
                        if filteredCommunities.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(filteredCommunities) { community in
                                    PrivateCommunityCard(
                                        community: community,
                                        isJoined: joinedCommunities.contains(community.id),
                                        onJoin: {
                                            if joinedCommunities.contains(community.id) {
                                                // Already joined, open detail
                                                selectedCommunityToView = community
                                                showCommunityDetail = true
                                            } else {
                                                // Not joined, show code entry
                                                selectedCommunityToJoin = community
                                                showCodeEntry = true
                                            }
                                        },
                                        onTap: {
                                            selectedCommunityToView = community
                                            showCommunityDetail = true
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
                }
            }
            .blur(radius: showOnboarding ? 10 : 0)
            .disabled(showOnboarding)
            
            // Onboarding overlay
            if showOnboarding && !hasCompletedOnboarding {
                CommunityOnboardingView(
                    onComplete: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            hasCompletedOnboarding = true
                            showOnboarding = false
                        }
                    },
                    onSkip: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            hasCompletedOnboarding = true
                            showOnboarding = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showCodeEntry) {
            if let community = selectedCommunityToJoin {
                CommunityCodeEntryView(
                    community: community,
                    onSuccess: {
                        joinCommunity(community)
                        showCodeEntry = false
                    }
                )
            }
        }
        .sheet(isPresented: $showCreateCommunity) {
            CreateCommunityView()
        }
        .sheet(isPresented: $showContactSales) {
            ContactSalesView()
        }
        .sheet(isPresented: $showCommunityInsights) {
            ComingSoonPlaceholder(
                title: "Community Insights",
                icon: "chart.bar.fill",
                iconColor: .purple,
                description: "Get detailed analytics and insights about your community engagement, growth trends, and member activity."
            )
        }
        .sheet(isPresented: $showEventCalendar) {
            ComingSoonPlaceholder(
                title: "Event Calendar",
                icon: "calendar",
                iconColor: .blue,
                description: "Schedule and manage community events, worship services, Bible studies, and social gatherings all in one place."
            )
        }
        .sheet(isPresented: $showModerationDashboard) {
            ComingSoonPlaceholder(
                title: "Moderation Dashboard",
                icon: "shield.checkered",
                iconColor: .red,
                description: "Powerful tools to keep your community safe and welcoming with content moderation, reporting, and automated filters."
            )
        }
        .sheet(isPresented: $showDonationCenter) {
            ComingSoonPlaceholder(
                title: "Donation Center",
                icon: "heart.circle.fill",
                iconColor: .pink,
                description: "Enable secure online giving for tithes, offerings, and special projects with integrated payment processing."
            )
        }
        .sheet(isPresented: $showVolunteerHub) {
            ComingSoonPlaceholder(
                title: "Volunteer Hub",
                icon: "hand.raised.fill",
                iconColor: .orange,
                description: "Coordinate volunteer opportunities, track service hours, and recognize your community's servants."
            )
        }
        .sheet(isPresented: $showLanguageSettings) {
            ComingSoonPlaceholder(
                title: "Language Settings",
                icon: "globe",
                iconColor: .green,
                description: "Support multiple languages to make your community accessible to everyone. Coming soon with 50+ language options."
            )
        }
        .fullScreenCover(isPresented: $showCommunityDetail) {
            if let community = selectedCommunityToView {
                CommunityDetailView(
                    community: community,
                    isJoined: joinedCommunities.contains(community.id)
                )
            }
        }
    }
    
    // MARK: - Header
    private var communityHeader: some View {
        VStack(spacing: 12) {
            HStack {
                // Back button
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(
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
                        
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Communities")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text("\(filteredCommunities.count) Available")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Menu with options
                Menu {
                    Button {
                        showCreateCommunity = true
                    } label: {
                        Label("Create Community", systemImage: "plus.circle.fill")
                    }
                    
                    Divider()
                    
                    // ✅ Coming Soon Features
                    Button {
                        showEventCalendar = true
                    } label: {
                        HStack {
                            Label("Event Calendar", systemImage: "calendar")
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Button {
                        showModerationDashboard = true
                    } label: {
                        HStack {
                            Label("Moderation Dashboard", systemImage: "shield.checkered")
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Button {
                        showDonationCenter = true
                    } label: {
                        HStack {
                            Label("Donation Center", systemImage: "heart.circle.fill")
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Button {
                        showVolunteerHub = true
                    } label: {
                        HStack {
                            Label("Volunteer Hub", systemImage: "hand.raised.fill")
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        showContactSales = true
                    } label: {
                        Label("Contact Sales Team", systemImage: "envelope.fill")
                    }
                    
                    Button {
                        showCommunityInsights = true
                    } label: {
                        HStack {
                            Label("Community Insights", systemImage: "chart.bar.fill")
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Button {
                        showLanguageSettings = true
                    } label: {
                        HStack {
                            Label("Language Settings", systemImage: "globe")
                            Spacer()
                            Text("Coming Soon")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.blue.opacity(0.3),
                                                Color.cyan.opacity(0.3)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search communities", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 16))
            
            if !searchText.isEmpty {
                Button {
                    withAnimation {
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(CommunityTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedTab = tab
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? .white : .primary)
                        
                        if selectedTab == tab {
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, selectedTab == tab ? 20 : 16)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if selectedTab == tab {
                                Capsule()
                                    .fill(Color.black)
                                    .matchedGeometryEffect(id: "selectedTab", in: tabAnimation)
                                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            
            Text(selectedTab == .myCommunities ? "No Communities Yet" : "No Results")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text(selectedTab == .myCommunities ? "Join a community to get started" : "Try adjusting your search")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
    
    // MARK: - Actions
    private func joinCommunity(_ community: PrivateCommunity) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            joinedCommunities.insert(community.id)
        }
        
        // Provide haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // After joining, switch to My Communities tab after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                selectedTab = .myCommunities
            }
        }
    }
    
    private func toggleJoin(_ community: PrivateCommunity) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if joinedCommunities.contains(community.id) {
                joinedCommunities.remove(community.id)
            } else {
                joinedCommunities.insert(community.id)
            }
        }
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
}

// MARK: - Smart Insights Card
struct SmartInsightsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Communities")
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text("Powered by AI & Faith")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                SmartFeatureBadge(
                    icon: "brain.head.profile",
                    text: "AI-powered content moderation",
                    color: .blue
                )
                
                SmartFeatureBadge(
                    icon: "bell.badge.fill",
                    text: "Smart notifications for events",
                    color: .orange
                )
                
                SmartFeatureBadge(
                    icon: "message.badge.filled.fill",
                    text: "Real-time group chats",
                    color: .green
                )
                
                SmartFeatureBadge(
                    icon: "calendar.badge.clock",
                    text: "Automated event reminders",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .padding(.horizontal, 20)
    }
}

struct SmartFeatureBadge: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Community Card
struct PrivateCommunityCard: View {
    let community: PrivateCommunity
    let isJoined: Bool
    let onJoin: () -> Void
    let onTap: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        Button {
            if isJoined {
                onTap()
            }
        } label: {
            cardContent
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var cardContent: some View {
        VStack(spacing: 0) {
            // Hero section with gradient
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: community.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 120)
                
                // Icon overlay
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: community.type.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                    }
                    .padding(20)
                }
                
                // Badges
                HStack(spacing: 8) {
                    if community.isFeatured {
                        Badge(text: "Featured", color: .yellow)
                    }
                    
                    if community.isVerified {
                        Badge(text: "Verified", color: .blue)
                    }
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            // Content
            VStack(alignment: .leading, spacing: 14) {
                // Title and type
                VStack(alignment: .leading, spacing: 8) {
                    Text(community.name)
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.primary)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: community.type.icon)
                                .font(.system(size: 12))
                            Text(community.type.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                        .foregroundStyle(community.type.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(community.type.color.opacity(0.1))
                        )
                        
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12))
                            Text("\(community.memberCount) members")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                
                Text(community.description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .lineLimit(isExpanded ? nil : 2)
                
                // Smart features grid
                if isExpanded {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Community Features")
                            .font(.custom("OpenSans-Bold", size: 16))
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(community.features, id: \.self) { feature in
                                FeatureBadge(feature: feature)
                            }
                        }
                    }
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        onJoin()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isJoined ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.system(size: 18))
                            
                            Text(isJoined ? "Joined" : "Join Community")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        .foregroundStyle(isJoined ? .green : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    isJoined ?
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.1), Color.green.opacity(0.1)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color.black, Color.black],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isJoined ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
                                )
                                .shadow(
                                    color: isJoined ? .green.opacity(0.2) : .black.opacity(0.2),
                                    radius: 8,
                                    y: 4
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "info.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 20)
    }
}

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
            Text(text)
                .font(.custom("OpenSans-Bold", size: 11))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
}

struct FeatureBadge: View {
    let feature: CommunityFeature
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: feature.icon)
                .font(.system(size: 14))
                .foregroundStyle(feature.color)
            
            Text(feature.name)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Models
struct PrivateCommunity: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let type: CommunityType
    let memberCount: Int
    let gradientColors: [Color]
    let isFeatured: Bool
    let isVerified: Bool
    let features: [CommunityFeature]
}

enum CommunityType: String, CaseIterable {
    case university = "University"
    case church = "Church"
    case organization = "Organization"
    
    var icon: String {
        switch self {
        case .university: return "graduationcap.fill"
        case .church: return "building.2.fill"
        case .organization: return "building.columns.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .university: return .blue
        case .church: return .purple
        case .organization: return .green
        }
    }
}

struct CommunityFeature: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CommunityFeature, rhs: CommunityFeature) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Sample Data
let allCommunities = [
    // Universities
    PrivateCommunity(
        name: "Colorado Christian University",
        description: "Connect with CCU students, join Bible studies, share prayer requests, and stay updated on campus ministry events.",
        type: .university,
        memberCount: 1247,
        gradientColors: [.blue, .cyan],
        isFeatured: true,
        isVerified: true,
        features: [
            CommunityFeature(name: "Group Chat", icon: "message.fill", color: .blue),
            CommunityFeature(name: "Events", icon: "calendar", color: .green),
            CommunityFeature(name: "Prayer Wall", icon: "hands.sparkles", color: .purple),
            CommunityFeature(name: "Resources", icon: "book.fill", color: .orange)
        ]
    ),
    PrivateCommunity(
        name: "Grand Canyon University",
        description: "GCU's faith community for students and alumni. Join worship nights, mission trips planning, and daily devotionals.",
        type: .university,
        memberCount: 2156,
        gradientColors: [.purple, .pink],
        isFeatured: true,
        isVerified: true,
        features: [
            CommunityFeature(name: "Live Worship", icon: "music.note", color: .pink),
            CommunityFeature(name: "Small Groups", icon: "person.3.fill", color: .blue),
            CommunityFeature(name: "Missions", icon: "globe", color: .green),
            CommunityFeature(name: "Mentorship", icon: "person.2.fill", color: .orange)
        ]
    ),
    
    // Churches
    PrivateCommunity(
        name: "Bethel Church",
        description: "Bethel's official community space. Access sermon notes, connect with life groups, and stay informed about church events.",
        type: .church,
        memberCount: 3542,
        gradientColors: [.purple, .blue],
        isFeatured: true,
        isVerified: true,
        features: [
            CommunityFeature(name: "Sermon Notes", icon: "note.text", color: .purple),
            CommunityFeature(name: "Life Groups", icon: "person.3.fill", color: .blue),
            CommunityFeature(name: "Giving", icon: "heart.fill", color: .red),
            CommunityFeature(name: "Kids Ministry", icon: "figure.and.child.holdinghands", color: .orange)
        ]
    ),
    PrivateCommunity(
        name: "Pillar Church - Scottsdale",
        description: "Join Pillar's Scottsdale campus community. Connect with your small group, volunteer for ministries, and grow in faith together.",
        type: .church,
        memberCount: 1823,
        gradientColors: [.orange, .red],
        isFeatured: true,
        isVerified: true,
        features: [
            CommunityFeature(name: "Small Groups", icon: "person.3.fill", color: .orange),
            CommunityFeature(name: "Volunteer", icon: "hand.raised.fill", color: .blue),
            CommunityFeature(name: "Youth Ministry", icon: "figure.wave", color: .green),
            CommunityFeature(name: "Prayer Chain", icon: "link", color: .purple)
        ]
    ),
    PrivateCommunity(
        name: "Elevation Church",
        description: "Elevation's digital gathering place. Watch live services, join discussion groups, and connect with your campus.",
        type: .church,
        memberCount: 4521,
        gradientColors: [.green, .teal],
        isFeatured: false,
        isVerified: true,
        features: [
            CommunityFeature(name: "Live Stream", icon: "video.fill", color: .red),
            CommunityFeature(name: "Discussions", icon: "bubble.left.and.bubble.right.fill", color: .blue),
            CommunityFeature(name: "Campus Groups", icon: "mappin.and.ellipse", color: .green),
            CommunityFeature(name: "Serve Team", icon: "person.fill.checkmark", color: .orange)
        ]
    ),
    
    // Organizations
    PrivateCommunity(
        name: "Young Life",
        description: "Connect with Young Life leaders and students. Plan events, share resources, and encourage one another in ministry.",
        type: .organization,
        memberCount: 2847,
        gradientColors: [.green, .mint],
        isFeatured: true,
        isVerified: true,
        features: [
            CommunityFeature(name: "Event Planning", icon: "calendar.badge.plus", color: .green),
            CommunityFeature(name: "Leader Chat", icon: "message.fill", color: .blue),
            CommunityFeature(name: "Resources", icon: "folder.fill", color: .orange),
            CommunityFeature(name: "Training", icon: "graduationcap.fill", color: .purple)
        ]
    ),
    PrivateCommunity(
        name: "Cru (Campus Crusade)",
        description: "Cru's global community for reaching students with the gospel. Join mission teams, access training, and collaborate worldwide.",
        type: .organization,
        memberCount: 5632,
        gradientColors: [.blue, .purple],
        isFeatured: false,
        isVerified: true,
        features: [
            CommunityFeature(name: "Missions", icon: "globe.americas.fill", color: .blue),
            CommunityFeature(name: "Training Hub", icon: "book.fill", color: .green),
            CommunityFeature(name: "Team Chat", icon: "message.fill", color: .purple),
            CommunityFeature(name: "Prayer Network", icon: "hands.sparkles", color: .orange)
        ]
    ),
    PrivateCommunity(
        name: "Fellowship of Christian Athletes",
        description: "FCA's community for athletes and coaches. Share testimonies, organize huddles, and inspire each other through sport and faith.",
        type: .organization,
        memberCount: 1956,
        gradientColors: [.orange, .yellow],
        isFeatured: false,
        isVerified: true,
        features: [
            CommunityFeature(name: "Huddles", icon: "sportscourt.fill", color: .orange),
            CommunityFeature(name: "Testimonies", icon: "quote.bubble.fill", color: .blue),
            CommunityFeature(name: "Coaches Corner", icon: "person.fill.checkmark", color: .green),
            CommunityFeature(name: "Events", icon: "calendar", color: .purple)
        ]
    ),
    PrivateCommunity(
        name: "InterVarsity Christian Fellowship",
        description: "InterVarsity's hub for college ministry. Connect with chapters nationwide, access Bible studies, and join mission initiatives.",
        type: .organization,
        memberCount: 3421,
        gradientColors: [.indigo, .blue],
        isFeatured: false,
        isVerified: true,
        features: [
            CommunityFeature(name: "Chapter Network", icon: "network", color: .blue),
            CommunityFeature(name: "Bible Studies", icon: "book.fill", color: .green),
            CommunityFeature(name: "Missions", icon: "airplane", color: .orange),
            CommunityFeature(name: "Conferences", icon: "person.3.fill", color: .purple)
        ]
    )
]

// MARK: - Community Onboarding View
struct CommunityOnboardingView: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    @State private var currentPage = 0
    @State private var isAnimating = false
    
    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "person.3.fill",
            title: "Welcome to Communities",
            description: "Connect with your university, church, or organization in a private, faith-centered space.",
            gradientColors: [.blue, .cyan]
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "Secure & Private",
            description: "Join communities with unique access codes. Your data is protected and your conversations stay private.",
            gradientColors: [.purple, .pink]
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "Smart Features",
            description: "AI-powered moderation, smart notifications, automated event reminders, and real-time group chats.",
            gradientColors: [.green, .mint]
        ),
        OnboardingPage(
            icon: "heart.fill",
            title: "Grow Together",
            description: "Share prayer requests, join Bible studies, attend events, and build meaningful connections.",
            gradientColors: [.orange, .red]
        )
    ]
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Prevent dismissal
                }
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        onSkip()
                    } label: {
                        Text("Skip")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 500)
                
                // Custom page indicator
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(currentPage == index ? Color.white : Color.white.opacity(0.3))
                            .frame(width: currentPage == index ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.vertical, 20)
                
                // Action button
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    
                    if currentPage < pages.count - 1 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentPage += 1
                        }
                    } else {
                        onComplete()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                            .font(.custom("OpenSans-Bold", size: 18))
                        
                        Image(systemName: currentPage < pages.count - 1 ? "arrow.right" : "checkmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: pages[currentPage].gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: pages[currentPage].gradientColors[0].opacity(0.4), radius: 12, y: 6)
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
                
                Spacer()
            }
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .padding(20)
            .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let gradientColors: [Color]
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                page.gradientColors[0].opacity(0.3),
                                page.gradientColors[1].opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .animation(
                        Animation.easeInOut(duration: 2)
                            .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                
                // Icon circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: page.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: page.gradientColors[0].opacity(0.4), radius: 20, y: 10)
                
                Image(systemName: page.icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 40)
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.custom("OpenSans-Bold", size: 32))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.custom("OpenSans-Regular", size: 17))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 32)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Community Code Entry View
struct CommunityCodeEntryView: View {
    @Environment(\.dismiss) var dismiss
    let community: PrivateCommunity
    let onSuccess: () -> Void
    
    @State private var code = ""
    @State private var isValidating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isCodeFieldFocused: Bool
    
    // Valid codes for demo (in production, validate with backend)
    let validCodes = [
        "CCU2024": "Colorado Christian University",
        "GCU2024": "Grand Canyon University",
        "BETHEL24": "Bethel Church",
        "PILLAR24": "Pillar Church - Scottsdale",
        "YOUNGLIFE": "Young Life",
        "CRU2024": "Cru (Campus Crusade)"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 20)
                    
                    // Community icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: community.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: community.gradientColors[0].opacity(0.4), radius: 20, y: 10)
                        
                        Image(systemName: community.type.icon)
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(spacing: 12) {
                        Text("Join \(community.name)")
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("Enter your unique access code")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 32)
                    
                    // Code entry field
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(community.type.color)
                            
                            TextField("ACCESS CODE", text: $code)
                                .font(.custom("OpenSans-Bold", size: 18))
                                .textCase(.uppercase)
                                .autocorrectionDisabled()
                                .focused($isCodeFieldFocused)
                                .onChange(of: code) { _ in
                                    code = code.uppercased()
                                    showError = false
                                }
                        }
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            showError ? Color.red : (isCodeFieldFocused ? community.type.color : Color.clear),
                                            lineWidth: 2
                                        )
                                )
                        )
                        
                        if showError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14))
                                Text(errorMessage)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
                            }
                            .foregroundStyle(.red)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Info card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.blue)
                            
                            Text("How to get your code")
                                .font(.custom("OpenSans-Bold", size: 16))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            NumberedInfoRow(
                                number: 1,
                                text: "Contact your organization administrator"
                            )
                            NumberedInfoRow(
                                number: 2,
                                text: "Request access to the digital community"
                            )
                            NumberedInfoRow(
                                number: 3,
                                text: "Receive your unique 6-8 character code"
                            )
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.blue.opacity(0.1))
                    )
                    .padding(.horizontal, 32)
                    
                    // Demo codes (for testing - remove in production)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.purple)
                            
                            Text("Demo Codes (Testing Only)")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.purple)
                        }
                        
                        ForEach(Array(validCodes.keys.sorted()), id: \.self) { key in
                            Button {
                                code = key
                            } label: {
                                HStack {
                                    Text(key)
                                        .font(.custom("OpenSans-Bold", size: 13))
                                    Text("→")
                                    Text(validCodes[key] ?? "")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                    Spacer()
                                }
                                .foregroundStyle(.purple)
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.05))
                    )
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Join button
                    Button {
                        validateAndJoin()
                    } label: {
                        HStack(spacing: 10) {
                            if isValidating {
                                ProgressView()
                                    .tint(.white)
                                Text("Validating...")
                            } else {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.system(size: 18))
                                Text("Verify & Join")
                            }
                        }
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    code.isEmpty ?
                                    LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(
                                        colors: community.gradientColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(
                                    color: code.isEmpty ? .clear : community.gradientColors[0].opacity(0.4),
                                    radius: 12,
                                    y: 6
                                )
                        )
                    }
                    .disabled(code.isEmpty || isValidating)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Access Code")
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isCodeFieldFocused = true
            }
        }
    }
    
    private func validateAndJoin() {
        isValidating = true
        showError = false
        
        // Simulate API validation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if validCodes[code] != nil {
                // Success
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                isValidating = false
                onSuccess()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    dismiss()
                }
            } else {
                // Error
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
                
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isValidating = false
                    showError = true
                    errorMessage = "Invalid code. Please check and try again."
                    code = ""
                }
            }
        }
    }
}

struct NumberedInfoRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Text("\(number)")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.blue)
            }
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Create Community View
struct CreateCommunityView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var communityName = ""
    @State private var communityDescription = ""
    @State private var selectedType: CommunityType = .university
    @State private var accessCode = ""
    @State private var enableAutoModeration = true
    @State private var enableSmartNotifications = true
    @State private var enablePrayerWall = true
    @State private var enableEvents = true
    @State private var isCreating = false
    @FocusState private var focusedField: CreateCommunityField?
    
    enum CreateCommunityField {
        case name, description, accessCode
    }
    
    var isFormValid: Bool {
        !communityName.isEmpty &&
        !communityDescription.isEmpty &&
        !accessCode.isEmpty &&
        accessCode.count >= 6
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [selectedType.color, selectedType.color.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: selectedType.icon)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Create Community")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Build your private faith community")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Form
                    VStack(spacing: 24) {
                        // Community Name
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Community Name", systemImage: "tag.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("e.g., Colorado Christian University", text: $communityName)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    focusedField == .name ? selectedType.color : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                )
                                .focused($focusedField, equals: .name)
                        }
                        
                        // Community Type
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Community Type", systemImage: "building.2.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(CommunityType.allCases, id: \.self) { type in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedType = type
                                        }
                                        let haptic = UIImpactFeedbackGenerator(style: .light)
                                        haptic.impactOccurred()
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: type.icon)
                                                .font(.system(size: 24))
                                            
                                            Text(type.rawValue)
                                                .font(.custom("OpenSans-SemiBold", size: 12))
                                        }
                                        .foregroundStyle(selectedType == type ? .white : type.color)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(
                                                    LinearGradient(
                                                        colors: selectedType == type ?
                                                            [type.color, type.color.opacity(0.8)] :
                                                            [Color(.systemGray6), Color(.systemGray6)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Description", systemImage: "text.alignleft")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            ZStack(alignment: .topLeading) {
                                if communityDescription.isEmpty {
                                    Text("Describe your community and what members can expect...")
                                        .font(.custom("OpenSans-Regular", size: 16))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 16)
                                }
                                
                                TextEditor(text: $communityDescription)
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .frame(height: 120)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(
                                                        focusedField == .description ? selectedType.color : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )
                                    )
                                    .focused($focusedField, equals: .description)
                            }
                        }
                        
                        // Access Code
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Access Code", systemImage: "lock.shield.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                TextField("Create unique 6-8 character code", text: $accessCode)
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .textCase(.uppercase)
                                    .autocorrectionDisabled()
                                    .onChange(of: accessCode) { _ in
                                        accessCode = accessCode.uppercased()
                                    }
                                
                                Button {
                                    accessCode = generateRandomCode()
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(selectedType.color)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                focusedField == .accessCode ? selectedType.color : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            )
                            .focused($focusedField, equals: .accessCode)
                            
                            Text("Members will need this code to join")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        
                        // Features
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Community Features", systemImage: "sparkles")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            VStack(spacing: 12) {
                                FeatureToggle(
                                    icon: "brain.head.profile",
                                    title: "AI Content Moderation",
                                    description: "Smart filtering of inappropriate content",
                                    isOn: $enableAutoModeration,
                                    color: .blue
                                )
                                
                                FeatureToggle(
                                    icon: "bell.badge.fill",
                                    title: "Smart Notifications",
                                    description: "Intelligent event and prayer reminders",
                                    isOn: $enableSmartNotifications,
                                    color: .orange
                                )
                                
                                FeatureToggle(
                                    icon: "hands.sparkles",
                                    title: "Prayer Wall",
                                    description: "Shared space for prayer requests",
                                    isOn: $enablePrayerWall,
                                    color: .purple
                                )
                                
                                FeatureToggle(
                                    icon: "calendar.badge.clock",
                                    title: "Events & Calendar",
                                    description: "Community events and gatherings",
                                    isOn: $enableEvents,
                                    color: .green
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Create Button
                    Button {
                        createCommunity()
                    } label: {
                        HStack(spacing: 10) {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                                Text("Creating...")
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("Create Community")
                            }
                        }
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    isFormValid ?
                                    LinearGradient(
                                        colors: [selectedType.color, selectedType.color.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [.gray, .gray],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(
                                    color: isFormValid ? selectedType.color.opacity(0.4) : .clear,
                                    radius: 12,
                                    y: 6
                                )
                        )
                    }
                    .disabled(!isFormValid || isCreating)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
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
    }
    
    private func generateRandomCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Excluded similar looking characters
        return String((0..<8).map { _ in letters.randomElement()! })
    }
    
    private func createCommunity() {
        isCreating = true
        
        // Simulate API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            isCreating = false
            dismiss()
        }
    }
}

struct FeatureToggle: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 15))
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .tint(color)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Contact Sales CTA Card
struct ContactSalesCTACard: View {
    let onTap: () -> Void
    
    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Need Help Getting Started?")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                    
                    Text("Contact our sales team for enterprise solutions")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 20)
    }
}

// MARK: - Contact Sales View
struct ContactSalesView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var email = ""
    @State private var organization = ""
    @State private var organizationType: CommunityType = .university
    @State private var estimatedUsers = "50-100"
    @State private var message = ""
    @State private var isSubmitting = false
    @FocusState private var focusedField: ContactSalesField?
    
    enum ContactSalesField {
        case name, email, organization, message
    }
    
    let userCountOptions = ["1-50", "50-100", "100-500", "500-1000", "1000+"]
    
    var isFormValid: Bool {
        !name.isEmpty && !email.isEmpty && !organization.isEmpty && email.contains("@")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "person.2.badge.gearshape.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Contact Sales Team")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Let's build your community together")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Benefits
                    VStack(spacing: 12) {
                        SalesBenefitRow(
                            icon: "checkmark.seal.fill",
                            text: "Dedicated account manager",
                            color: .green
                        )
                        SalesBenefitRow(
                            icon: "gearshape.2.fill",
                            text: "Custom feature development",
                            color: .blue
                        )
                        SalesBenefitRow(
                            icon: "chart.line.uptrend.xyaxis",
                            text: "Advanced analytics & insights",
                            color: .purple
                        )
                        SalesBenefitRow(
                            icon: "shield.lefthalf.filled.badge.checkmark",
                            text: "Priority support & security",
                            color: .orange
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // Form
                    VStack(spacing: 20) {
                        // Name
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Your Name", systemImage: "person.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("John Doe", text: $name)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(focusedField == .name ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                )
                                .focused($focusedField, equals: .name)
                        }
                        
                        // Email
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Email Address", systemImage: "envelope.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("john@organization.com", text: $email)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(focusedField == .email ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                )
                                .focused($focusedField, equals: .email)
                        }
                        
                        // Organization
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Organization Name", systemImage: "building.2.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("Your University/Church/Organization", text: $organization)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(focusedField == .organization ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                )
                                .focused($focusedField, equals: .organization)
                        }
                        
                        // Organization Type
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Organization Type", systemImage: "square.grid.2x2.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(CommunityType.allCases, id: \.self) { type in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            organizationType = type
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: type.icon)
                                                .font(.system(size: 20))
                                            Text(type.rawValue)
                                                .font(.custom("OpenSans-SemiBold", size: 11))
                                        }
                                        .foregroundStyle(organizationType == type ? .white : type.color)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(
                                                    organizationType == type ?
                                                    type.color :
                                                    Color(.systemGray6)
                                                )
                                        )
                                    }
                                }
                            }
                        }
                        
                        // Estimated Users
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Estimated Users", systemImage: "person.3.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            Picker("Estimated Users", selection: $estimatedUsers) {
                                ForEach(userCountOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        // Message
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Additional Information (Optional)", systemImage: "text.alignleft")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            ZStack(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("Tell us about your needs and goals...")
                                        .font(.custom("OpenSans-Regular", size: 16))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 16)
                                }
                                
                                TextEditor(text: $message)
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .frame(height: 120)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(focusedField == .message ? Color.blue : Color.clear, lineWidth: 2)
                                            )
                                    )
                                    .focused($focusedField, equals: .message)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Submit Button
                    Button {
                        submitInquiry()
                    } label: {
                        HStack(spacing: 10) {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                                Text("Sending...")
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 18))
                                Text("Send Inquiry")
                            }
                        }
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    isFormValid ?
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [.gray, .gray],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: isFormValid ? .blue.opacity(0.4) : .clear, radius: 12, y: 6)
                        )
                    }
                    .disabled(!isFormValid || isSubmitting)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
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
    }
    
    private func submitInquiry() {
        isSubmitting = true
        
        // Simulate API call
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            
            isSubmitting = false
            dismiss()
        }
    }
}

struct SalesBenefitRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
            }
            
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Community Insights View
struct CommunityInsightsView: View {
    @Environment(\.dismiss) var dismiss
    let joinedCommunities: [UUID]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Community Insights")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Your faith community analytics")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Stats Cards
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            InsightStatCard(
                                icon: "person.2.fill",
                                value: "\(joinedCommunities.count)",
                                label: "Joined Communities",
                                color: .blue
                            )
                            
                            InsightStatCard(
                                icon: "calendar.badge.clock",
                                value: "12",
                                label: "Upcoming Events",
                                color: .green
                            )
                        }
                        
                        HStack(spacing: 16) {
                            InsightStatCard(
                                icon: "hands.sparkles",
                                value: "28",
                                label: "Prayer Requests",
                                color: .purple
                            )
                            
                            InsightStatCard(
                                icon: "message.fill",
                                value: "156",
                                label: "Messages Sent",
                                color: .orange
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Engagement Chart
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Weekly Engagement")
                            .font(.custom("OpenSans-Bold", size: 20))
                            .padding(.horizontal, 20)
                        
                        EngagementChartView()
                            .frame(height: 200)
                            .padding(.horizontal, 20)
                    }
                    
                    // Top Communities
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Most Active Communities")
                            .font(.custom("OpenSans-Bold", size: 20))
                            .padding(.horizontal, 20)
                        
                        VStack(spacing: 12) {
                            TopCommunityRow(
                                name: "Bethel Church",
                                engagement: 92,
                                color: .purple
                            )
                            TopCommunityRow(
                                name: "Colorado Christian University",
                                engagement: 78,
                                color: .blue
                            )
                            TopCommunityRow(
                                name: "Young Life",
                                engagement: 65,
                                color: .green
                            )
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 32)
            }
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
    }
}

struct InsightStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(.custom("OpenSans-Bold", size: 32))
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct TopCommunityRow: View {
    let name: String
    let engagement: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            
            Text(name)
                .font(.custom("OpenSans-SemiBold", size: 15))
            
            Spacer()
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(engagement) / 100, height: 8)
                }
            }
            .frame(width: 80)
            
            Text("\(engagement)%")
                .font(.custom("OpenSans-Bold", size: 14))
                .foregroundStyle(color)
                .frame(width: 45, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

struct EngagementChartView: View {
    let weeklyData = [45, 62, 58, 73, 85, 92, 78]
    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weeklyData.enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))
                                .frame(height: 150)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: CGFloat(value) * 1.5)
                        }
                        
                        Text(days[index])
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Event Calendar View
struct EventCalendarView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedDate = Date()
    @State private var showCreateEvent = false
    @State private var selectedEventType: EventType = .all
    @State private var searchText = ""
    
    enum EventType: String, CaseIterable {
        case all = "All"
        case worship = "Worship"
        case study = "Bible Study"
        case service = "Service"
        case social = "Social"
        case mission = "Mission"
        
        var icon: String {
            switch self {
            case .all: return "calendar"
            case .worship: return "music.note"
            case .study: return "book.fill"
            case .service: return "hand.raised.fill"
            case .social: return "person.3.fill"
            case .mission: return "globe.americas.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .all: return .blue
            case .worship: return .purple
            case .study: return .green
            case .service: return .orange
            case .social: return .pink
            case .mission: return .cyan
            }
        }
    }
    
    var filteredEvents: [CommunityEvent] {
        let filtered = selectedEventType == .all ? sampleEvents : sampleEvents.filter { $0.type == selectedEventType }
        
        if searchText.isEmpty {
            return filtered
        } else {
            return filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search events", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 16))
                    
                    if !searchText.isEmpty {
                        Button {
                            withAnimation {
                                searchText = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Event type filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(EventType.allCases, id: \.self) { type in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedEventType = type
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: type.icon)
                                        .font(.system(size: 14))
                                    Text(type.rawValue)
                                        .font(.custom("OpenSans-SemiBold", size: 14))
                                }
                                .foregroundStyle(selectedEventType == type ? .white : type.color)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(
                                            selectedEventType == type ?
                                            type.color :
                                            Color(.systemGray6)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 12)
                
                // Calendar mini view
                VStack(spacing: 12) {
                    HStack {
                        Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                            .font(.custom("OpenSans-Bold", size: 18))
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button {
                                withAnimation {
                                    selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color(.systemGray6)))
                            }
                            
                            Button {
                                withAnimation {
                                    selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color(.systemGray6)))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 12)
                
                // Events list
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredEvents) { event in
                            EventCard(event: event)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Event Calendar")
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
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateEvent = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                    }
                }
            }
            .sheet(isPresented: $showCreateEvent) {
                CreateEventView()
            }
        }
    }
}

struct CommunityEvent: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let date: Date
    let location: String
    let type: EventCalendarView.EventType
    let attendees: Int
    let maxAttendees: Int?
    let isRSVPed: Bool
}

let sampleEvents = [
    CommunityEvent(
        title: "Sunday Morning Worship",
        description: "Join us for uplifting worship and inspiring message",
        date: Date().addingTimeInterval(86400 * 2),
        location: "Main Sanctuary",
        type: .worship,
        attendees: 245,
        maxAttendees: 300,
        isRSVPed: true
    ),
    CommunityEvent(
        title: "Wednesday Night Bible Study",
        description: "Deep dive into the book of Romans",
        date: Date().addingTimeInterval(86400 * 3),
        location: "Fellowship Hall",
        type: .study,
        attendees: 32,
        maxAttendees: 50,
        isRSVPed: false
    ),
    CommunityEvent(
        title: "Community Service Day",
        description: "Serve at local food bank and homeless shelter",
        date: Date().addingTimeInterval(86400 * 5),
        location: "City Food Bank",
        type: .service,
        attendees: 18,
        maxAttendees: 25,
        isRSVPed: true
    ),
    CommunityEvent(
        title: "College & Career Social",
        description: "Pizza, games, and fellowship for young adults",
        date: Date().addingTimeInterval(86400 * 6),
        location: "Student Center",
        type: .social,
        attendees: 42,
        maxAttendees: nil,
        isRSVPed: false
    ),
    CommunityEvent(
        title: "Mission Trip Fundraiser",
        description: "Support our upcoming Guatemala mission trip",
        date: Date().addingTimeInterval(86400 * 8),
        location: "Church Courtyard",
        type: .mission,
        attendees: 67,
        maxAttendees: nil,
        isRSVPed: true
    )
]

struct EventCard: View {
    let event: CommunityEvent
    @State private var isRSVPed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                // Date badge
                VStack(spacing: 4) {
                    Text(event.date.formatted(.dateTime.month(.abbreviated)))
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(.white)
                    Text(event.date.formatted(.dateTime.day()))
                        .font(.custom("OpenSans-Bold", size: 24))
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [event.type.color, event.type.color.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: event.type.icon)
                            .font(.system(size: 12))
                        Text(event.type.rawValue)
                            .font(.custom("OpenSans-SemiBold", size: 12))
                    }
                    .foregroundStyle(event.type.color)
                    
                    Text(event.title)
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.primary)
                    
                    Text(event.description)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            
            Divider()
            
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                    Text(event.date.formatted(.dateTime.hour().minute()))
                        .font(.custom("OpenSans-Regular", size: 13))
                }
                .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14))
                    Text(event.location)
                        .font(.custom("OpenSans-Regular", size: 13))
                }
                .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                    Text("\(event.attendees)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                    if let max = event.maxAttendees {
                        Text("/ \(max)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isRSVPed.toggle()
                }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isRSVPed ? "checkmark.circle.fill" : "calendar.badge.plus")
                        .font(.system(size: 16))
                    Text(isRSVPed ? "RSVP'd" : "RSVP")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(isRSVPed ? .green : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: isRSVPed ?
                                    [Color.green.opacity(0.1), Color.green.opacity(0.1)] :
                                    [event.type.color, event.type.color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isRSVPed ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
                        )
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
        .padding(.horizontal, 20)
        .onAppear {
            isRSVPed = event.isRSVPed
        }
    }
}

// MARK: - Moderation Dashboard View
struct ModerationDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Moderation Dashboard")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("AI-powered content safety")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Stats
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            ModerationStatCard(
                                icon: "checkmark.shield.fill",
                                value: "98.5%",
                                label: "Content Approved",
                                color: .green
                            )
                            
                            ModerationStatCard(
                                icon: "exclamationmark.triangle.fill",
                                value: "12",
                                label: "Flagged Items",
                                color: .orange
                            )
                        }
                        
                        HStack(spacing: 16) {
                            ModerationStatCard(
                                icon: "brain.head.profile",
                                value: "AI",
                                label: "Auto-Moderated",
                                color: .blue
                            )
                            
                            ModerationStatCard(
                                icon: "person.fill.checkmark",
                                value: "156",
                                label: "Reviews Today",
                                color: .purple
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Text("Coming Soon: Full moderation tools")
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 40)
                }
                .padding(.bottom, 32)
            }
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
    }
}

struct ModerationStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(.custom("OpenSans-Bold", size: 28))
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Donation Center View
struct DonationCenterView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.pink, .red],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Donation Center")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Support your community")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 16) {
                        DonationCampaignCard(
                            title: "Mission Trip Fund",
                            description: "Help send students to Guatemala",
                            raised: 8500,
                            goal: 15000,
                            color: .blue
                        )
                        
                        DonationCampaignCard(
                            title: "Building Renovation",
                            description: "Upgrade our youth center",
                            raised: 23000,
                            goal: 50000,
                            color: .green
                        )
                        
                        DonationCampaignCard(
                            title: "Scholarship Fund",
                            description: "Support students in need",
                            raised: 12000,
                            goal: 20000,
                            color: .purple
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
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
    }
}

struct DonationCampaignCard: View {
    let title: String
    let description: String
    let raised: Int
    let goal: Int
    let color: Color
    
    var progress: Double {
        Double(raised) / Double(goal)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("$\(raised)")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(color)
                    
                    Text("of $\(goal)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(height: 12)
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [color, color.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress, height: 12)
                    }
                }
                .frame(height: 12)
            }
            
            Button {
                // Donate action
            } label: {
                HStack {
                    Image(systemName: "heart.fill")
                    Text("Donate Now")
                        .font(.custom("OpenSans-Bold", size: 16))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [color, color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Volunteer Hub View
struct VolunteerHubView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Volunteer Hub")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Serve your community")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 16) {
                        VolunteerOpportunityCard(
                            title: "Sunday Worship Team",
                            description: "Help with setup and tech support",
                            time: "Sundays 8:00 AM - 12:00 PM",
                            volunteers: 12,
                            needed: 15,
                            color: .purple
                        )
                        
                        VolunteerOpportunityCard(
                            title: "Youth Ministry Helper",
                            description: "Assist with Wednesday night programs",
                            time: "Wednesdays 6:00 PM - 9:00 PM",
                            volunteers: 8,
                            needed: 10,
                            color: .blue
                        )
                        
                        VolunteerOpportunityCard(
                            title: "Community Outreach",
                            description: "Food bank and homeless shelter",
                            time: "Saturdays 9:00 AM - 2:00 PM",
                            volunteers: 18,
                            needed: 20,
                            color: .green
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
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
    }
}

struct VolunteerOpportunityCard: View {
    let title: String
    let description: String
    let time: String
    let volunteers: Int
    let needed: Int
    let color: Color
    @State private var isSignedUp = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 18))
                    
                    Text(description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14))
                Text(time)
                    .font(.custom("OpenSans-Regular", size: 14))
            }
            .foregroundStyle(.secondary)
            
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                Text("\(volunteers) / \(needed) volunteers")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                
                Spacer()
                
                let progress = Double(volunteers) / Double(needed)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geometry.size.width * progress, height: 8)
                    }
                }
                .frame(width: 80, height: 8)
            }
            .foregroundStyle(.primary)
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isSignedUp.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isSignedUp ? "checkmark.circle.fill" : "hand.thumbsup.fill")
                    Text(isSignedUp ? "Signed Up" : "Sign Up")
                        .font(.custom("OpenSans-Bold", size: 16))
                }
                .foregroundStyle(isSignedUp ? .green : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: isSignedUp ?
                                    [Color.green.opacity(0.1), Color.green.opacity(0.1)] :
                                    [color, color.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSignedUp ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
                        )
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Language Settings View
struct LanguageSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedLanguage = "English"
    
    let languages = [
        "English", "Spanish", "French", "German", "Italian",
        "Portuguese", "Chinese", "Japanese", "Korean", "Arabic"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "globe")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Language Settings")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Choose your preferred language")
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 12) {
                        ForEach(languages, id: \.self) { language in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedLanguage = language
                                }
                            } label: {
                                HStack {
                                    Text(language)
                                        .font(.custom("OpenSans-SemiBold", size: 16))
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    if selectedLanguage == language {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            selectedLanguage == language ?
                                            Color.blue.opacity(0.1) :
                                            Color(.systemGray6)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(
                                                    selectedLanguage == language ?
                                                    Color.blue.opacity(0.3) :
                                                    Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 32)
            }
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
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }
}

struct CreateEventView: View {
    @Environment(\.dismiss) var dismiss
    @State private var eventTitle = ""
    @State private var eventDescription = ""
    @State private var eventDate = Date()
    @State private var eventLocation = ""
    @State private var selectedType: EventCalendarView.EventType = .worship
    @State private var maxAttendees = ""
    @State private var enableReminders = true
    @State private var isCreating = false
    
    var isFormValid: Bool {
        !eventTitle.isEmpty && !eventDescription.isEmpty && !eventLocation.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [selectedType.color, selectedType.color.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: selectedType.icon)
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        
                        Text("Create Event")
                            .font(.custom("OpenSans-Bold", size: 28))
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 20) {
                        // Event Title
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Event Title", systemImage: "text.cursor")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("e.g., Sunday Morning Worship", text: $eventTitle)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        // Event Type
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Event Type", systemImage: "tag.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach([EventCalendarView.EventType.worship, .study, .service, .social, .mission], id: \.self) { type in
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedType = type
                                            }
                                        } label: {
                                            VStack(spacing: 6) {
                                                Image(systemName: type.icon)
                                                    .font(.system(size: 20))
                                                Text(type.rawValue)
                                                    .font(.custom("OpenSans-SemiBold", size: 12))
                                            }
                                            .foregroundStyle(selectedType == type ? .white : type.color)
                                            .frame(width: 90)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(selectedType == type ? type.color : Color(.systemGray6))
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Description", systemImage: "text.alignleft")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextEditor(text: $eventDescription)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .frame(height: 100)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        // Date & Time
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Date & Time", systemImage: "calendar.badge.clock")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            DatePicker("", selection: $eventDate)
                                .datePickerStyle(.compact)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        // Location
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Location", systemImage: "mappin.circle.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("e.g., Main Sanctuary", text: $eventLocation)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        // Max Attendees (Optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Max Attendees (Optional)", systemImage: "person.2.fill")
                                .font(.custom("OpenSans-Bold", size: 14))
                                .foregroundStyle(.secondary)
                            
                            TextField("Leave empty for unlimited", text: $maxAttendees)
                                .font(.custom("OpenSans-Regular", size: 16))
                                .keyboardType(.numberPad)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                        
                        // Reminders Toggle
                        Toggle(isOn: $enableReminders) {
                            HStack(spacing: 10) {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Smart Reminders")
                                        .font(.custom("OpenSans-Bold", size: 15))
                                    Text("Notify members before event")
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(selectedType.color)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6).opacity(0.5))
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // Create Button
                    Button {
                        createEvent()
                    } label: {
                        HStack(spacing: 10) {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                                Text("Creating...")
                            } else {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 18))
                                Text("Create Event")
                            }
                        }
                        .font(.custom("OpenSans-Bold", size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    isFormValid ?
                                    LinearGradient(
                                        colors: [selectedType.color, selectedType.color.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing)
                                )
                                .shadow(color: isFormValid ? selectedType.color.opacity(0.4) : .clear, radius: 12, y: 6)
                        )
                    }
                    .disabled(!isFormValid || isCreating)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
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
    }
    
    private func createEvent() {
        isCreating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let haptic = UINotificationFeedbackGenerator()
            haptic.notificationOccurred(.success)
            isCreating = false
            dismiss()
        }
    }
}

// MARK: - Supporting Models for Community Detail
struct ChatMessage: Identifiable {
    let id: UUID
    let sender: String
    let text: String
    let timestamp: Date
    let isCurrentUser: Bool
}

struct CommunityPrayerRequest: Identifiable {
    let id = UUID()
    let author: String
    let text: String
    let timestamp: Date
    let prayerCount: Int
}

struct CommunityResource: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
}

// MARK: - Sample Data
let sampleMessages: [ChatMessage] = [
    ChatMessage(
        id: UUID(),
        sender: "Sarah Johnson",
        text: "Looking forward to Sunday's service! 🙏",
        timestamp: Date().addingTimeInterval(-3600),
        isCurrentUser: false
    ),
    ChatMessage(
        id: UUID(),
        sender: "Michael Chen",
        text: "Don't forget about the Bible study tonight at 7pm!",
        timestamp: Date().addingTimeInterval(-1800),
        isCurrentUser: false
    ),
    ChatMessage(
        id: UUID(),
        sender: "You",
        text: "I'll be there! Can't wait to discuss Romans chapter 8.",
        timestamp: Date().addingTimeInterval(-900),
        isCurrentUser: true
    )
]

let samplePrayerRequests: [CommunityPrayerRequest] = [
    CommunityPrayerRequest(
        author: "Emily Rodriguez",
        text: "Please pray for my grandmother who is recovering from surgery. She's doing better but still has a long recovery ahead.",
        timestamp: Date().addingTimeInterval(-7200),
        prayerCount: 24
    ),
    CommunityPrayerRequest(
        author: "David Thompson",
        text: "Asking for prayers as I prepare for final exams next week. Feeling stressed but trusting in God's plan.",
        timestamp: Date().addingTimeInterval(-14400),
        prayerCount: 18
    ),
    CommunityPrayerRequest(
        author: "Jessica Martinez",
        text: "Praying for our community as we prepare for the upcoming mission trip to Guatemala. May God use us to bless others.",
        timestamp: Date().addingTimeInterval(-21600),
        prayerCount: 42
    )
]

let sampleResources: [CommunityResource] = [
    CommunityResource(
        title: "Sunday Sermon Notes",
        description: "Access notes and discussion questions from recent sermons",
        icon: "doc.text.fill"
    ),
    CommunityResource(
        title: "Bible Reading Plan",
        description: "Join our community in reading through the Bible together",
        icon: "book.fill"
    ),
    CommunityResource(
        title: "Worship Playlists",
        description: "Curated playlists from our worship team",
        icon: "music.note"
    ),
    CommunityResource(
        title: "Small Group Materials",
        description: "Discussion guides and study materials for small groups",
        icon: "person.3.fill"
    )
]

// MARK: - Community Detail View
struct CommunityDetailView: View {
    @Environment(\.dismiss) var dismiss
    let community: PrivateCommunity
    let isJoined: Bool
    
    @State private var selectedTab: DetailTab = .chat
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = sampleMessages
    @Namespace private var detailTabAnimation
    
    enum DetailTab: String, CaseIterable {
        case chat = "Chat"
        case events = "Events"
        case prayer = "Prayer"
        case resources = "Resources"
        
        var icon: String {
            switch self {
            case .chat: return "message.fill"
            case .events: return "calendar"
            case .prayer: return "hands.sparkles"
            case .resources: return "book.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Tab Selector
                tabSelector
                
                // Content
                TabView(selection: $selectedTab) {
                    chatView
                        .tag(DetailTab.chat)
                    
                    eventsView
                        .tag(DetailTab.events)
                    
                    prayerView
                        .tag(DetailTab.prayer)
                    
                    resourcesView
                        .tag(DetailTab.resources)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(community.name)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        
                        Text("\(community.memberCount) members")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Menu {
                    Button {
                        // Community info
                    } label: {
                        Label("Community Info", systemImage: "info.circle")
                    }
                    
                    Button {
                        // Notifications
                    } label: {
                        Label("Notifications", systemImage: "bell")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        // Leave community
                    } label: {
                        Label("Leave Community", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            // Community banner (optional)
            LinearGradient(
                colors: community.gradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 4)
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(tab.rawValue)
                                .font(.custom("OpenSans-Bold", size: 14))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(community.type.color)
                                        .matchedGeometryEffect(id: "selectedDetailTab", in: detailTabAnimation)
                                }
                            }
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(Color(.systemGray6).opacity(0.3))
    }
    
    // MARK: - Chat View
    private var chatView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        ChatMessageRow(message: message)
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 20)
            }
            
            // Message input
            HStack(spacing: 12) {
                TextField("Type a message...", text: $messageText)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemGray6))
                    )
                
                Button {
                    sendMessage()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: community.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(messageText.isEmpty)
                .opacity(messageText.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
    
    // MARK: - Events View
    private var eventsView: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Community Events")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .padding(.top, 20)
                    
                    ForEach(sampleEvents.prefix(3)) { event in
                        EventCard(event: event)
                    }
                }
                .padding(.bottom, 20)
            }
            .blur(radius: 8)
            
            // Coming Soon Overlay
            ComingSoonOverlay(
                icon: "calendar",
                iconColor: .blue,
                title: "Events Coming Soon",
                message: "Schedule and manage community events"
            )
        }
    }
    
    // MARK: - Prayer View
    private var prayerView: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Prayer Requests")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .padding(.top, 20)
                    
                    ForEach(samplePrayerRequests) { prayer in
                        CommunityPrayerRequestCard(prayer: prayer, communityColor: community.type.color)
                    }
                }
                .padding(.bottom, 20)
            }
            .blur(radius: 8)
            
            // Coming Soon Overlay
            ComingSoonOverlay(
                icon: "hands.sparkles",
                iconColor: .purple,
                title: "Prayer Wall Coming Soon",
                message: "Share and support each other in prayer"
            )
        }
    }
    
    // MARK: - Resources View
    private var resourcesView: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Community Resources")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .padding(.top, 20)
                    
                    ForEach(sampleResources) { resource in
                        CommunityResourceCard(resource: resource, communityColor: community.type.color)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
            .blur(radius: 8)
            
            // Coming Soon Overlay
            ComingSoonOverlay(
                icon: "book.fill",
                iconColor: .green,
                title: "Resources Coming Soon",
                message: "Access shared study materials and guides"
            )
        }
    }
    
    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        let newMessage = ChatMessage(
            id: UUID(),
            sender: "You",
            text: messageText,
            timestamp: Date(),
            isCurrentUser: true
        )
        
        messages.append(newMessage)
        messageText = ""
        
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
    }
}

// MARK: - Chat Message Row
struct ChatMessageRow: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !message.isCurrentUser {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(message.sender.prefix(1)))
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                    )
            } else {
                Spacer()
            }
            
            VStack(alignment: message.isCurrentUser ? .trailing : .leading, spacing: 4) {
                if !message.isCurrentUser {
                    Text(message.sender)
                        .font(.custom("OpenSans-Bold", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Text(message.text)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(message.isCurrentUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                message.isCurrentUser ?
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: [Color(.systemGray6), Color(.systemGray6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                
                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 250, alignment: message.isCurrentUser ? .trailing : .leading)
            
            if message.isCurrentUser {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(message.sender.prefix(1)))
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                    )
            } else {
                Spacer()
            }
        }
    }
}

// MARK: - Prayer Request Card  
struct CommunityPrayerRequestCard: View {
    let prayer: CommunityPrayerRequest
    let communityColor: Color
    @State private var hasPrayed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [communityColor, communityColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(prayer.author.prefix(1)))
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundStyle(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(prayer.author)
                        .font(.custom("OpenSans-Bold", size: 15))
                    
                    Text(prayer.timestamp.formatted(.relative(presentation: .named)))
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Text(prayer.text)
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        hasPrayed.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                            .font(.system(size: 14))
                        Text(hasPrayed ? "Prayed" : "Pray")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                    }
                    .foregroundStyle(hasPrayed ? communityColor : .secondary)
                }
                
                Text("•")
                    .foregroundStyle(.secondary)
                
                Text("\(prayer.prayerCount) prayers")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Community Resource Card
struct CommunityResourceCard: View {
    let resource: CommunityResource
    let communityColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(communityColor.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: resource.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(communityColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.title)
                    .font(.custom("OpenSans-Bold", size: 16))
                
                Text(resource.description)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }
}

// MARK: - Coming Soon Overlay (for tabs)

struct ComingSoonOverlay: View {
    let icon: String
    let iconColor: Color
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.pulse, options: .repeating)
            }
            
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                    Text("COMING SOON")
                        .font(.custom("OpenSans-Bold", size: 12))
                        .tracking(1.5)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.15))
                )
                
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 22))
                    .foregroundStyle(.primary)
                
                Text(message)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Coming Soon Placeholder

struct ComingSoonPlaceholder: View {
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
                                FeatureHighlightRow(
                                    icon: "checkmark.circle.fill",
                                    text: "Full functionality coming soon",
                                    color: iconColor
                                )
                                FeatureHighlightRow(
                                    icon: "bell.fill",
                                    text: "You'll be notified when it's ready",
                                    color: iconColor
                                )
                                FeatureHighlightRow(
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
                                Text("Back to Communities")
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

// MARK: - Feature Highlight Row

struct FeatureHighlightRow: View {
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
    NavigationStack {
        PrivateCommunitiesView()
    }
}
