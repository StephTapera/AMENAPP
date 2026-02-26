//
//  PeopleDiscoveryView.swift
//  AMENAPP
//
//  Created by Steph on 1/28/26.
//
//  Production-ready people discovery with clean black & white design
//  Focused on finding and connecting with people
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - People Discovery View (Liquid Glass Design)

struct PeopleDiscoveryViewNew: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PeopleDiscoveryViewModelNew()
    @State private var searchText = ""
    @State private var selectedFilter: DiscoveryFilter = .suggested
    @State private var showProfileSheet: UserModel?
    @State private var scrollOffset: CGFloat = 0
    @State private var searchDebounceTimer: Timer?
    @State private var isLoadingTriggered = false
    
    // Tab bar auto-hide on scroll
    @State private var lastDragValue: CGFloat = 0
    @State private var isTabBarHidden = false
    
    enum DiscoveryFilter: String, CaseIterable {
        case suggested = "Suggested"
        case recent = "Recent"
        
        var icon: String {
            switch self {
            case .suggested: return "sparkles"
            case .recent: return "clock.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Clean white gradient background
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(red: 0.97, green: 0.97, blue: 0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // UNIFIED SCROLL: Everything inside ScrollView
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        // Header with back button (collapses on scroll)
                        headerSection
                            .background(
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("scroll")).minY
                                    )
                                }
                            )
                        
                        // Search bar (shrinks on scroll)
                        liquidGlassSearchSection
                        
                        // Filter tabs (fade out on scroll)
                        liquidGlassFilterSection
                        
                        // People Discovery content
                        LazyVStack(spacing: 12) {
                            if viewModel.isLoading && viewModel.users.isEmpty {
                                loadingView
                            } else if let error = viewModel.networkError {
                                errorStateView(message: error)
                            } else if viewModel.users.isEmpty {
                                emptyStateView
                            } else {
                                ForEach(Array(viewModel.users.filter { $0.id != nil }.enumerated()), id: \.element.id) { index, user in
                                    PeopleDiscoveryPersonCard(
                                        user: user,
                                        onTap: {
                                            showProfileSheet = user
                                        },
                                        cardIndex: index,
                                        viewModel: viewModel
                                    )
                                    .onAppear {
                                        // ✨ Smart Prefetch Trigger: At 80% of list
                                        let totalUsers = viewModel.users.count
                                        let prefetchThreshold = Int(Double(totalUsers) * 0.8)
                                        
                                        if index >= prefetchThreshold && viewModel.hasMore {
                                            viewModel.triggerPrefetch()
                                        }
                                    }
                                }
                                
                                // Load more trigger (with double-trigger guard)
                                if viewModel.hasMore && !viewModel.isLoadingMore {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black.opacity(0.5)))
                                        .frame(height: 50)
                                        .onAppear {
                                            guard !isLoadingTriggered else { return }
                                            isLoadingTriggered = true
                                            Task {
                                                await viewModel.loadMore()
                                                isLoadingTriggered = false
                                            }
                                        }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
                .refreshable {
                    await viewModel.refresh()
                }
                .onChange(of: scrollOffset) { oldValue, newValue in
                    // Scroll tracking for tab bar auto-hide
                }
            }
            .navigationBarHidden(true)
            .toolbar(isTabBarHidden ? .hidden : .visible, for: .tabBar)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = value.translation.height - lastDragValue
                        
                        if delta < -10 && !isTabBarHidden {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isTabBarHidden = true
                            }
                        } else if delta > 10 && isTabBarHidden {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isTabBarHidden = false
                            }
                        }
                        
                        lastDragValue = value.translation.height
                    }
                    .onEnded { _ in
                        lastDragValue = 0
                    }
            )
            .overlay(
                VStack {
                    Spacer()
                    
                    if viewModel.showPrefetchBadge {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Found \(viewModel.prefetchCount) more believers")
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.9))
                                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.showPrefetchBadge)
                    }
                }
                .padding(.bottom, 80)
            )
            .sheet(item: $showProfileSheet) { user in
                if let userId = user.id, !userId.isEmpty {
                    NavigationView {
                        SafeUserProfileWrapper(userId: userId)
                    }
                } else {
                    Text("Unable to load profile")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .task {
                await viewModel.loadUsers(filter: selectedFilter)
            }
        }
    }
    
    // MARK: - Header with Back Button (Scroll-Driven Collapse)
    
    private var headerSection: some View {
        let collapsedHeight: CGFloat = 50
        let expandedHeight: CGFloat = 80
        let collapsedFontSize: CGFloat = 20
        let expandedFontSize: CGFloat = 28
        let scrollThreshold: CGFloat = 100
        
        // Calculate progress (0 = expanded, 1 = collapsed)
        let progress = max(0, min(1, -scrollOffset / scrollThreshold))
        let currentHeight = expandedHeight - (expandedHeight - collapsedHeight) * progress
        let currentFontSize = expandedFontSize - (expandedFontSize - collapsedFontSize) * progress
        let currentPadding = 20 - (8 * progress)
        
        // Smart blur/fade effect: more translucent when scrolling
        let headerOpacity = 1.0 - (progress * 0.15)
        let blurRadius = progress * 2
        
        return HStack(spacing: 16) {
            Spacer()
            
            Text("Discover People")
                .font(.custom("OpenSans-Bold", size: currentFontSize))
                .foregroundColor(.black)
                .opacity(headerOpacity)
            
            Spacer()
        }
        .padding(.horizontal, currentPadding)
        .padding(.top, 16)
        .padding(.bottom, currentPadding)
        .frame(height: currentHeight)
        .background(
            Color.white
                .opacity(1.0 - (progress * 0.1))
                .blur(radius: blurRadius)
        )
        .animation(.easeOut(duration: 0.2), value: scrollOffset)
    }
    
    // MARK: - Smart Search (Scroll-Driven Shrink + View-Level Debouncing)
    
    private var liquidGlassSearchSection: some View {
        let scrollThreshold: CGFloat = 100
        let progress = max(0, min(1, -scrollOffset / scrollThreshold))
        
        // Height shrink: 56pt → 44pt
        let expandedHeight: CGFloat = 56
        let collapsedHeight: CGFloat = 44
        let currentHeight = expandedHeight - (expandedHeight - collapsedHeight) * progress
        
        // Padding shrink
        let expandedPadding: CGFloat = 16
        let collapsedPadding: CGFloat = 10
        let currentPadding = expandedPadding - (expandedPadding - collapsedPadding) * progress
        
        // Smart appearance changes on scroll
        let cornerRadius = 14 - (progress * 2) // 14 → 12
        let searchOpacity = 1.0 - (progress * 0.2) // Subtle fade
        let glassOpacity = 0.1 + (progress * 0.15) // More glass effect when compact
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Animated search icon
                Image(systemName: searchText.isEmpty ? "magnifyingglass" : "magnifyingglass.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(searchText.isEmpty ? .black.opacity(0.6) : .black)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: searchText.isEmpty)
                
                TextField("", text: $searchText, prompt: Text("Search by name or @username").foregroundColor(.black.opacity(0.4)))
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundColor(.black)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: searchText) { _, newValue in
                        // View-level debouncing (300ms)
                        searchDebounceTimer?.invalidate()
                        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            Task {
                                await viewModel.searchUsers(query: newValue)
                            }
                        }
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchDebounceTimer?.invalidate()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            searchText = ""
                            Task {
                                await viewModel.loadUsers(filter: selectedFilter)
                            }
                        }
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, currentPadding)
            .padding(.vertical, currentPadding)
            .frame(height: currentHeight)
            .opacity(searchOpacity)
            .background(
                ZStack {
                    // Dynamic glass effect - more translucent when compact
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(glassOpacity))
                    
                    // Blur effect increases when scrolling
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(searchText.isEmpty ? 0.02 : 0.04))
                        .blur(radius: progress * 1.5)
                    
                    // Border becomes more prominent when compact
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            Color.black.opacity((searchText.isEmpty ? 0.12 : 0.2) + (progress * 0.05)),
                            lineWidth: (searchText.isEmpty ? 0.5 : 1) + (progress * 0.5)
                        )
                }
            )
            .shadow(color: .black.opacity(0.04 + (progress * 0.02)), radius: 4 - (progress * 2), y: 2)
            .animation(.easeOut(duration: 0.2), value: scrollOffset)
            
            // Smart search status
            if !searchText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    
                    if viewModel.isLoading {
                        Text("Searching...")
                            .font(.custom("OpenSans-Medium", size: 12))
                    } else if viewModel.users.isEmpty {
                        Text("No results for \"\(searchText)\"")
                            .font(.custom("OpenSans-Medium", size: 12))
                    } else {
                        Text("\(viewModel.users.count) \(viewModel.users.count == 1 ? "result" : "results")")
                            .font(.custom("OpenSans-Medium", size: 12))
                    }
                }
                .foregroundColor(.black.opacity(0.5))
                .padding(.horizontal, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
    
    // MARK: - Liquid Glass Filters (Scroll-Driven Fade Out)
    
    private var liquidGlassFilterSection: some View {
        let fadeThreshold: CGFloat = 50
        let progress = max(0, min(1, -scrollOffset / fadeThreshold))
        let opacity = 1.0 - progress
        let height: CGFloat? = opacity > 0.1 ? nil : 0
        
        return VStack(spacing: 12) {
            // Filter buttons
            HStack(spacing: 12) {
                ForEach(DiscoveryFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedFilter = filter
                        }
                        
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        
                        Task {
                            await viewModel.loadUsers(filter: filter)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 14, weight: .semibold))
                            
                            Text(filter.rawValue)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                        }
                        .foregroundColor(selectedFilter == filter ? .white : .black.opacity(0.7))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                if selectedFilter == filter {
                                    // Selected: Solid black pill
                                    Capsule()
                                        .fill(Color.black)
                                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                                } else {
                                    // Unselected: Reduced opacity for performance
                                    Capsule()
                                        .fill(.ultraThinMaterial.opacity(0.1))
                                    
                                    Capsule()
                                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                                }
                            }
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Smart discovery tip
            if !viewModel.users.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    
                    Text(selectedFilter == .suggested ? "People you might know" : "Recently joined believers")
                        .font(.custom("OpenSans-Medium", size: 12))
                }
                .foregroundColor(.black.opacity(0.5))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.1))
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .opacity(opacity)
        .frame(height: height.map { CGFloat($0) })
        .animation(.easeOut(duration: 0.2), value: scrollOffset)
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                .scaleEffect(1.2)
            
            Text("Finding people...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundColor(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.black.opacity(0.3))
                .symbolEffect(.bounce, value: viewModel.users.isEmpty)
            
            Text("No people found")
                .font(.custom("OpenSans-SemiBold", size: 18))
                .foregroundColor(.black)
            
            Text("Try a different search or filter")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    // MARK: - Error State (with Retry)
    
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.red.opacity(0.6))
                .symbolEffect(.pulse, value: message)
            
            Text("Connection Error")
                .font(.custom("OpenSans-SemiBold", size: 18))
                .foregroundColor(.black)
            
            Text(message)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundColor(.black.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()
                
                Task {
                    await viewModel.loadUsers(filter: selectedFilter)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Retry")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Liquid Glass Filter Chip

struct LiquidGlassFilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 15))
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    if isSelected {
                        // Selected: White liquid glass
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .white.opacity(0.3), radius: 12, y: 6)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Unselected: Transparent liquid glass
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.2))
                        
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.75, blendDuration: 0), value: isSelected)
            )
            .contentShape(Rectangle()) // Better tap target
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(true)
    }
}

// ScaleButtonStyle is defined in SharedUIComponents.swift

// MARK: - Smart Follow Button

struct SmartFollowButton: View {
    let isFollowing: Bool
    @Binding var isHovering: Bool
    let onToggle: () -> Void
    
    @State private var isPressed = false
    @State private var showCheckmark = false
    
    var body: some View {
        Button(action: {
            let haptic = UIImpactFeedbackGenerator(style: .medium)
            haptic.impactOccurred()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                showCheckmark = true
            }
            
            onToggle()
            
            // Hide checkmark after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.2)) {
                    showCheckmark = false
                }
            }
        }) {
            ZStack {
                // Following state - "Following" text
                if isFollowing && !showCheckmark {
                    Text("Following")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundColor(.black.opacity(0.6))
                        .transition(.scale.combined(with: .opacity))
                }
                // Not following state - "Follow" text
                else if !isFollowing && !showCheckmark {
                    Text("Follow")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
                // Checkmark animation
                else if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: isFollowing ? 85 : 70, height: 32)
            .background(
                ZStack {
                    if isFollowing {
                        // Following state - subtle glass
                        Capsule()
                            .fill(.ultraThinMaterial.opacity(0.3))
                        
                        Capsule()
                            .stroke(Color.black.opacity(0.15), lineWidth: 1)
                    } else {
                        // Follow state - solid black
                        Capsule()
                            .fill(Color.black)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    }
                }
            )
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFollowing)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showCheckmark)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                    isHovering = true
                }
                .onEnded { _ in
                    isPressed = false
                    isHovering = false
                }
        )
    }
}

// MARK: - People Discovery Person Card

struct PeopleDiscoveryPersonCard: View {
    let user: UserModel
    let onTap: () -> Void
    let cardIndex: Int
    @State private var isFollowing = false
    @State private var isPressed = false
    @State private var isHovering = false
    @StateObject private var followService = FollowService.shared
    @ObservedObject var viewModel: PeopleDiscoveryViewModelNew
    @State private var hasAppeared = false // Track appearance for staggered animation
    @State private var photoInsights: PhotoInsight? // AI photo insights
    @State private var smartSuggestion: SmartSuggestion? // AI connection reason
    
    var body: some View {
        HStack(spacing: 12) {
            // Smaller Avatar - tappable
            Button(action: onTap) {
                ZStack {
                    // Avatar circle
                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.black.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                    
                    if let profileImageURL = user.profileImageURL, !profileImageURL.isEmpty {
                        CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(user.initials)
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundColor(.black.opacity(0.7))
                        }
                    } else {
                        Text(user.initials)
                            .font(.custom("OpenSans-Bold", size: 16))
                            .foregroundColor(.black.opacity(0.7))
                    }
                }
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Info - tappable
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(user.displayName)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundColor(.black)
                            .lineLimit(1)
                        
                        // Mutual following badge
                        if isFollowing && viewModel.followingUserIds.contains(user.id ?? "") {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.black.opacity(0.4))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.06))
                                )
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Text("@\(user.username)")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundColor(.black.opacity(0.5))
                        
                        if user.followersCount > 0 {
                            Text("•")
                                .foregroundColor(.black.opacity(0.3))
                            
                            HStack(spacing: 3) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 9))
                                Text("\(user.followersCount)")
                                    .font(.custom("OpenSans-Medium", size: 13))
                            }
                            .foregroundColor(.black.opacity(0.5))
                        }
                    }
                    .lineLimit(1)
                    
                    // 🤖 AI Smart Suggestion (show every 3rd card)
                    if let suggestion = smartSuggestion, cardIndex % 3 == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.black)
                            
                            Text(suggestion.reason)
                                .font(.custom("OpenSans-Medium", size: 11))
                                .foregroundColor(.black)
                                .lineLimit(1)
                        }
                        .padding(.top, 2)
                    }
                    
                    // 📸 Photo Insights Badges
                    if let insights = photoInsights, !insights.badges.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(insights.badges.prefix(2), id: \.self) { badge in
                                Text(badge)
                                    .font(.custom("OpenSans-Medium", size: 10))
                                    .foregroundColor(.black.opacity(0.6))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.06))
                                    )
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Smart Follow Button
            SmartFollowButton(
                isFollowing: isFollowing,
                isHovering: $isHovering,
                onToggle: {
                    toggleFollow()
                }
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                // Optimized: Reduced opacity to 0.1 for GPU performance
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.1))
                
                // Static color instead of gradient (GPU-friendly)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(isHovering ? 0.03 : 0.015))
                
                // Subtle border
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.black.opacity(isHovering ? 0.15 : 0.08),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.easeOut(duration: 0.3), value: hasAppeared)
        .onAppear {
            // Staggered fade-in animation
            withAnimation {
                hasAppeared = true
            }
            
            // Use cached follow status from viewModel - only check once
            if let userId = user.id {
                isFollowing = viewModel.followingUserIds.contains(userId)
            }
        }
        .task {
            guard let userId = user.id else { return }
            guard let currentUserId = Auth.auth().currentUser?.uid else { return }
            
            // Load both AI features in parallel
            async let photoTask: PhotoInsight? = {
                guard let imageURL = user.profileImageURL, !imageURL.isEmpty else { return nil }
                do {
                    return try await PhotoInsightsService.shared.analyzeProfilePhoto(
                        imageURL: imageURL,
                        userId: userId,
                        currentUserId: currentUserId
                    )
                } catch {
                    Logger.debug("Photo insights failed: \(error.localizedDescription)")
                    return nil
                }
            }()
            
            async let suggestionTask: SmartSuggestion? = {
                do {
                    return try await SmartSuggestionsService.shared.getSuggestion(
                        for: userId,
                        currentUserId: currentUserId
                    )
                } catch {
                    Logger.debug("Smart suggestion failed: \(error.localizedDescription)")
                    return nil
                }
            }()
            
            // Await both results
            photoInsights = await photoTask
            smartSuggestion = await suggestionTask
        }
        // MEMORY LEAK FIX: Removed onChange listener
        // Follow status updates happen via optimistic UI in toggleFollow()
    }
    
    private func toggleFollow() {
        guard let userId = user.id else { return }
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isFollowing.toggle()
            
            // Update the cache immediately for instant UI feedback
            if isFollowing {
                viewModel.followingUserIds.insert(userId)
            } else {
                viewModel.followingUserIds.remove(userId)
            }
        }
        
        Task {
            do {
                if isFollowing {
                    try await followService.followUser(userId: userId)
                } else {
                    try await followService.unfollowUser(userId: userId)
                }
            } catch {
                Logger.error("Follow action failed", error: error)
                // Revert on error
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isFollowing.toggle()
                        
                        // Revert cache
                        if isFollowing {
                            viewModel.followingUserIds.insert(userId)
                        } else {
                            viewModel.followingUserIds.remove(userId)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Liquid Glass Follow Button

struct LiquidGlassFollowButton: View {
    let isFollowing: Bool
    let userId: String
    let onTap: () -> Void
    @State private var showCheckmark = false
    
    var body: some View {
        Button(action: {
            onTap()
            // Show brief checkmark animation when following
            if !isFollowing {
                showCheckmark = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showCheckmark = false
                }
            }
        }) {
            HStack(spacing: 6) {
                if !isFollowing && !showCheckmark {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                } else if showCheckmark {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
                
                Text(isFollowing ? "Following" : "Follow")
                    .font(.custom("OpenSans-Bold", size: 14))
            }
            .foregroundColor(isFollowing ? .white.opacity(0.7) : .black)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isFollowing {
                        // Following state: Liquid glass
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.3))
                        
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    } else {
                        // Follow state: White solid
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .white.opacity(0.4), radius: 8, y: 4)
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isFollowing)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - View Model (Production-Ready with Smart Algorithm)

@MainActor
class PeopleDiscoveryViewModelNew: ObservableObject {
    @Published var users: [UserModel] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var error: String?
    @Published var networkError: String? // For error recovery UI
    @Published var followingUserIds: Set<String> = [] // Cache follow status
    
    // Smart Prefetch
    @Published var prefetchedUsers: [UserModel] = [] // Hidden cache for instant display
    @Published var showPrefetchBadge = false
    @Published var prefetchCount = 0
    
    private let db = Firestore.firestore()
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 50 // Increased to show more users for discovery
    private var searchTask: Task<Void, Never>?
    private var currentFilter: PeopleDiscoveryViewNew.DiscoveryFilter = .suggested
    private var prefetchTask: Task<Void, Never>?
    private var isPrefetching = false
    
    // Cache for user connections to improve performance
    private var connectionsCache: [String: (following: Set<String>, followers: Set<String>)] = [:]
    private var currentUserConnections: (following: Set<String>, followers: Set<String>)?
    
    func loadUsers(filter: PeopleDiscoveryViewNew.DiscoveryFilter) async {
        isLoading = true
        lastDocument = nil
        currentFilter = filter // Track current filter
        networkError = nil
        
        do {
            users = try await fetchUsers(filter: filter, limit: pageSize)
            hasMore = users.count >= pageSize
            
            // PERFORMANCE FIX: Only load following status once on initial load
            if followingUserIds.isEmpty {
                await loadFollowingStatus()
            }
        } catch {
            networkError = "Unable to load users. Please check your connection."
            Logger.error("Failed to load users", error: error)
        }
        
        isLoading = false
    }
    
    // Batch load following status - ONE query instead of N queries
    private func loadFollowingStatus() async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { 
            return 
        }
        
        do {
            let snapshot = try await db
                .collection("users")
                .document(currentUserId)
                .collection("following")
                .getDocuments()
            
            followingUserIds = Set(snapshot.documents.map { $0.documentID })
        } catch let error as NSError {
            // Handle permission errors gracefully
            if error.domain == "FIRFirestoreErrorDomain" && error.code == 7 {
                Logger.warning("Permission denied for following status. Check Firestore rules for /users/{userId}/following")
                followingUserIds = [] // Start with empty set
            } else {
                Logger.error("Failed to load following status", error: error)
            }
        }
    }
    
    func loadMore() async {
        guard !isLoadingMore && hasMore else { return }
        
        // ✨ SMART PREFETCH: Check if we have cached users ready
        if !prefetchedUsers.isEmpty {
            // Instantly append prefetched users
            users.append(contentsOf: prefetchedUsers)
            
            // Show elegant badge
            prefetchCount = prefetchedUsers.count
            showPrefetchBadge = true
            
            // Hide badge after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showPrefetchBadge = false
            }
            
            // Clear prefetch cache
            prefetchedUsers = []
            
            // Immediately start prefetching next batch
            Task {
                await smartPrefetch()
            }
            
            return
        }
        
        // Fallback: Traditional loading with spinner
        isLoadingMore = true
        
        do {
            let newUsers = try await fetchUsers(
                filter: currentFilter,
                limit: pageSize,
                afterDocument: lastDocument
            )
            users.append(contentsOf: newUsers)
            hasMore = newUsers.count >= pageSize
            
            // Start prefetching next batch
            Task {
                await smartPrefetch()
            }
        } catch {
            Logger.error("Failed to load more users", error: error)
        }
        
        isLoadingMore = false
    }
    
    // ✨ SMART PREFETCH: Predictive loading for instant UX
    func smartPrefetch() async {
        guard !isPrefetching && hasMore && prefetchedUsers.isEmpty else { 
            return 
        }
        
        isPrefetching = true
        
        do {
            let nextBatch = try await fetchUsers(
                filter: currentFilter,
                limit: 10, // Smaller prefetch batch
                afterDocument: lastDocument
            )
            
            prefetchedUsers = nextBatch
        } catch {
            Logger.debug("Prefetch failed (non-critical): \(error.localizedDescription)")
        }
        
        isPrefetching = false
    }
    
    // Call this when user reaches 80% scroll
    func triggerPrefetch() {
        guard !isPrefetching && hasMore && prefetchedUsers.isEmpty else { return }
        
        Task {
            await smartPrefetch()
        }
    }
    
    func refresh() async {
        // Clear cache on refresh to get fresh data
        connectionsCache.removeAll()
        currentUserConnections = nil
        await loadUsers(filter: .suggested)
    }
    
    func clearCache() {
        connectionsCache.removeAll()
        currentUserConnections = nil
    }
    
    func searchUsers(query: String) async {
        // Cancel previous search task
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            await loadUsers(filter: .suggested)
            return
        }
        
        // Debounce search with Task
        searchTask = Task {
            // Wait 300ms for debouncing
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            await performSearch(query: query)
        }
    }
    
    private func performSearch(query: String) async {
        isLoading = true
        networkError = nil
        
        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Use Algolia for fast, typo-tolerant search
            let algoliaUsers = try await AlgoliaSearchService.shared.searchUsers(query: trimmedQuery)
            
            // Convert Algolia users to UserModel (now parallel!)
            let results = try await convertAlgoliaUsersToUserModels(algoliaUsers)
            
            // Update users on main thread
            users = results
            
            // Only load following status if not already cached
            if followingUserIds.isEmpty {
                await loadFollowingStatus()
            }
            
        } catch {
            Logger.error("Algolia search failed, falling back to Firestore", error: error)
            // Fallback to Firestore search if Algolia fails
            await performFirestoreSearch(query: query)
        }
        
        isLoading = false
    }
    
    // MARK: - Algolia to UserModel Conversion (Parallel Batch Fetching)
    
    private func convertAlgoliaUsersToUserModels(_ algoliaUsers: [AlgoliaUser]) async throws -> [UserModel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            return []
        }
        
        // Filter out current user first
        let userIdsToFetch = algoliaUsers
            .map { $0.objectID }
            .filter { $0 != currentUserId }
        
        // PERFORMANCE FIX: Batch fetch all users in parallel with TaskGroup
        return await withTaskGroup(of: UserModel?.self, returning: [UserModel].self) { group in
            // Add all fetch tasks to group
            for userId in userIdsToFetch {
                group.addTask {
                    do {
                        let doc = try await self.db.collection("users").document(userId).getDocument()
                        if let user = try? doc.data(as: UserModel.self), user.id != nil {
                            return user
                        }
                    } catch {
                        print("⚠️ Failed to fetch user \(userId): \(error)")
                    }
                    return nil
                }
            }
            
            // Collect all results
            var userModels: [UserModel] = []
            for await user in group {
                if let user = user {
                    userModels.append(user)
                }
            }
            
            return userModels
        }
    }
    
    // MARK: - Firestore Fallback Search
    
    private func performFirestoreSearch(query: String) async {
        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercaseQuery = trimmedQuery.lowercased()
            
            // Strategy 1: Search by username (most common)
            var results = try await searchByUsername(lowercaseQuery)
            
            // Strategy 2: If few results, also search by display name
            if results.count < 5 {
                let nameResults = try await searchByDisplayName(trimmedQuery)
                
                // Merge results, avoiding duplicates
                for user in nameResults {
                    if !results.contains(where: { $0.id == user.id }) {
                        results.append(user)
                    }
                }
            }
            
            // Strategy 3: If still few results, try searchable fields
            if results.count < 3 {
                let searchableResults = try await searchBySearchableFields(lowercaseQuery)
                
                for user in searchableResults {
                    if !results.contains(where: { $0.id == user.id }) {
                        results.append(user)
                    }
                }
            }
            
            users = results
            
        } catch {
            Logger.error("Firestore search failed", error: error)
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Search Strategies
    
    private func searchByUsername(_ query: String) async throws -> [UserModel] {
        let snapshot = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: query)
            .whereField("username", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: pageSize)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> UserModel? in
            guard let user = try? doc.data(as: UserModel.self),
                  user.id != nil else {
                return nil
            }
            return user
        }
    }
    
    private func searchByDisplayName(_ query: String) async throws -> [UserModel] {
        let snapshot = try await db.collection("users")
            .whereField("displayName", isGreaterThanOrEqualTo: query)
            .whereField("displayName", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: pageSize)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> UserModel? in
            guard let user = try? doc.data(as: UserModel.self),
                  user.id != nil else {
                return nil
            }
            return user
        }
    }
    
    private func searchBySearchableFields(_ query: String) async throws -> [UserModel] {
        // Try searching with searchable username/display name fields
        let snapshot = try await db.collection("users")
            .whereField("searchableUsername", isGreaterThanOrEqualTo: query)
            .whereField("searchableUsername", isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: pageSize)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> UserModel? in
            guard let user = try? doc.data(as: UserModel.self),
                  user.id != nil else {
                return nil
            }
            return user
        }
    }
    
    // MARK: - Fetch Users by Filter
    
    private func fetchUsers(
        filter: PeopleDiscoveryViewNew.DiscoveryFilter,
        limit: Int,
        afterDocument: DocumentSnapshot? = nil
    ) async throws -> [UserModel] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "PeopleDiscovery",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        // Fetch ALL users from the app for discovery
        var query: Query = db.collection("users")
        
        // Pagination
        if let afterDocument = afterDocument {
            query = query.start(afterDocument: afterDocument).limit(to: limit)
        } else {
            query = query.limit(to: limit)
        }
        
        let snapshot = try await query.getDocuments()
        lastDocument = snapshot.documents.last
        
        // Filter out current user and map to UserModel
        var allUsers: [UserModel] = []
        var decodingErrors = 0
        var currentUserFiltered = 0
        var idFixedCount = 0
        
        for doc in snapshot.documents {
            do {
                var user = try doc.data(as: UserModel.self)
                
                // Fix @DocumentID issue - manually set ID if nil
                if user.id == nil {
                    user.id = doc.documentID
                    idFixedCount += 1
                }
                
                // Check if it's the current user
                if user.id == currentUserId {
                    currentUserFiltered += 1
                    continue
                }
                
                allUsers.append(user)
            } catch {
                Logger.debug("Decoding error for user \(doc.documentID): \(error.localizedDescription)")
                decodingErrors += 1
            }
        }
        
        #if DEBUG
        if decodingErrors > 0 || idFixedCount > 0 {
            Logger.debug("Fetch stats - Decoding errors: \(decodingErrors), IDs fixed: \(idFixedCount)")
        }
        #endif
        
        // Apply smart algorithm based on filter
        allUsers = await applySmartAlgorithm(to: allUsers, filter: filter, currentUserId: currentUserId)
        
        return allUsers
    }
    
    // MARK: - Smart Discovery Algorithm
    
    private func applySmartAlgorithm(
        to users: [UserModel],
        filter: PeopleDiscoveryViewNew.DiscoveryFilter,
        currentUserId: String
    ) async -> [UserModel] {
        // Return users immediately if empty
        guard !users.isEmpty else {
            return users
        }
        
        // Load current user's following and followers for mutual connection scoring (with cache)
        let (currentUserFollowing, currentUserFollowers): (Set<String>, Set<String>)
        if let cached = currentUserConnections {
            (currentUserFollowing, currentUserFollowers) = cached
        } else {
            let connections = await loadUserConnections(userId: currentUserId)
            currentUserConnections = connections
            (currentUserFollowing, currentUserFollowers) = connections
        }
        
        // Score each user based on multiple factors
        let scoredUsers = users.map { user -> (user: UserModel, score: Double) in
            var score: Double = 10.0 // Base score to ensure everyone has some score
            
            guard let userId = user.id else {
                return (user, 0.0)
            }
            
            // Factor 1: User engagement/activity (always calculated)
            let followerCount = user.followersCount
            let followingCount = user.followingCount
            score += Double(followerCount) * 0.5 // Popular users
            score += Double(followingCount) * 0.3 // Active users
            
            // Factor 2: Profile completeness (quality signal)
            var completeness = 0
            if !(user.bio?.isEmpty ?? true) { completeness += 1 }
            if !(user.profileImageURL?.isEmpty ?? true) { completeness += 1 }
            if !user.displayName.isEmpty { completeness += 1 }
            score += Double(completeness) * 2.0
            
            // Factor 3: Recency (for Recent filter)
            if filter == .recent {
                let daysSinceCreation = Date().timeIntervalSince(user.createdAt) / 86400
                // Boost score for recently joined users (decay over time)
                score += max(0, 50.0 - daysSinceCreation)
            }
            
            // Factor 4: Already following penalty (for Suggested filter only)
            // Don't completely hide users you follow, just deprioritize them
            if filter == .suggested && followingUserIds.contains(userId) {
                score *= 0.2 // Reduce score but don't eliminate
            }
            
            return (user, score)
        }
        
        // Sort by score (highest first)
        let sortedUsers = scoredUsers
            .sorted { $0.score > $1.score }
            .map { $0.user }
        
        return sortedUsers
    }
    
    // MARK: - Load User Connections
    
    private func loadUserConnections(userId: String) async -> (following: Set<String>, followers: Set<String>) {
        var following: Set<String> = []
        var followers: Set<String> = []
        
        do {
            // Load following
            let followingSnapshot = try await db
                .collection("users")
                .document(userId)
                .collection("following")
                .getDocuments()
            following = Set(followingSnapshot.documents.map { $0.documentID })
            
            // Load followers
            let followersSnapshot = try await db
                .collection("users")
                .document(userId)
                .collection("followers")
                .getDocuments()
            followers = Set(followersSnapshot.documents.map { $0.documentID })
        } catch {
            Logger.debug("Failed to load user connections: \(error.localizedDescription)")
        }
        
        return (following, followers)
    }
}

// MARK: - Safe Profile Wrapper

struct SafeUserProfileWrapper: View {
    let userId: String
    @State private var loadFailed = false
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Group {
            if loadFailed {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    
                    Text("Unable to Load Profile")
                        .font(.custom("OpenSans-Bold", size: 20))
                    
                    Text("This profile could not be loaded. Please try again later.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.black)
                            )
                    }
                }
                .padding()
            } else {
                UserProfileView(userId: userId, showsDismissButton: true)
                    .task {
                        // Add timeout to detect crashes
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                        isLoading = false
                    }
                    .onDisappear {
                        // Clean up if needed
                        isLoading = false
                    }
            }
        }
        .task {
            // Watchdog timer - if view doesn't load in 10 seconds, show error
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if isLoading {
                loadFailed = true
            }
        }
    }
}

// MARK: - Typealias for backward compatibility
typealias PeopleDiscoveryView = PeopleDiscoveryViewNew

