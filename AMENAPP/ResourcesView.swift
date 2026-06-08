//
//  ResourcesView.swift
//  AMENAPP
//
//  Created by Steph on 1/15/26.
//

import SwiftUI
import FirebaseAuth

struct ResourcesView: View {
    @ObservedObject private var greetingService = GreetingService.shared
    @ObservedObject private var featureFlags = AMENFeatureFlags.shared
    @ObservedObject private var supportCoordinator = SupportIntelligenceCoordinator.shared
    @State private var plannerViewModel = AmenLifePlannerViewModel()
    @State private var selectedChurchId: String? = nil
    @State private var showChurchHub = false
    @State private var searchText = ""
    @State private var selectedCategory: ResourceCategory = .all
    @FocusState private var isSearchFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollToResults = false
    @State private var aiSearchResults: [AISearchResult] = []
    @State private var isSearchingWithAI = false
    @State private var useAISearch = false
    // P0 FIX: Store observer tokens so removeObserver works correctly for
    // closure-based NotificationCenter observers. The old removeObserver(self,…)
    // form is a no-op for these and caused duplicate/leaked observers on each appear.
    @State private var keyboardShowToken: NSObjectProtocol?
    @State private var keyboardHideToken: NSObjectProtocol?
    // P1 FIX: Store AI search task so it can be cancelled on disappear.
    @State private var aiSearchTask: Task<Void, Never>?
    @State private var supportAnalysisTask: Task<Void, Never>?
    // Scroll-collapse — same pattern as MessagesView
    @State private var scrollOffset: CGFloat = 0
    @State private var showHeader: Bool = true
    @Environment(\.tabBarVisible) private var tabBarVisible
    
    /// Drives category pills compression — 0 = fully visible, 1 = fully hidden
    private var pillsCompression: CGFloat {
        min(max((-scrollOffset - 10) / 60, 0), 1.0)
    }
    
    enum ResourceCategory: String, CaseIterable {
        case all = "All"
        case mentalHealth = "Mental Health"
        case crisis = "Crisis"
        case giving = "Giving"
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Zero-height scroll offset reader — must be first child
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("resourcesScroll")).minY
                            )
                        }
                        .frame(height: 0)

                        // Spiritual OS — Life Planner (Agent C, gated by AppStorage flag)
                        AmenLifePlannerSectionView(
                            viewModel: plannerViewModel,
                            userId: Auth.auth().currentUser?.uid ?? ""
                        )

                        // Smart Header Orchestrator (feature-flagged, off by default)
                        SmartHeaderOrchestrator(
                            screenType: .resources,
                            userName: Auth.auth().currentUser?.displayName ?? "",
                            intentMode: nil,
                            scrollOffset: max(0, -scrollOffset),
                            hasVerseReady: DailyVerseGenkitService.shared.todayVerse != nil
                        )

                        // Header scrolls WITH content (like OpenTable / Messages)
                        headerView
                            .opacity(max(0.0, min(1.0, 1.0 + (scrollOffset / 80.0))))
                            .offset(y: min(0, scrollOffset / 4.0))

                        // Main content
                        contentView
                            .onChange(of: scrollToResults) { _, shouldScroll in
                                if shouldScroll {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo("searchResults", anchor: .top)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        scrollToResults = false
                                    }
                                }
                            }
                    }
                }
                .coordinateSpace(name: "resourcesScroll")
                .refreshable {
                    greetingService.refreshGreeting()
                    _ = await DailyVerseGenkitService.shared.generatePersonalizedDailyVerse()
                }
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    handleScrollOffset(value)
                }
                .simultaneousGesture(
                    TapGesture().onEnded { _ in
                        if isSearchFocused { isSearchFocused = false }
                    }
                )
            }
            .scrollEdgeTopBlur(scrollOffset: scrollOffset)
            .navigationBarHidden(true)
            .scrollDismissesKeyboard(.interactively)
            .animation(.easeOut(duration: 0.15), value: searchFilteredResources.count)
            .onAppear {
                setupKeyboardObservers()
                greetingService.refreshGreeting()
            }
            .onDisappear {
                removeKeyboardObservers()
                // P1 FIX: Cancel any in-flight AI search when view disappears.
                aiSearchTask?.cancel()
                aiSearchTask = nil
                supportAnalysisTask?.cancel()
                supportAnalysisTask = nil
            }
            .onChange(of: searchText) { _, query in
                handleSupportSearchChange(query)
            }
        }
    }

    // MARK: - Scroll Handling

    private func handleScrollOffset(_ offset: CGFloat) {
        withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
            scrollOffset = offset
        }
        
        // Hide header when scrolling down, but keep tab bar visible in Resources
        // ResourcesView is a static hub, not an infinite feed, so tab bar stays visible
        if offset < -100 {
            if showHeader {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                    showHeader = false
                }
            }
            // Don't hide tab bar in Resources — users need quick navigation
        } else if offset >= -30 {
            // Show header when near top
            if !showHeader {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                    showHeader = true
                }
            }
            // Tab bar is always visible in Resources
        }
    }
    
    // MARK: - Header View

    private var dayString: String {
        String(format: "%02d", Calendar.current.component(.day, from: Date()))
    }

    /// Returns the first word of the user's display name, falling back to "Friend".
    private var userFirstName: String {
        let full = Auth.auth().currentUser?.displayName ?? ""
        let first = full.components(separatedBy: " ").first ?? ""
        return first.isEmpty ? "Friend" : first
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Hero header row ───────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                // Left: large date number (same reference-image style)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dayString)
                        .font(.systemScaled(52, weight: .black))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                Spacer()

                // Right: personalized greeting + "Resources" heading + red dot
                VStack(alignment: .trailing, spacing: 2) {
                    // Personalized greeting — small, warm
                    Text(greetingService.currentGreeting.text)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)

                    // Main heading with premium red dot accent
                    HStack(alignment: .top, spacing: 0) {
                        Text("Resources")
                            .font(AMENFont.bold(28))
                            .foregroundStyle(.primary)

                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 3, y: 3)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)

            // Subtle divider
            Rectangle()
                .fill(Color(.separator).opacity(0.4))
                .frame(height: 0.5)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            
            searchBarView
            
            // Active filter badge (shown only when filtered)
            if selectedCategory != .all || !searchText.isEmpty {
                activeFiltersBadge
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
            
            categoryPillsView
                .padding(.bottom, 8)
                .opacity(1.0 - pillsCompression)
                .scaleEffect(y: 1.0 - pillsCompression * 0.15, anchor: .top)
                .frame(height: max(0, (1.0 - pillsCompression) * 52), alignment: .top)
                .clipped()
                .animation(Motion.adaptive(.interactiveSpring(response: 0.22, dampingFraction: 0.78)), value: pillsCompression)
        }
        .background(Color(.systemBackground))
    }
    
    private var activeFiltersBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.systemScaled(13))
            Text("\(searchFilteredResources.count) result\(searchFilteredResources.count == 1 ? "" : "s")")
                .font(AMENFont.semiBold(13))
        }
        .foregroundStyle(Color(.label))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    Capsule()
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                )
        )
        .transition(.scale.combined(with: .opacity))
    }
    
    private var searchBarView: some View {
        HStack(spacing: 14) {
            // Circular icon button with glass effect
            Button {
                if !searchText.isEmpty {
                    performAISearch()
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                } else {
                    isSearchFocused = true
                }
            } label: {
                if isSearchingWithAI {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: searchText.isEmpty ? "magnifyingglass" : "sparkles.rectangle.stack.fill")
                        .font(.systemScaled(18, weight: .semibold))
                        .symbolEffect(.pulse, options: .repeating, isActive: useAISearch && !searchText.isEmpty)
                }
            }
            .buttonStyle(.amenGlass(
                role: .utility,
                size: .iconLarge,
                shape: .circle,
                background: .balanced,
                placement: .inline
            ))
            .animation(.easeOut(duration: 0.2), value: searchText.isEmpty)
            .animation(.easeOut(duration: 0.2), value: isSearchingWithAI)
            
            // Text field with custom styling
            TextField("Search resources...", text: $searchText)
                .font(AMENFont.regular(17))
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
                    Image(systemName: "xmark")
                        .font(.systemScaled(11, weight: .bold))
                }
                .buttonStyle(.amenGlass(
                    role: .dismiss,
                    size: .icon,
                    shape: .circle,
                    background: .balanced,
                    placement: .inline
                ))
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
                                AmenTheme.Colors.glassHighlightTop,
                                AmenTheme.Colors.glassHighlightBottom
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
                                AmenTheme.Colors.glassStroke.opacity(searchText.isEmpty ? 0.7 : 1.0),
                                AmenTheme.Colors.glassStroke.opacity(searchText.isEmpty ? 0.35 : 0.6)
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
        .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.75), radius: 12, x: 0, y: 4)
        .shadow(color: AmenTheme.Colors.shadowCard.opacity(0.45), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
        .animation(.easeOut(duration: 0.15), value: searchText.isEmpty)
    }
    
    private var categoryPillsView: some View {
        LiquidGlassSegmentedControl(
            selection: $selectedCategory,
            categories: ResourceCategory.allCases
        )
    }
    
    // MARK: - Content View
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 28) {

            // ── Disaster Alerts — shown for All and Crisis categories ──
            if selectedCategory == .all || selectedCategory == .crisis {
                DisasterResourcesSection()
            }

            // ── Community Discovery Rails (gated by AppStorage flag) ──
            if selectedCategory == .all || selectedCategory == .community {
                AmenDiscoveryRailsView(
                    userId: Auth.auth().currentUser?.uid ?? ""
                ) { item in
                    if item.type == .church, let churchId = item.metadata["churchId"] {
                        selectedChurchId = churchId
                        showChurchHub = true
                    }
                }
                .frame(maxWidth: .infinity)
                .sheet(isPresented: $showChurchHub) {
                    if let churchId = selectedChurchId {
                        AmenChurchHubView(churchId: churchId, onDismiss: { showChurchHub = false })
                    }
                }
            }

            if supportSectionVisible {
                resourceSection(title: "For You", subtitle: supportSectionSubtitle) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !supportDomains.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(supportDomains, id: \.rawValue) { domain in
                                        Text(supportDomainLabel(domain))
                                            .font(AMENFont.semiBold(12))
                                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(AmenTheme.Colors.surfaceGrouped)
                                                    .overlay(
                                                        Capsule()
                                                            .stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
                                                    )
                                            )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                        VStack(spacing: 10) {
                            ForEach(supportSectionActions) { action in
                                supportActionView(action)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }

            // ── Church ── Notes + Find a Church (side-by-side liquid glass) ──
            if selectedCategory == .all || selectedCategory == .tools || selectedCategory == .community {
                resourceSection(title: "Church", subtitle: "Your faith home") {
                    HStack(spacing: 12) {
                        // Church Notes
                        NavigationLink(destination: ChurchNotesView()) {
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(
                                            colors: [Color(hex: "F59E0B").opacity(0.85), Color(hex: "FBBF24").opacity(0.60)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "note.text")
                                        .font(.systemScaled(16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Church Notes")
                                        .font(.systemScaled(14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Sermons, highlights & insights")
                                        .font(.systemScaled(11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                HStack(spacing: 3) {
                                    Text("Open")
                                        .font(.systemScaled(11, weight: .medium))
                                        .foregroundColor(Color(hex: "F59E0B"))
                                    Image(systemName: "arrow.right")
                                        .font(.systemScaled(9, weight: .semibold))
                                        .foregroundColor(Color(hex: "F59E0B"))
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color(hex: "F59E0B").opacity(0.35), Color.white.opacity(0.10)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.75
                                    )
                            )
                            .shadow(color: Color(hex: "F59E0B").opacity(0.08), radius: 12, x: 0, y: 4)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(ResourceCardPressStyle())

                        // Find a Church
                        NavigationLink(destination: FindChurchView()) {
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(
                                            colors: [Color(hex: "10B981").opacity(0.85), Color(hex: "34D399").opacity(0.60)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "mappin.and.ellipse")
                                        .font(.systemScaled(16, weight: .medium))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Find a Church")
                                        .font(.systemScaled(14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Text("Discover churches near you")
                                        .font(.systemScaled(11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                HStack(spacing: 3) {
                                    Text("Open")
                                        .font(.systemScaled(11, weight: .medium))
                                        .foregroundColor(Color(hex: "10B981"))
                                    Image(systemName: "arrow.right")
                                        .font(.systemScaled(9, weight: .semibold))
                                        .foregroundColor(Color(hex: "10B981"))
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color(hex: "10B981").opacity(0.35), Color.white.opacity(0.10)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.75
                                    )
                            )
                            .shadow(color: Color(hex: "10B981").opacity(0.08), radius: 12, x: 0, y: 4)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(ResourceCardPressStyle())
                    }
                    .padding(.horizontal, 20)
                }
            }

            // ── AMEN Connect ──
            if selectedCategory == .all || selectedCategory == .community {
                resourceSection(title: "Connect", subtitle: "Acts 2:42") {
                    NavigationLink(destination: AMENConnectView()) {
                        AMENConnectBanner()
                    }
                    .buttonStyle(ResourceCardPressStyle())
                    .padding(.horizontal, 20)
                }
            }
            
            // ── Support & Wellness ── 3-col grid (smaller cards) ─────────
            if selectedCategory == .all || selectedCategory == .crisis || selectedCategory == .mentalHealth {
                resourceSection(title: "Support & Wellness") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        NavigationLink(destination: CrisisResourcesDetailView()) {
                            FolderSquareCard(
                                icon: "phone.fill",
                                title: "Crisis Resources",
                                accentColor: Color(red: 0.82, green: 0.18, blue: 0.20),
                                folderColor: Color(red: 0.72, green: 0.13, blue: 0.16),
                                paperColor: Color(red: 1.0, green: 0.95, blue: 0.95)
                            )
                        }
                        .buttonStyle(ResourceCardPressStyle())

                        NavigationLink(destination: MentalHealthDetailView()) {
                            FolderSquareCard(
                                icon: "heart.text.square.fill",
                                title: "Mental Health",
                                accentColor: Color(red: 0.18, green: 0.60, blue: 0.36),
                                folderColor: Color(red: 0.12, green: 0.48, blue: 0.28),
                                paperColor: Color(red: 0.93, green: 0.99, blue: 0.95)
                            )
                        }
                        .buttonStyle(ResourceCardPressStyle())

                        NavigationLink(destination: GivingNonprofitsDetailView()) {
                            FolderSquareCard(
                                icon: "heart.circle.fill",
                                title: "Giving",
                                accentColor: Color(red: 0.15, green: 0.42, blue: 0.84),
                                folderColor: Color(red: 0.10, green: 0.32, blue: 0.72),
                                paperColor: Color(red: 0.93, green: 0.96, blue: 1.0)
                            )
                        }
                        .buttonStyle(ResourceCardPressStyle())
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            // ── Grow + Journey + Wisdom + Media ── compact rows ──────────
            if selectedCategory == .all || selectedCategory == .learning || selectedCategory == .community {
                resourceSection(title: "Faith & Learning") {
                    VStack(spacing: 10) {
                        // Walk With Christ
                        if selectedCategory == .all || selectedCategory == .learning || selectedCategory == .community {
                            NavigationLink(destination: WalkWithChristView()) {
                                CompactResourceRow(
                                    icon: "figure.walk",
                                    iconColors: [Color(hex: "10B981"), Color(hex: "34D399")],
                                    title: "Walk With Christ",
                                    subtitle: "Discipleship journey & devotionals"
                                )
                            }
                            .buttonStyle(ResourceCardPressStyle())
                        }
                    }
                }
            }

            // ── Search Results ────────────────────────────────────────────
            if !searchText.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    // Section header
                    HStack(spacing: 8) {
                        Image(systemName: useAISearch ? "sparkles" : "magnifyingglass")
                            .foregroundStyle(useAISearch ? Color.purple : .secondary)
                            .font(.systemScaled(14, weight: .semibold))
                        Text(useAISearch ? "AI Search Results" : "Search Results")
                            .font(AMENFont.bold(20))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text("\(searchFilteredResources.count)")
                            .font(AMENFont.bold(13))
                            .foregroundStyle(searchFilteredResources.isEmpty ? Color.red : Color(.label))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }
                    .padding(.horizontal, 20)
                    .id("searchResults")
                    
                    if useAISearch && !aiSearchResults.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.systemScaled(12))
                            Text("Results ranked by AI relevance")
                                .font(AMENFont.regular(13))
                        }
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal, 20)
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
                                    
                                    if useAISearch, index < aiSearchResults.count {
                                        Text(aiSearchResults[index].reason)
                                            .font(AMENFont.regular(11))
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 8)
                                            .padding(.top, 6)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 32)
    }
    
    // MARK: - Section builder helper
    @ViewBuilder
    private func resourceSection<Content: View>(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section title with subtle left-line accent
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 3, height: 18)
                    .clipShape(Capsule())
                Text(title)
                    .font(AMENFont.bold(18))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 20)
            
            content()
        }
    }

    private var supportSectionVisible: Bool {
        featureFlags.resourcesIntelligenceEnabled && (!supportSectionActions.isEmpty || !supportDomains.isEmpty)
    }

    private var supportSectionActions: [SupportAction] {
        let latestActions = supportCoordinator.lastDecision?.actions ?? []
        if !latestActions.isEmpty {
            return Array(latestActions.prefix(4))
        }
        return Array(supportCoordinator.currentProfile.suggestedActions.prefix(4))
    }

    private var supportDomains: [ResourceSupportDomain] {
        let latestDomains = supportCoordinator.lastDecision?.domains ?? []
        if !latestDomains.isEmpty {
            return Array(latestDomains.prefix(3))
        }
        return Array(supportCoordinator.currentProfile.recommendedDomains.prefix(3))
    }

    private var supportSectionSubtitle: String {
        if let decision = supportCoordinator.lastDecision, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return supportPromptCopy(for: decision)
        }
        return "Quietly shaped by your recent searches and care context"
    }

    private func handleSupportSearchChange(_ query: String) {
        supportAnalysisTask?.cancel()

        guard featureFlags.resourcesIntelligenceEnabled else { return }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }

        supportAnalysisTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            _ = await supportCoordinator.analyze(text: trimmed, surface: .search)
        }
    }

    private func supportPromptCopy(for decision: SupportRouteDecision) -> String {
        switch decision.promptType {
        case .crisisHelpRespectful:
            return "Immediate support options, kept private and calm"
        case .forFriendGuideSoft:
            return "Guidance for helping someone else without overstepping"
        case .noteCareSummary:
            return "Care and next steps based on what you have been reflecting on"
        case .practicalAidBridge:
            return "Practical help, church support, and next steps in one place"
        case .prayerSupportBridge, .churchCareRoute, .wellnessGroundingSubtle, .postAftercareGentle, .reachOutTrustedSoft, .giveRelevantPrivate, .recoveryReinforcementSoft:
            return "The right mix of prayer, people, and practical support"
        case nil:
            return "Quietly shaped by your recent searches and care context"
        }
    }

    private func supportDomainLabel(_ domain: ResourceSupportDomain) -> String {
        switch domain {
        case .crisisImmediate:
            return "Immediate Help"
        case .emotionalWellness:
            return "Wellness"
        case .anxietyStress:
            return "Anxiety & Stress"
        case .depressionHopelessness:
            return "Hopelessness"
        case .griefLoss:
            return "Grief"
        case .lonelinessCommunity:
            return "Community"
        case .churchHurt:
            return "Church Hurt"
        case .counselingTherapy:
            return "Counseling"
        case .marriageRelationships:
            return "Relationships"
        case .addictionRecovery:
            return "Recovery"
        case .financialNeed:
            return "Financial Help"
        case .foodHousingNeed:
            return "Food & Housing"
        case .pastoralCare:
            return "Pastoral Care"
        case .prayerSupport:
            return "Prayer"
        case .accountability:
            return "Accountability"
        case .bibleGuidance:
            return "Bible Guidance"
        case .serviceVolunteer:
            return "Serve"
        case .givingNonprofits:
            return "Giving"
        case .helpingSomeoneElse:
            return "Helping Someone"
        case .newcomerChurchDiscovery:
            return "Find a Church"
        }
    }

    @ViewBuilder
    private func supportActionView(_ action: SupportAction) -> some View {
        switch action.type {
        case .openFindChurch, .shareWithPastorOrCareTeam:
            NavigationLink(destination: FindChurchView()) {
                IntelligentSupportActionCard(
                    icon: "mappin.and.ellipse",
                    title: action.title,
                    subtitle: "Find churches, ministries, and care nearby.",
                    tint: Color(hex: "10B981")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .openCounselingResources, .openSupportGroups, .openGroundingExercise, .openBreathingTool:
            NavigationLink(destination: MentalHealthDetailView()) {
                IntelligentSupportActionCard(
                    icon: "heart.text.square.fill",
                    title: action.title,
                    subtitle: "Open calming tools, counseling paths, and wellness support.",
                    tint: Color(hex: "22C55E")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .openNonprofitResources:
            NavigationLink(destination: GivingNonprofitsDetailView()) {
                IntelligentSupportActionCard(
                    icon: "heart.circle.fill",
                    title: action.title,
                    subtitle: "Practical aid, benevolence, and trusted nonprofit actions.",
                    tint: Color(hex: "2563EB")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .openBerean:
            NavigationLink(destination: BereanLandingView()) {
                IntelligentSupportActionCard(
                    icon: "sparkles.rectangle.stack.fill",
                    title: action.title,
                    subtitle: "Let Berean help translate this moment into next steps.",
                    tint: Color(hex: "7C3AED")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .messageTrustedContact:
            NavigationLink(destination: TrustedCircleView()) {
                IntelligentSupportActionCard(
                    icon: "person.2.circle.fill",
                    title: action.title,
                    subtitle: "Reach out to your trusted circle with calm, editable support prompts.",
                    tint: Color(hex: "A855F7")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .openPrayerFlow, .convertToPrivatePrayer:
            NavigationLink(
                destination: PlaceholderResourceView(
                    title: "Prayer Support",
                    description: "Turn this moment into a private prayer flow with grounded next steps.",
                    icon: "hands.sparkles.fill",
                    iconColor: Color(hex: "F59E0B")
                )
            ) {
                IntelligentSupportActionCard(
                    icon: "hands.sparkles.fill",
                    title: action.title,
                    subtitle: "Move this into prayer without losing the practical next step.",
                    tint: Color(hex: "F59E0B")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .saveToPrivateNotes, .viewResourcePlan:
            NavigationLink(destination: ChurchNotesView()) {
                IntelligentSupportActionCard(
                    icon: "note.text",
                    title: action.title,
                    subtitle: "Keep it private, reflect, and return when you are ready.",
                    tint: Color(hex: "F97316")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .openHelpingSomeoneElse:
            NavigationLink(
                destination: PlaceholderResourceView(
                    title: "Helping Someone Else",
                    description: "Guidance for caring well, what to say, and when to escalate urgently.",
                    icon: "person.2.wave.2.fill",
                    iconColor: Color(hex: "EC4899")
                )
            ) {
                IntelligentSupportActionCard(
                    icon: "person.2.wave.2.fill",
                    title: action.title,
                    subtitle: "Signs to watch for, message templates, and safe escalation paths.",
                    tint: Color(hex: "EC4899")
                )
            }
            .buttonStyle(ResourceCardPressStyle())
        case .call988:
            Button {
                openSupportURL("tel://988")
            } label: {
                IntelligentSupportActionCard(
                    icon: "phone.fill",
                    title: action.title,
                    subtitle: "Immediate crisis support through the 988 Lifeline.",
                    tint: Color(hex: "DC2626")
                )
            }
            .buttonStyle(.plain)
        case .text988, .textCrisisLine:
            Button {
                openSupportURL("sms:988")
            } label: {
                IntelligentSupportActionCard(
                    icon: "message.fill",
                    title: action.title,
                    subtitle: "Text-based crisis help when calling feels too heavy.",
                    tint: Color(hex: "DC2626")
                )
            }
            .buttonStyle(.plain)
        case .call911:
            Button {
                openSupportURL("tel://911")
            } label: {
                IntelligentSupportActionCard(
                    icon: "cross.case.fill",
                    title: action.title,
                    subtitle: "Emergency services for immediate danger.",
                    tint: Color(hex: "B91C1C")
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func openSupportURL(_ rawValue: String) {
        guard let url = URL(string: rawValue) else { return }
        UIApplication.shared.open(url)
    }
    
    // MARK: - Keyboard Handling
    
    private func setupKeyboardObservers() {
        // Guard against duplicate registration on repeated onAppear calls.
        guard keyboardShowToken == nil else { return }

        keyboardShowToken = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = keyboardFrame.height
            }
        }

        keyboardHideToken = NotificationCenter.default.addObserver(
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
        if let token = keyboardShowToken {
            NotificationCenter.default.removeObserver(token)
            keyboardShowToken = nil
        }
        if let token = keyboardHideToken {
            NotificationCenter.default.removeObserver(token)
            keyboardHideToken = nil
        }
    }
    
    // MARK: - AI Search
    
    private func performAISearch() {
        guard !searchText.isEmpty else { return }

        // P1 FIX: Cancel any previous in-flight search before starting a new one.
        aiSearchTask?.cancel()

        let querySnapshot = searchText
        aiSearchTask = Task {
            await MainActor.run {
                isSearchingWithAI = true
                isSearchFocused = false
            }

            do {
                let results = try await AIResourceSearchService.shared.searchWithAI(
                    query: querySnapshot,
                    allResources: allResources
                )

                // Don't update state if the task was cancelled while awaiting.
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        aiSearchResults = results
                        useAISearch = true
                        isSearchingWithAI = false
                        scrollToResults = true
                    }
                }

            } catch {
                guard !Task.isCancelled else { return }
                // Fall back to keyword search on error.
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        useAISearch = false
                        isSearchingWithAI = false
                        scrollToResults = true
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: searchText.isEmpty ? "tray.fill" : "magnifyingglass")
                .font(.systemScaled(48))
                .foregroundStyle(.secondary.opacity(0.5))
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No resources in this category" : "No results found")
                    .font(AMENFont.bold(18))
                    .foregroundStyle(.primary)

                Text(searchText.isEmpty ?
                     "Try selecting 'All' to see all resources" :
                     "Try adjusting your search or filter")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !searchText.isEmpty || selectedCategory != .all {
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.8))) {
                        searchText = ""
                        selectedCategory = .all
                    }

                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                } label: {
                    Text("Clear Filters")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(AmenTheme.Colors.buttonPrimary)
                        )
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5))
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, y: 3)
        .padding(.horizontal)
    }
}

// MARK: - Compact Resource Row
/// Reusable compact navigation row used throughout ResourcesView for space-efficient entries.
struct CompactResourceRow: View {
    let icon: String
    let iconColors: [Color]
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: iconColors,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.systemScaled(17, weight: .medium))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
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
                        .font(.systemScaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .symbolEffect(.bounce, value: fact.id)
                        .padding(7)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                    
                    Text("Fun Bible Fact")
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.systemScaled(14, weight: .semibold))
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
                .font(AMENFont.regular(14))
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
    @State private var isVisible = false
    
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
                        .font(.systemScaled(26, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .symbolEffect(.pulse, options: .repeating.speed(0.7))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AMENFont.bold(22))
                        .foregroundStyle(.white)
                    
                    Text(subtitle)
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white.opacity(0.9))
                }
                
                Spacer()
            }
            
            Text(description)
                .font(AMENFont.regular(15))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
            
            HStack {
                Spacer()
                
                HStack(spacing: 6) {
                    Text("Explore Now")
                        .font(AMENFont.bold(14))
                    Image(systemName: "arrow.right")
                        .font(.systemScaled(12, weight: .bold))
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
            isVisible = true
            // P1 FIX: Only run shimmer while visible. The previous unconditional
            // repeatForever kept the animation alive even off-screen, wasting CPU.
            guard isVisible else { return }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                shimmerPhase = 400
            }
        }
        .onDisappear {
            isVisible = false
            // Reset so the animation restarts cleanly when the view reappears.
            shimmerPhase = 0
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    // Icon with glass effect
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: icon)
                            .font(.systemScaled(24))
                            .foregroundStyle(iconColor)
                            .symbolEffect(.bounce, value: isExpanded)
                    }
                    .glassEffect(.regular)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(AMENFont.bold(17))
                                .foregroundStyle(.primary)
                            
                            if let badge = badge {
                                badgeView(badge: badge)
                            }
                        }
                        
                        Text(description)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                        .font(.systemScaled(14, weight: .semibold))
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
                                    .font(.systemScaled(14))
                                    .foregroundStyle(iconColor)
                                
                                Text(feature)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.primary)
                            }
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        
                        Button {
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
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
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
    }
    
    // Helper views to reduce complexity
    @ViewBuilder
    private func badgeView(badge: String) -> some View {
        Text(badge)
            .font(AMENFont.bold(10))
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
                .font(AMENFont.bold(14))
            Image(systemName: "arrow.right.circle.fill")
                .font(.systemScaled(16))
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
                    .font(.systemScaled(24))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.bold(16))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(AMENFont.regular(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                Text(category)
                    .font(AMENFont.semiBold(11))
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
                .font(.systemScaled(14, weight: .semibold))
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
                        .font(.systemScaled(24, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Bible App")
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.primary)
                        
                        Text("YOUVERSION")
                            .font(AMENFont.bold(10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue)
                            )
                    }
                    
                    Text("Read, study, and share scripture")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text("External App")
                        .font(AMENFont.semiBold(11))
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
                    .font(.systemScaled(24))
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
                        .font(.systemScaled(24, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Pray.com")
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.primary)
                        
                        Text("FEATURED")
                            .font(AMENFont.bold(10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.purple)
                            )
                    }
                    
                    Text("Guided prayers, sleep stories, and worship")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    Text("External App")
                        .font(AMENFont.semiBold(11))
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
                    .font(.systemScaled(24))
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
                        .font(.systemScaled(48))
                        .foregroundStyle(iconColor)
                }
                
                VStack(spacing: 12) {
                    Text(title)
                        .font(AMENFont.bold(28))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(description)
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("More Resources Coming")
                        .font(AMENFont.bold(20))
                        .foregroundStyle(.primary)

                    Text("Additional study tools, commentaries, and devotionals are being reviewed for biblical accuracy before release.")
                        .font(AMENFont.regular(15))
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
        title: "AMEN Connect",
        description: "Connect with believers, ministries, and local opportunities",
        category: "Community"
    ),
    
    ResourceItem(
        icon: "figure.walk",
        iconColor: .orange,
        title: "Walk With Christ",
        description: "Discipleship journey and devotionals for daily growth",
        category: "Learning"
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
    
    ResourceItem(
        icon: "cross.case.fill",
        iconColor: .orange,
        title: "Church Tools",
        description: "Church notes and discovery tools for Sunday and beyond",
        category: "Tools"
    )
]


// MARK: - Liquid Glass Segmented Control with Morph + Slide

struct LiquidGlassSegmentedControl: View {
    @Binding var selection: ResourcesView.ResourceCategory
    let categories: [ResourcesView.ResourceCategory]
    
    @Namespace private var segmentAnimation
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { category in
                    segmentButton(for: category)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }
    
    @ViewBuilder
    private func segmentButton(for category: ResourcesView.ResourceCategory) -> some View {
        let isSelected = selection == category
        
        Button {
            selectCategory(category)
        } label: {
            Text(category.rawValue)
                .font(.custom(isSelected ? "OpenSans-Bold" : "OpenSans-Regular", size: 14))
                .foregroundStyle(isSelected ? .white : Color(.label).opacity(0.65))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        if isSelected {
                            // Filled black pill for selected
                            Capsule()
                                .fill(Color(.label))
                                .matchedGeometryEffect(
                                    id: "selectedSegment",
                                    in: segmentAnimation,
                                    properties: .frame,
                                    isSource: true
                                )
                                .shadow(color: Color(.label).opacity(0.20), radius: 6, x: 0, y: 3)
                        } else {
                            // Subtle outline pill for unselected
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                                .overlay(
                                    Capsule()
                                        .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                )
                .animation(.spring(response: 0.38, dampingFraction: 0.72), value: selection)
        }
        .buttonStyle(ResourcesSegmentButtonStyle())
    }
    
    private func selectCategory(_ category: ResourcesView.ResourceCategory) {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
            selection = category
        }
    }
}

// MARK: - Segment Button Style (Resources specific to avoid conflicts)

struct ResourcesSegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
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
                            .font(.systemScaled(60))
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
                                    .font(.systemScaled(14, weight: .bold))
                                    .foregroundStyle(.yellow)
                                    .symbolEffect(.pulse, options: .repeating)
                                
                                Text("NEW")
                                    .font(AMENFont.bold(12))
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
                                .font(AMENFont.bold(24))
                                .foregroundStyle(.white)
                            
                            Text("Join your church, university, or organization")
                                .font(AMENFont.regular(14))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineSpacing(2)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.systemScaled(32))
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
                .font(.systemScaled(14))
                .foregroundStyle(color)
            
            Text(text)
                .font(AMENFont.semiBold(12))
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
                                .font(.systemScaled(48, weight: .semibold))
                                .foregroundStyle(iconColor)
                                .symbolEffect(.pulse, options: .repeating)
                        }
                        
                        VStack(spacing: 16) {
                            // Coming Soon Badge
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.systemScaled(14, weight: .bold))
                                    .foregroundStyle(.orange)
                                
                                Text("COMING SOON")
                                    .font(AMENFont.bold(14))
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
                                .font(AMENFont.bold(32))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text(description)
                                .font(AMENFont.regular(16))
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
                                    .font(AMENFont.bold(18))
                            }
                            
                            Text("This feature is currently under development and will be available in a future update. We're building something amazing for you!")
                                .font(AMENFont.regular(15))
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
                                    .font(.systemScaled(16, weight: .semibold))
                                Text("Back to Resources")
                                    .font(AMENFont.bold(16))
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
                            .font(.systemScaled(24))
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
                .font(.systemScaled(18))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(text)
                .font(AMENFont.regular(15))
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
                        .font(.systemScaled(isFullWidth ? 22 : 20, weight: .semibold))
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
                                .font(AMENFont.bold(9))
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
                        .font(.systemScaled(14, weight: .semibold))
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
                        .font(.systemScaled(24, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))
                }
                
                // Title
                Text(title)
                    .font(AMENFont.bold(13))
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

struct IntelligentSupportActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tint.opacity(0.14))
                    .frame(width: 46, height: 46)

                Image(systemName: icon)
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AmenTheme.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(AmenTheme.Colors.borderSoft, lineWidth: 0.8)
                )
        )
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
                        .font(.systemScaled(20, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Expand/collapse button
                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                        isExpanded.toggle()
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.systemScaled(14, weight: .semibold))
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
                                .font(.systemScaled(12))
                                .foregroundStyle(accentColor)
                            
                            Text(feature)
                                .font(AMENFont.regular(14))
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
                            .font(.systemScaled(12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(6)
                            .background(Circle().fill(.ultraThinMaterial))
                        
                        Text("Daily Verse")
                            .font(AMENFont.bold(13))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    Text("\"For I know the plans I have for you,\" declares the LORD, \"plans to prosper you and not to harm you, plans to give you hope and a future.\"")
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.primary)
                        .lineSpacing(6)
                        .padding(.horizontal, 20)
                    
                    Text("Jeremiah 29:11")
                        .font(AMENFont.bold(14))
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
                dlog("⚠️ AIDailyVerseCard taking too long, using fallback")
                loadFailed = true
            }
        }
    }
}

// MARK: - ResourceHubCard
// Square cards used in the "Connect" section (Find Church / Church Notes)

struct ResourceHubCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    let bgColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icon zone — top half of card
            ZStack(alignment: .topLeading) {
                // Coloured soft top area
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(bgColor)
                    .frame(height: 70)
                
                Image(systemName: icon)
                    .font(.systemScaled(28, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .padding(16)
            }
            
            // Text zone — bottom half
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - WellnessCard
// Full-width cards for the "Support & Wellness" section.
// Design: warm soft rounded card with a coloured left accent stripe,
// generous padding, and an elevated-but-gentle depth — inspired by
// supportive category-card reference UI.

struct WellnessCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let detail: String
    let accentColor: Color
    let bgColor: Color
    
    var body: some View {
        HStack(spacing: 0) {
            // Left colour stripe — premium accent bar
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accentColor)
                .frame(width: 4)
                .padding(.vertical, 14)
                .padding(.leading, 16)

            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(bgColor)
                    .frame(width: 52, height: 52)

                Image(systemName: icon)
                    .font(.systemScaled(22, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .padding(.leading, 14)
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.bold(15))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(AMENFont.semiBold(12))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                
                Text(detail)
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 14)
            
            Spacer(minLength: 8)
            
            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
                .padding(.trailing, 18)
        }
        .frame(minHeight: 76)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: accentColor.opacity(0.10), radius: 12, x: 0, y: 5)
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - ResourceCardPressStyle
// Subtle press scale + opacity for all tappable resource cards

struct ResourceCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - MediaBannerPressStyle
// ButtonStyle for ChristianMediaBannerView — feeds isPressed into the banner
// so the inner press animation (card offset + scale) works without _onButtonGesture.

struct MediaBannerPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.mediaBannerIsPressed, configuration.isPressed)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Walk With Christ Entry Card
// Editorial hero card — immersive warm gradient + editorial typography.
// Lives in the "Grow" section of ResourcesView.

struct WalkWithChristEntryCard: View {
    @StateObject private var store = WalkWithChristStore.shared

    private let ink   = Color(red: 0.10, green: 0.09, blue: 0.09)
    private let warm  = Color(red: 0.62, green: 0.48, blue: 0.30)
    private let slate = Color(red: 0.38, green: 0.38, blue: 0.40)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Warm dusk gradient background — original AMEN composition
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.11, blue: 0.08),
                    Color(red: 0.38, green: 0.24, blue: 0.12),
                    Color(red: 0.60, green: 0.42, blue: 0.22),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            // Faint cross accent — very subtle
            Image(systemName: "cross")
                .font(.systemScaled(100, weight: .ultraLight))
                .foregroundStyle(Color.white.opacity(0.05))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16)
                .padding(.trailing, 20)

            // Bottom fade
            LinearGradient(
                colors: [ink.opacity(0.55), .clear],
                startPoint: .bottom, endPoint: .center
            )

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Eyebrow
                Text("DISCIPLESHIP")
                    .font(.systemScaled(9, weight: .semibold))
                    .kerning(2.5)
                    .foregroundStyle(Color.white.opacity(0.55))

                // Title
                Text("Walk With Christ")
                    .font(.systemScaled(24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .tracking(-0.3)

                // Subtitle / state
                if store.profile.onboardingComplete {
                    HStack(spacing: 6) {
                        Image(systemName: store.profile.pathAssigned.icon)
                            .font(.systemScaled(10, weight: .semibold))
                            .foregroundStyle(store.profile.pathAssigned.accentColor)
                        Text(store.profile.pathAssigned.rawValue)
                            .font(.systemScaled(12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                    )
                } else {
                    Text("Personalized guidance for every stage of your faith journey")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineSpacing(2)
                        .lineLimit(2)
                }

                // CTA chip
                HStack(spacing: 5) {
                    Text(store.profile.onboardingComplete ? "Continue" : "Start Your Path")
                        .font(.systemScaled(11, weight: .semibold))
                        .foregroundStyle(ink)
                    Image(systemName: "arrow.right")
                        .font(.systemScaled(9, weight: .semibold))
                        .foregroundStyle(ink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                )
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: ink.opacity(0.18), radius: 14, x: 0, y: 5)
    }
}

#Preview {
    ResourcesView()
}
