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
    @State private var bibleFact: BibleFact = .sample
    @State private var isRefreshingFact = false
    @FocusState private var isSearchFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollToResults = false
    @State private var aiSearchResults: [AISearchResult] = []
    @State private var isSearchingWithAI = false
    @State private var useAISearch = false
    
    enum ResourceCategory: String, CaseIterable {
        case all = "All"
        case mentalHealth = "Mental Health"
        case crisis = "Crisis"
        case giving = "Giving"
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
        
        // Use AI search results if available
        if useAISearch && !aiSearchResults.isEmpty {
            return aiSearchResults.map { $0.resource }
        }
        
        // Fallback to keyword search
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
                
                ScrollViewReader { proxy in
                    ScrollView {
                        contentView
                            .onChange(of: scrollToResults) { _, shouldScroll in
                                if shouldScroll {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        proxy.scrollTo("searchResults", anchor: .top)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        scrollToResults = false
                                    }
                                }
                            }
                    }
                    .simultaneousGesture(
                        // Tap to dismiss keyboard
                        TapGesture()
                            .onEnded { _ in
                                if isSearchFocused {
                                    isSearchFocused = false
                                }
                            }
                    )
                }
            }
            .navigationBarHidden(true)
            .animation(.easeOut(duration: 0.15), value: searchFilteredResources.count)
            .onAppear {
                setupKeyboardObservers()
            }
            .onDisappear {
                removeKeyboardObservers()
            }
            .padding(.bottom, keyboardHeight)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
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
            // Circular icon button with glass effect
            Button {
                print("🔍 [DEBUG] Search button tapped, searchText: '\(searchText)'")
                if !searchText.isEmpty {
                    print("🔍 [DEBUG] Calling performAISearch()")
                    // Trigger AI search
                    performAISearch()
                    
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                } else {
                    print("🔍 [DEBUG] Search text empty, focusing search field")
                    // Focus search field when empty
                    isSearchFocused = true
                }
            } label: {
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
                    
                    if isSearchingWithAI {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: searchText.isEmpty ? "magnifyingglass" : "sparkles.rectangle.stack.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(searchText.isEmpty ? Color.primary.opacity(0.6) : Color.purple)
                            .symbolEffect(.pulse, options: .repeating, isActive: useAISearch && !searchText.isEmpty)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: searchText.isEmpty)
                .animation(.easeOut(duration: 0.2), value: isSearchingWithAI)
            }
            
            // Text field with custom styling
            TextField("Search resources...", text: $searchText)
                .font(.custom("OpenSans-Regular", size: 17))
                .foregroundStyle(.primary)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    // Dismiss keyboard when user taps search
                    isSearchFocused = false
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                }
            
            // Clear button with glass effect
            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        searchText = ""
                    }
                    isSearchFocused = false
                    
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
                .transition(.scale.combined(with: .opacity).animation(.easeOut(duration: 0.15)))
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
        .overlay(
            // ✨ Subtle shining animation border
            ShiningBorderView(isActive: true)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
        .animation(.easeOut(duration: 0.15), value: searchText.isEmpty)
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
            // AI-Powered Daily Bible Verse Card (with safe loading)
            SafeAIDailyVerseCard()
            
            // Fun Bible Fact Card
            BibleFactCard(fact: bibleFact, isRefreshing: $isRefreshingFact) {
                refreshBibleFact()
            }
            
            // AMEN | Connect Section - Condensed with Color Accents
            if selectedCategory == .all || selectedCategory == .community {
                VStack(alignment: .leading, spacing: 14) {
                    Text("AMEN | Connect")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    
                    // Grid layout for connect cards
                    VStack(spacing: 12) {
                        // Private Communities - Full width, colored
                        NavigationLink(destination: PrivateCommunitiesView()) {
                            MinimalConnectCard(
                                icon: "person.3.fill",
                                title: "Private Communities",
                                subtitle: "Church, university & more",
                                badge: "COMING SOON",
                                accentColor: .blue,
                                isFullWidth: true
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Two-column grid
                        HStack(spacing: 12) {
                            // Find Church
                            NavigationLink(destination: FindChurchView()) {
                                MinimalConnectCard(
                                    icon: "building.2.fill",
                                    title: "Find Church",
                                    subtitle: "Nearby worship",
                                    badge: nil,
                                    accentColor: .purple,
                                    isFullWidth: false
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Church Notes
                            NavigationLink(destination: ChurchNotesView()) {
                                MinimalConnectCard(
                                    icon: "note.text",
                                    title: "Church Notes",
                                    subtitle: "Take & share",
                                    badge: nil,
                                    accentColor: .orange,
                                    isFullWidth: false
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        HStack(spacing: 12) {
                            // Christian Dating - Coming Soon
                            Button {
                                // Show coming soon
                            } label: {
                                MinimalConnectCard(
                                    icon: "heart.text.square.fill",
                                    title: "Dating",
                                    subtitle: "Coming soon",
                                    badge: nil,
                                    accentColor: .pink,
                                    isFullWidth: false
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Find Friends - Coming Soon
                            Button {
                                // Show coming soon
                            } label: {
                                MinimalConnectCard(
                                    icon: "person.2.fill",
                                    title: "Find Friends",
                                    subtitle: "Coming soon",
                                    badge: nil,
                                    accentColor: .cyan,
                                    isFullWidth: false
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
            

            
            // Crisis & Support - Always accessible, subtle
            if selectedCategory == .all || selectedCategory == .crisis || selectedCategory == .mentalHealth {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Support & Wellness")
                        .font(.custom("OpenSans-Bold", size: 22))
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        // Crisis Resources Banner
                        NavigationLink(destination: CrisisResourcesDetailView()) {
                            SimplifiedFeatureBanner(
                                icon: "phone.fill",
                                title: "Crisis Resources",
                                subtitle: "24/7 help & support",
                                accentColor: .red,
                                features: [
                                    "988 Suicide & Crisis Lifeline",
                                    "Crisis Text Line: Text HOME to 741741",
                                    "SAMHSA National Helpline: 1-800-662-4357",
                                    "Immediate professional support"
                                ]
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                        
                        // Mental Health Banner
                        NavigationLink(destination: MentalHealthDetailView()) {
                            SimplifiedFeatureBanner(
                                icon: "heart.text.square.fill",
                                title: "Mental Health & Wellness",
                                subtitle: "Faith-based support",
                                accentColor: .green,
                                features: [
                                    "Christian counseling resources",
                                    "Mental health awareness",
                                    "Prayer and meditation guides",
                                    "Community support groups"
                                ]
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                        
                        // Giving & Nonprofits Banner
                        NavigationLink(destination: GivingNonprofitsDetailView()) {
                            SimplifiedFeatureBanner(
                                icon: "heart.circle.fill",
                                title: "Giving & Nonprofits",
                                subtitle: "Make an impact",
                                accentColor: .blue,
                                features: [
                                    "Vetted Christian nonprofits",
                                    "Mission & humanitarian work",
                                    "Local church support",
                                    "Track your giving journey"
                                ]
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                    }
                }
            }
            
            // Search Results (when searching)
            if !searchText.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: useAISearch ? "sparkles" : "magnifyingglass")
                            .foregroundStyle(useAISearch ? Color.purple : Color.black.opacity(0.6))
                            .font(.system(size: 14))
                        Text(useAISearch ? "AI Search Results" : "Search Results")
                            .font(.custom("OpenSans-Bold", size: 22))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        // Results count badge
                        Text("\(searchFilteredResources.count)")
                            .font(.custom("OpenSans-Bold", size: 14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(searchFilteredResources.isEmpty ? Color.red : (useAISearch ? Color.purple : Color.blue))
                            )
                    }
                    .padding(.horizontal)
                    .id("searchResults") // For scrolling
                    
                    // AI search indicator
                    if useAISearch && !aiSearchResults.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 12))
                            Text("Results ranked by AI relevance")
                                .font(.custom("OpenSans-Regular", size: 13))
                        }
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal)
                    }
                    
                    if searchFilteredResources.isEmpty {
                        emptyStateView
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(Array(searchFilteredResources.enumerated()), id: \.element.id) { index, resource in
                                VStack(spacing: 0) {
                                    MinimalResourceCard(
                                        icon: resource.icon,
                                        title: resource.title,
                                        accentColor: resource.iconColor
                                    )
                                    
                                    // Show AI relevance reason
                                    if useAISearch, index < aiSearchResults.count {
                                        Text(aiSearchResults[index].reason)
                                            .font(.custom("OpenSans-Regular", size: 11))
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 8)
                                            .padding(.top, 6)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.vertical)
    }
    
    private func refreshBibleFact() {
        Task {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isRefreshingFact = true
            }
            
            // Try to get AI-generated fact first
            do {
                let aiFact = try await BereanGenkitService.shared.generateFunBibleFact(category: nil)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        bibleFact = BibleFact(text: aiFact)
                        isRefreshingFact = false
                    }
                }
                
                print("✅ AI-generated Bible fact loaded")
                
            } catch {
                print("⚠️ AI fact generation failed, using fallback: \(error.localizedDescription)")
                
                // Fallback to static random facts if AI fails
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        bibleFact = BibleFact.random()
                        isRefreshingFact = false
                    }
                }
            }
        }
    }
    
    // MARK: - Keyboard Handling
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = keyboardFrame.height
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }
    
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - AI Search
    
    private func performAISearch() {
        print("🔍 [DEBUG] performAISearch() called")
        guard !searchText.isEmpty else {
            print("🔍 [DEBUG] Search text is empty, returning")
            return
        }
        
        print("🔍 [DEBUG] Starting AI search task for query: '\(searchText)'")
        print("🔍 [DEBUG] Total resources available: \(allResources.count)")
        
        Task {
            await MainActor.run {
                isSearchingWithAI = true
                isSearchFocused = false
            }
            print("🔍 [DEBUG] Set isSearchingWithAI = true")
            
            do {
                // Call AI search service
                print("🔍 [DEBUG] Calling AIResourceSearchService.shared.searchWithAI()")
                let results = try await AIResourceSearchService.shared.searchWithAI(
                    query: searchText,
                    allResources: allResources
                )
                
                print("🔍 [DEBUG] AI search returned \(results.count) results")
                
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        aiSearchResults = results
                        useAISearch = true
                        isSearchingWithAI = false
                        scrollToResults = true
                    }
                }
                
                print("✅ AI search complete: \(results.count) results")
                
            } catch {
                print("❌ AI search error: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                
                // Fall back to keyword search
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        useAISearch = false
                        isSearchingWithAI = false
                        scrollToResults = true
                    }
                }
                print("🔍 [DEBUG] Fell back to keyword search")
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
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        searchText = ""
                        selectedCategory = .all
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
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

// MARK: - Bible Fact Card
struct BibleFactCard: View {
    let fact: BibleFact
    @Binding var isRefreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .symbolEffect(.bounce, value: fact.id)
                        .padding(7)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                    
                    Text("Fun Bible Fact")
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(.linear(duration: 1).repeatCount(isRefreshing ? 100 : 0, autoreverses: false), value: isRefreshing)
                }
                .disabled(isRefreshing)
            }
            
            Text(fact.text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(5)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(fact.id)
        }
        .padding(16)
        .background(
            ZStack {
                // Clean glassmorphic background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                // Simple border
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
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
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
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isHovered)
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
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
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
                    ResourceComingSoonPlaceholder(
                        title: "Christian Dating",
                        icon: "heart.text.square.fill",
                        iconColor: .pink,
                        description: "Meet fellow believers looking for meaningful relationships built on shared faith and values. Our Christian dating feature will help you find your match in Christ."
                    )
                } else if title == "Find Friends" {
                    ResourceComingSoonPlaceholder(
                        title: "Find Friends",
                        icon: "person.2.fill",
                        iconColor: .blue,
                        description: "Connect with fellow believers in your area. Build authentic friendships rooted in faith through shared interests, Bible studies, and community activities."
                    )
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

// MARK: - Resource Data (Expanded for Search)
let allResources: [ResourceItem] = [
    // Reading Resources
    ResourceItem(
        icon: "book.fill",
        iconColor: .blue,
        title: "Bible App",
        description: "Read, study, and share scripture with YouVersion",
        category: "Reading"
    ),
    ResourceItem(
        icon: "book.pages.fill",
        iconColor: .green,
        title: "Essential Books",
        description: "Recommended Christian books and literature",
        category: "Reading"
    ),
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
    
    // Listening Resources
    ResourceItem(
        icon: "mic.fill",
        iconColor: .red,
        title: "Sermons",
        description: "Powerful sermons from Christian leaders worldwide",
        category: "Listening"
    ),
    ResourceItem(
        icon: "headphones",
        iconColor: .indigo,
        title: "Podcasts",
        description: "Faith-based podcasts for spiritual growth",
        category: "Listening"
    ),
    ResourceItem(
        icon: "hands.sparkles.fill",
        iconColor: .purple,
        title: "Pray.com",
        description: "Guided prayers, sleep stories, and worship music",
        category: "Listening"
    ),
    
    // Community Resources
    ResourceItem(
        icon: "person.3.fill",
        iconColor: .blue,
        title: "Private Communities",
        description: "Join your church, university, or organization",
        category: "Community"
    ),
    ResourceItem(
        icon: "building.2.fill",
        iconColor: .purple,
        title: "Find Church",
        description: "Discover nearby worship communities",
        category: "Community"
    ),
    ResourceItem(
        icon: "note.text",
        iconColor: .orange,
        title: "Church Notes",
        description: "Take and share sermon notes with your community",
        category: "Community"
    ),
    ResourceItem(
        icon: "person.2.fill",
        iconColor: .green,
        title: "Christian Community",
        description: "Connect with believers in your area",
        category: "Community"
    ),
    ResourceItem(
        icon: "heart.text.square.fill",
        iconColor: .pink,
        title: "Christian Dating",
        description: "Find meaningful relationships rooted in faith",
        category: "Community"
    ),
    ResourceItem(
        icon: "person.2.fill",
        iconColor: .cyan,
        title: "Find Friends",
        description: "Build authentic friendships with fellow believers",
        category: "Community"
    ),
    
    // Tools & Apps
    ResourceItem(
        icon: "sparkles",
        iconColor: .orange,
        title: "Faith & Tech",
        description: "Explore how technology enhances faith journeys",
        category: "Tools"
    ),
    ResourceItem(
        icon: "app.badge.fill",
        iconColor: .purple,
        title: "Recommended Apps",
        description: "Top Christian apps for your spiritual journey",
        category: "Tools"
    ),
    
    // Crisis & Support
    ResourceItem(
        icon: "phone.fill",
        iconColor: .red,
        title: "Crisis Resources",
        description: "24/7 help and support for mental health emergencies",
        category: "Crisis"
    ),
    ResourceItem(
        icon: "heart.text.square.fill",
        iconColor: .green,
        title: "Mental Health & Wellness",
        description: "Faith-based mental health support and resources",
        category: "Mental Health"
    ),
    
    // Giving
    ResourceItem(
        icon: "heart.circle.fill",
        iconColor: .blue,
        title: "Giving & Nonprofits",
        description: "Support vetted Christian ministries and causes",
        category: "Giving"
    ),
    
    // Learning
    ResourceItem(
        icon: "brain.head.profile",
        iconColor: .purple,
        title: "Bible Study Tools",
        description: "Commentaries, concordances, and study aids",
        category: "Learning"
    ),
    ResourceItem(
        icon: "graduationcap.fill",
        iconColor: .blue,
        title: "Theology Courses",
        description: "Learn doctrine and theology from trusted sources",
        category: "Learning"
    ),
    ResourceItem(
        icon: "book.and.wrench.fill",
        iconColor: .orange,
        title: "Discipleship Resources",
        description: "Materials for spiritual growth and maturity",
        category: "Learning"
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
        .buttonStyle(ResourcesSegmentButtonStyle())
    }
    
    private func selectCategory(_ category: ResourcesView.ResourceCategory) {
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        
        // Trigger springy scale animation
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            isAnimating = true
            selection = category
        }
        
        // Reset scale after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                isAnimating = false
            }
        }
    }
}

// MARK: - Segment Button Style (Resources specific to avoid conflicts)

struct ResourcesSegmentButtonStyle: ButtonStyle {
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
    @State private var shimmerPhase: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Hero section with glassmorphic design
            ZStack {
                // Base dark glass
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.4))
                    )
                
                // Subtle animated gradient overlay
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.15),
                        Color.blue.opacity(0.12),
                        Color.cyan.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .hueRotation(.degrees(isAnimating ? 15 : 0))
                .animation(
                    Animation.easeInOut(duration: 3)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                
                // Pattern overlay
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.white.opacity(0.05))
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
                                    .symbolEffect(.pulse, options: .repeating)
                                
                                Text("NEW")
                                    .font(.custom("OpenSans-Bold", size: 12))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                            }
                            
                            Text("Private Communities")
                                .font(.custom("OpenSans-Bold", size: 24))
                                .foregroundStyle(.white)
                            
                            Text("Join your church, university, or organization")
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineSpacing(2)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: isAnimating)
                    }
                    .padding(20)
                }
            }
            .frame(height: 140)
            .overlay(
                // Clean border
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.15),
                        lineWidth: 1
                    )
            )
            
            // Quick stats bar - glassmorphic
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
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.black.opacity(0.3))
                        )
                    
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            Color.white.opacity(0.15),
                            lineWidth: 1
                        )
                }
            )
            .offset(y: -8)
        }
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
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

// MARK: - Minimal Connect Card (Black & White Glassmorphic with Color Accents)

struct MinimalConnectCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let accentColor: Color
    let isFullWidth: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Clean glassmorphic icon - no glow
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: isFullWidth ? 48 : 44, height: isFullWidth ? 48 : 44)
                        .overlay(
                            Circle()
                                .stroke(accentColor.opacity(0.3), lineWidth: 1.5)
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: isFullWidth ? 22 : 20, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.custom("OpenSans-Bold", size: isFullWidth ? 16 : 15))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        if let badge = badge {
                            Text(badge)
                                .font(.custom("OpenSans-Bold", size: 9))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(accentColor.opacity(0.12))
                                        .overlay(
                                            Capsule()
                                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                    }
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: isFullWidth ? 13 : 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                if isFullWidth {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            }
        }
        .padding(isFullWidth ? 18 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                // Clean glassmorphic background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                // Simple border
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
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

// MARK: - Minimal Resource Card (Compact Grid Item)

struct MinimalResourceCard: View {
    let icon: String
    let title: String
    let accentColor: Color
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button {
            action?()
            
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        } label: {
            VStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(accentColor.opacity(0.25), lineWidth: 1.5)
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))
                }
                
                // Title
                Text(title)
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                    
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
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Shining Border Animation Component

struct ShiningBorderView: View {
    let isActive: Bool
    var color: Color = .white
    
    @State private var rotation: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Rotating gradient for shimmer effect
                AngularGradient(
                    colors: [
                        color.opacity(0),
                        color.opacity(0.1),
                        color.opacity(0.3),
                        color.opacity(0.5),
                        color.opacity(0.3),
                        color.opacity(0.1),
                        color.opacity(0)
                    ],
                    center: .center,
                    angle: .degrees(rotation)
                )
                .blur(radius: 8)
                .opacity(isActive ? 0.6 : 0)
                
                // Black/white shimmer overlay
                AngularGradient(
                    colors: [
                        Color.black.opacity(0),
                        Color.white.opacity(0.15),
                        Color.black.opacity(0.1),
                        Color.white.opacity(0.2),
                        Color.black.opacity(0.1),
                        Color.white.opacity(0.15),
                        Color.black.opacity(0)
                    ],
                    center: .center,
                    angle: .degrees(rotation + 45)
                )
                .blur(radius: 6)
                .opacity(isActive ? 0.4 : 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                if isActive {
                    withAnimation(
                        .linear(duration: 4)
                        .repeatForever(autoreverses: false)
                    ) {
                        rotation = 360
                    }
                }
            }
        }
    }
}

// MARK: - Simplified Feature Banner (Compact with Expandable Features)

struct SimplifiedFeatureBanner: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    let features: [String]
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with expand/collapse
            HStack(spacing: 12) {
                // Colored icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Expand/collapse button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .padding(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(14)
            
            // Expandable features list
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .padding(.horizontal, 14)
                    
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(accentColor)
                            
                            Text(feature)
                                .font(.custom("OpenSans-Regular", size: 14))
                                .foregroundStyle(.primary)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, 14)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                .padding(.bottom, 14)
            }
        }
        .background(
            ZStack {
                // Black and white glassmorphic background
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                // Very subtle accent tint (mostly black and white)
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Colored border for accent
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.3),
                                accentColor.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: accentColor.opacity(0.1), radius: 8, y: 2)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
    }
}

// MARK: - Safe AI Daily Verse Card Wrapper

struct SafeAIDailyVerseCard: View {
    @State private var loadFailed = false
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if loadFailed {
                // Fallback card when AI service fails
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(6)
                            .background(Circle().fill(.ultraThinMaterial))
                        
                        Text("Daily Verse")
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    Text("\"For I know the plans I have for you,\" declares the LORD, \"plans to prosper you and not to harm you, plans to give you hope and a future.\"")
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                    
                    Text("Jeremiah 29:11")
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    ZStack {
                        // Clean glassmorphic background
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                        
                        // Simple border
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
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
                .padding(.horizontal)
            } else {
                AIDailyVerseCard()
                    .onAppear {
                        isLoading = false
                    }
            }
        }
        .task {
            // Monitor for crashes with timeout
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if isLoading {
                print("⚠️ AIDailyVerseCard taking too long, using fallback")
                loadFailed = true
            }
        }
    }
}

#Preview {
    ResourcesView()
}
