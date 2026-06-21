//
//  ChurchNotesView.swift
//  AMENAPP
//
//  Created by Steph on 1/20/26.
//
//  Smart church notes with Firebase backend integration
//  Liquid Glass Design - Production Ready
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct ChurchNotesView: View {
    @StateObject private var notesService = ChurchNotesService()
    @ObservedObject private var postsManager = PostsManager.shared
    @ObservedObject private var followService = FollowService.shared
    @State private var showingNewNote = false
    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all
    @State private var selectedNote: ChurchNote?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var isSearchFocused = false
    @AppStorage("hasSeenChurchNotesOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @Namespace private var animation

    // For You personalization: loaded on appear
    @State private var userChurchName: String? = nil
    @State private var userChurchTags: Set<String> = []

    enum FilterOption: String, CaseIterable {
        case forYou = "For You"
        case recent = "Recent"
        case following = "Following"
        case sharedWithMe = "Shared"
        case all = "All"
        case community = "Community"
        case favorites = "Favorites"

        var icon: String {
            switch self {
            case .forYou: return "sparkles"
            case .recent: return "clock.fill"
            case .following: return "person.2.fill"
            case .sharedWithMe: return "person.crop.circle.badge.checkmark"
            case .all: return "note.text"
            case .community: return "globe"
            case .favorites: return "star.fill"
            }
        }
    }
    
    var filteredNotes: [ChurchNote] {
        var filtered = notesService.notes
        let discoveryService = ChurchNotesDiscoveryService.shared

        // Apply filter with discovery algorithm
        switch selectedFilter {
        case .forYou:
            // Personalized "For You" feed with ranking algorithm
            let userFollowing = followService.following
            return discoveryService.getForYouFeed(
                from: filtered,
                userFollowing: userFollowing,
                userChurch: userChurchName,
                userTags: userChurchTags
            )

        case .recent:
            // Chronological feed - all recent notes
            return discoveryService.getRecentFeed(from: filtered)

        case .following:
            // Notes from followed users only
            let userFollowing = followService.following
            return discoveryService.getFollowingFeed(
                from: filtered,
                userFollowing: userFollowing
            )

        case .sharedWithMe:
            // Filter notes shared with current user
            guard let currentUserId = Auth.auth().currentUser?.uid else { break }
            filtered = filtered.filter { note in
                note.sharedWith.contains(currentUserId)
            }

        case .all:
            // All notes, sorted by date
            break

        case .community:
            // Community notes shown in OpenTable feed - handled separately in UI
            break

        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        }

        // Apply search
        if !searchText.isEmpty {
            filtered = notesService.searchNotes(query: searchText)
        }

        return filtered.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        bodyContent
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            // AMEN Liquid Glass — warm pearl base
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Minimal Typography Header (respects safe area for back button)
                MinimalTypographyHeader(
                    searchText: $searchText,
                    selectedFilter: $selectedFilter,
                    isScrolled: scrollOffset < -20,
                    onNewNote: {
                        withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7))) {
                            showingNewNote = true
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    },
                    notes: notesService.notes
                )
                
                // Smart Header Orchestrator (feature-flagged, off by default)
                SmartHeaderOrchestrator(
                    screenType: .church,
                    userName: Auth.auth().currentUser?.displayName ?? "",
                    intentMode: nil,
                    scrollOffset: max(0, -scrollOffset),
                    hasVerseReady: DailyVerseGenkitService.shared.todayVerse != nil
                )

                // Content with minimal list design or community feed
                Group {
                    if selectedFilter == .community {
                        // Show community church notes from OpenTable
                        ElegantChurchNotesFeedForChurchNotesView(
                            posts: postsManager.openTablePosts.filter { $0.churchNoteId != nil }
                        )
                        .transition(.opacity)
                    } else if notesService.isLoading {
                        MinimalLoadingView()
                            .transition(.opacity)
                    } else if filteredNotes.isEmpty {
                        MinimalEmptyState(
                            hasSearch: !searchText.isEmpty,
                            filterType: selectedFilter,
                            onCreateNote: {
                                withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.7))) {
                                    showingNewNote = true
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .medium)
                                haptic.impactOccurred()
                            }
                        )
                        .transition(.opacity)
                    } else {
                        MinimalNotesList(
                            notes: filteredNotes,
                            notesService: notesService,
                            scrollOffset: $scrollOffset,
                            onNoteSelected: { note in
                                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))) {
                                    selectedNote = note
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .fullScreenCover(isPresented: $showingNewNote) {
            ChurchNotesPremiumEditor(notesService: notesService, existingNote: nil)
        }
        .sheet(item: $selectedNote) { note in
            ChurchNotesPremiumEditor(notesService: notesService, existingNote: note)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showOnboarding) {
            ChurchNotesOnboardingView()
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Start real-time listener when view appears
            notesService.startListening()
            
            // Start follow service listener for discovery algorithm
            followService.startListening()

            // Show onboarding on first open
            if !hasSeenOnboarding {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showOnboarding = true
                }
            }

            // Fetch user's church for For You personalization
            Task {
                await loadUserChurchForPersonalization()
            }
        }
        .onDisappear {
            // Stop listener when view disappears
            notesService.stopListening()
            // Note: We keep followService listening as it's used app-wide
        }
    }

    // MARK: - For You Personalization

    /// Fetches the user's church name from Firestore `userChurchRelations`
    /// and common tags from their recent notes, used to power the For You feed ranking.
    private func loadUserChurchForPersonalization() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        lazy var db = Firestore.firestore()

        // 1. Look up user's most recent church relation (member or regular visitor)
        do {
            let snapshot = try await db.collection("userChurchRelations")
                .whereField("userId", isEqualTo: uid)
                .order(by: "since", descending: true)
                .limit(to: 1)
                .getDocuments()

            if let data = snapshot.documents.first?.data(),
               let churchId = data["churchId"] as? String {
                // Fetch church name from churches collection
                let churchDoc = try await db.collection("churches").document(churchId).getDocument()
                if let name = churchDoc.data()?["name"] as? String {
                    await MainActor.run { userChurchName = name }
                }
            }
        } catch {
            // Non-fatal — For You falls back to follow-based ranking
        }

        // 2. Derive popular tags from user's own notes (top 5 most used)
        do {
            let notesSnap = try await db.collection("churchNotes")
                .whereField("authorId", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .getDocuments()

            var tagCounts: [String: Int] = [:]
            for doc in notesSnap.documents {
                let tags = doc.data()["tags"] as? [String] ?? []
                tags.forEach { tagCounts[$0, default: 0] += 1 }
            }
            let topTags = Set(tagCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key))
            await MainActor.run { userChurchTags = topTags }
        } catch {
            // Non-fatal — tags default to empty set
        }
    }
}

// MARK: - Animated Gradient Background (Private to ChurchNotesView)

private struct ChurchNotesAnimatedGradientBackground: View {
    @State private var animateGradient = false
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        bodyContent
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            // Base gradient - warm cream to brown inspired by design
            LinearGradient(
                colors: [
                    Color(hex: "F5E9DD"), // Warm cream
                    Color(hex: "D4A574"), // Soft tan
                    Color(hex: "A67C52"), // Medium brown
                    Color(hex: "5C4033"), // Deep brown
                    Color(hex: "122D70")  // Deep blue-black
                ],
                startPoint: animateGradient ? .topLeading : .topTrailing,
                endPoint: animateGradient ? .bottomTrailing : .bottomLeading
            )
            
            // Overlay gradient for depth and movement
            RadialGradient(
                colors: [
                    Color(hex: "A67C52").opacity(0.4),
                    Color(hex: "122D70").opacity(0.6),
                    Color.black.opacity(0.8)
                ],
                center: UnitPoint(
                    x: 0.5 + cos(animationPhase) * 0.3,
                    y: 0.5 + sin(animationPhase) * 0.3
                ),
                startRadius: 100,
                endRadius: 800
            )
            .blendMode(.multiply)
            .opacity(0.7)
            
            // Subtle shimmer overlay
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.clear,
                    Color.white.opacity(0.05)
                ],
                startPoint: UnitPoint(
                    x: animationPhase / .pi,
                    y: 0
                ),
                endPoint: UnitPoint(
                    x: 1 + animationPhase / .pi,
                    y: 1
                )
            )
            .blendMode(.overlay)
        }
        .onAppear {
            // Smooth gradient animation
            withAnimation(
                .easeInOut(duration: 10.0)
                    .repeatForever(autoreverses: true)
            ) {
                animateGradient = true
            }
            
            // Radial movement animation
            withAnimation(
                .linear(duration: 20.0)
                    .repeatForever(autoreverses: false)
            ) {
                animationPhase = .pi * 2
            }
        }
    }
}



// MARK: - Liquid Glass Header

struct LiquidGlassHeader: View {
    @Binding var searchText: String
    let isScrolled: Bool
    let onNewNote: () -> Void
    @State private var isSearchFocused = false
    @State private var headerScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 16) {
            // Title and Add Button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Church Notes")
                        .font(.custom("OpenSans-Bold", size: isScrolled ? 28 : 32))
                        .foregroundStyle(.white)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isScrolled)
                    
                    if !isScrolled {
                        Text("Sermons, insights, & reflections")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.white.opacity(0.7))
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .scaleEffect(headerScale)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: headerScale)
                
                Spacer()
                
                Button {
                    // Bounce animation on tap
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.5))) {
                        headerScale = 0.95
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.5))) {
                            headerScale = 1.0
                        }
                    }
                    
                    let haptic = UIImpactFeedbackGenerator(style: .medium)
                    haptic.impactOccurred()
                    onNewNote()
                } label: {
                    ZStack {
                        // Base frosted glass
                        Circle()
                            .fill(.thinMaterial)
                        
                        // Warm gradient overlay
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "D4A574").opacity(0.5),
                                        Color(hex: "A67C52").opacity(0.6)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Icon
                        Image(systemName: "plus")
                            .font(.systemScaled(20, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        // Border with warm glow
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color(hex: "F5E9DD").opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                    .frame(width: 50, height: 50)
                    .shadow(color: Color(hex: "A67C52").opacity(0.4), radius: 12, y: 6)
                    .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
                }
                .scaleEffect(headerScale == 1.0 ? 1.0 : 0.9)
                .rotationEffect(.degrees(headerScale == 1.0 ? 0 : 90))
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: headerScale)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            // Frosted Glass Search Bar inspired by "Ask AI" design
            HStack(spacing: 14) {
                // Leading button/icon
                Button(action: {
                    // Optional: Add search filter or quick action
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                }) {
                    ZStack {
                        Circle()
                            .fill(.thinMaterial)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                            )
                        
                        Image(systemName: "plus")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
                .opacity(isSearchFocused ? 0 : 1)
                .scaleEffect(isSearchFocused ? 0.8 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSearchFocused)
                
                // Search field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.systemScaled(16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    TextField("", text: $searchText, prompt: Text("Search notes, sermons, scriptures...").foregroundStyle(.white.opacity(0.4)))
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.white)
                        .tint(Color(hex: "A67C52"))
                        .onTapGesture {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                isSearchFocused = true
                            }
                        }
                        .onChange(of: searchText) { oldValue, newValue in
                            // P1 FIX: Only trigger haptic on meaningful transitions (start typing or clear)
                            // Avoids haptic on every character which can cause input lag
                            if newValue.isEmpty && !oldValue.isEmpty {
                                // User cleared search
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            } else if oldValue.isEmpty && !newValue.isEmpty {
                                // User started typing
                                let haptic = UISelectionFeedbackGenerator()
                                haptic.selectionChanged()
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                searchText = ""
                                isSearchFocused = false
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    ZStack {
                        // Frosted glass base
                        Capsule()
                            .fill(.thinMaterial)
                        
                        // White overlay for more opacity
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSearchFocused ? 0.25 : 0.15),
                                        Color.white.opacity(isSearchFocused ? 0.15 : 0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Subtle inner shadow
                        Capsule()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.black.opacity(0.0),
                                        Color.black.opacity(0.05)
                                    ],
                                    center: .center,
                                    startRadius: 100,
                                    endRadius: 200
                                )
                            )
                        
                        // Border
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSearchFocused ? 0.4 : 0.25),
                                        Color.white.opacity(isSearchFocused ? 0.2 : 0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSearchFocused ? 1.5 : 1
                            )
                    }
                )
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 8)
                
                // Trailing button (voice/action)
                Button(action: {
                    // Optional: Add voice search or filter
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                }) {
                    ZStack {
                        Circle()
                            .fill(.thinMaterial)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                            )
                            .overlay(
                                Circle()
                                    .fill(Color(hex: "122D70").opacity(0.6))
                            )
                        
                        Image(systemName: "waveform")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color(hex: "122D70").opacity(0.3), radius: 8, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .scaleEffect(isSearchFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSearchFocused)
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let filter: ChurchNotesView.FilterOption
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: filter.icon)
                    .font(.systemScaled(14, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(AMENFont.semiBold(15))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    // Frosted glass base
                    Capsule()
                        .fill(.thinMaterial)
                    
                    // Selected state overlay
                    if isSelected {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "A67C52").opacity(0.4),
                                        Color(hex: "5C4033").opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    }
                    
                    // Border
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? 0.4 : 0.25),
                                    Color(hex: "D4A574").opacity(isSelected ? 0.3 : 0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
            )
            .shadow(color: isSelected ? Color(hex: "A67C52").opacity(0.3) : Color.black.opacity(0.1), radius: isSelected ? 12 : 6, y: isSelected ? 6 : 3)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
    }
}

// MARK: - Loading Glass View

struct LoadingGlassView: View {
    @State private var isAnimating = false
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Animated ripple circles with warm colors
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: "D4A574").opacity(0.3),
                                    Color(hex: "A67C52").opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 100 - CGFloat(index * 20), height: 100 - CGFloat(index * 20))
                        .scaleEffect(isAnimating ? 1.5 : 0.5)
                        .opacity(isAnimating ? 0.0 : 0.8)
                        .animation(
                            .easeInOut(duration: 1.8)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.3),
                            value: isAnimating
                        )
                }
                
                // Center icon container
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "D4A574").opacity(0.3),
                                    Color(hex: "A67C52").opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Image(systemName: "note.text")
                        .font(.systemScaled(32))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(rotationAngle))
                    
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color(hex: "F5E9DD").opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .frame(width: 80, height: 80)
                .shadow(color: Color(hex: "A67C52").opacity(0.3), radius: 15, y: 8)
            }
            .frame(width: 160, height: 160)
            
            Text("Loading Notes...")
                .font(AMENFont.semiBold(18))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = true
            
            withAnimation(
                .linear(duration: 3.0)
                    .repeatForever(autoreverses: false)
            ) {
                rotationAngle = 360
            }
        }
    }
}

// MARK: - Empty State Glass View

struct EmptyStateGlassView: View {
    let hasSearch: Bool
    let filterType: ChurchNotesView.FilterOption
    let onCreateNote: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 60)
                
                // Glass Icon Container
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.05))
                        .frame(width: 160, height: 160)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true),
                            value: isAnimating
                        )
                    
                    Image(systemName: hasSearch ? "magnifyingglass" : "note.text")
                        .font(.systemScaled(64, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 140, height: 140)
                        .amenGlassEffect(in: Circle())
                }
                
                // Message
                VStack(spacing: 12) {
                    Text(emptyTitle)
                        .font(AMENFont.bold(28))
                        .foregroundStyle(.white)
                    
                    Text(emptySubtitle)
                        .font(AMENFont.regular(16))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 40)
                
                // Create Button with warm glassmorphic design
                if !hasSearch && filterType == .all {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        onCreateNote()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.systemScaled(20))
                            Text("Create Your First Note")
                                .font(AMENFont.bold(17))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(.thinMaterial)
                                
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(hex: "D4A574").opacity(0.6),
                                                Color(hex: "A67C52").opacity(0.7)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                Capsule()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color(hex: "F5E9DD").opacity(0.3)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        )
                        .shadow(color: Color(hex: "A67C52").opacity(0.4), radius: 20, y: 10)
                        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            isAnimating = true
        }
    }
    
    var emptyTitle: String {
        if hasSearch {
            return "No Results Found"
        }
        switch filterType {
        case .all:
            return "No Notes Yet"
        case .favorites:
            return "No Favorites"
        case .recent:
            return "No Recent Notes"
        case .forYou:
            return "No Recommended Notes"
        case .following:
            return "No Notes from Following"
        case .sharedWithMe:
            return "No Shared Notes"
        case .community:
            return "No Community Notes"
        }
    }
    
    var emptySubtitle: String {
        if hasSearch {
            return "Try different keywords or check your spelling"
        }
        switch filterType {
        case .all:
            return "Start capturing sermon insights, reflections, and scriptures"
        case .favorites:
            return "Star notes to add them to your favorites"
        case .recent:
            return "Notes from the last 7 days will appear here"
        case .forYou:
            return "Personalized notes based on your interests will appear here"
        case .following:
            return "Notes from people you follow will appear here"
        case .sharedWithMe:
            return "Notes that friends have shared with you will appear here"
        case .community:
            return "Community shared notes will appear here"
        }
    }
}

// MARK: - Notes Grid View

struct NotesGridView: View {
    let notes: [ChurchNote]
    @ObservedObject var notesService: ChurchNotesService
    @Binding var scrollOffset: CGFloat
    let onNoteSelected: (ChurchNote) -> Void
    
    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scroll")).minY
                )
            }
            .frame(height: 0)
            
            LazyVStack(spacing: 16) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    LiquidGlassNoteCard(
                        note: note,
                        notesService: notesService,
                        onTap: { onNoteSelected(note) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.8)
                            .delay(Double(index) * 0.05),
                        value: notes.count
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 40)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
        .refreshable {
            await notesService.fetchNotes()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Liquid Glass Note Card

struct LiquidGlassNoteCard: View {
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    let onTap: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var isPressed = false
    @State private var cardScale: CGFloat = 1.0
    @State private var cardRotation: Double = 0
    @State private var showShareToOpenTable = false
    @State private var showShareSheet = false
    @State private var isSharing = false
    @State private var showCopiedToast = false
    
    var body: some View {
        Button {
            // Smart haptic feedback
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
            
            // Animated press effect
            withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.6))) {
                cardScale = 0.97
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                    cardScale = 1.0
                }
                onTap()
            }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                // Header with smooth animations
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.title)
                            .font(AMENFont.bold(20))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.systemScaled(12))
                                    .foregroundStyle(.purple.opacity(0.8))
                                Text(sermonTitle)
                                    .font(AMENFont.semiBold(14))
                            }
                            .foregroundStyle(.white.opacity(0.7))
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    
                    Spacer()
                    
                    // Animated Favorite Button with warm glow
                    Button {
                        Task {
                            try? await notesService.toggleFavorite(note)
                            
                            // Fun bounce animation
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.4))) {
                                cardRotation = note.isFavorite ? -10 : 10
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.6))) {
                                    cardRotation = 0
                                }
                            }
                            
                            let haptic = UINotificationFeedbackGenerator()
                            haptic.notificationOccurred(note.isFavorite ? .success : .warning)
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)
                            
                            Circle()
                                .fill(Color.white.opacity(0.1))
                            
                            if note.isFavorite {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color(hex: "FFD700").opacity(0.3),
                                                Color(hex: "FFA500").opacity(0.15)
                                            ],
                                            center: .center,
                                            startRadius: 5,
                                            endRadius: 30
                                        )
                                    )
                                    .scaleEffect(1.4)
                                    .blur(radius: 8)
                            }
                            
                            Image(systemName: note.isFavorite ? "star.fill" : "star")
                                .font(.systemScaled(20))
                                .foregroundStyle(
                                    note.isFavorite 
                                        ? LinearGradient(
                                            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        : LinearGradient(
                                            colors: [Color.white.opacity(0.6), Color.white.opacity(0.4)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                )
                                .scaleEffect(note.isFavorite ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: note.isFavorite)
                            
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color(hex: "D4A574").opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .frame(width: 44, height: 44)
                        .shadow(
                            color: note.isFavorite ? Color(hex: "FFA500").opacity(0.4) : Color.black.opacity(0.1),
                            radius: note.isFavorite ? 10 : 5,
                            y: 3
                        )
                    }
                    .rotationEffect(.degrees(cardRotation))
                }
                
                // Content Preview with smart truncation
                if !note.content.isEmpty {
                    Text(note.content)
                        .font(AMENFont.regular(15))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                
                // Scripture Badge with warm glow effect
                if let scripture = note.scripture, !scripture.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.systemScaled(13))
                        Text(scripture)
                            .font(AMENFont.semiBold(14))
                    }
                    .foregroundStyle(Color(hex: "D4A574"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(.thinMaterial)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: "F5E9DD").opacity(0.2),
                                            Color(hex: "A67C52").opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: "D4A574").opacity(0.4),
                                            Color(hex: "A67C52").opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: Color(hex: "A67C52").opacity(0.25), radius: 10, y: 4)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                
                // Footer with metadata
                HStack(spacing: 16) {
                    // Date
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.systemScaled(12))
                        Text(note.date, style: .date)
                            .font(AMENFont.regular(13))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    
                    if let churchName = note.churchName, !churchName.isEmpty {
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        
                        HStack(spacing: 6) {
                            Image(systemName: "building.2")
                                .font(.systemScaled(12))
                            Text(churchName)
                                .font(AMENFont.regular(13))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    }
                    
                    Spacer()

                    // Animated Tags with warm tones
                    if !note.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(note.tags.prefix(2), id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundStyle(Color(hex: "F5E9DD").opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        ZStack {
                                            Capsule()
                                                .fill(.ultraThinMaterial)

                                            Capsule()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color(hex: "5C4033").opacity(0.3),
                                                            Color(hex: "122D70").opacity(0.2)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )

                                            Capsule()
                                                .strokeBorder(Color(hex: "D4A574").opacity(0.3), lineWidth: 0.5)
                                        }
                                    )
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }

                    // Small Share Button
                    Button {
                        showShareSheet = true
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.thinMaterial)

                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            Color(hex: "D4A574").opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Image(systemName: "square.and.arrow.up")
                                .font(.systemScaled(14, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.9),
                                            Color(hex: "D4A574").opacity(0.7)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color(hex: "D4A574").opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .frame(width: 32, height: 32)
                        .shadow(color: Color.black.opacity(0.1), radius: 4, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isSharing)
                    .opacity(isSharing ? 0.5 : 1.0)
                }
            }
            .padding(20)
            .background(
                ZStack {
                    // Base frosted glass layer
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.thinMaterial)
                    
                    // Warm gradient overlay matching the design
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color(hex: "F5E9DD").opacity(0.08),
                                    Color(hex: "A67C52").opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Subtle color tint for depth
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: "A67C52").opacity(0.03),
                                    Color.clear
                                ],
                                center: .topLeading,
                                startRadius: 50,
                                endRadius: 300
                            )
                        )
                    
                    // Glass border with warm tones
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color(hex: "D4A574").opacity(0.15),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                    
                    // Inner glow
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        .blur(radius: 2)
                        .offset(x: 0, y: 1)
                }
            )
            .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
            .shadow(color: Color(hex: "A67C52").opacity(0.1), radius: 30, x: 0, y: 15)
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .scaleEffect(cardScale)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cardScale)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                Task {
                    try? await notesService.toggleFavorite(note)
                }
            } label: {
                Label(note.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: note.isFavorite ? "star.slash" : "star.fill")
            }

            Button {
                showShareSheet = true
            } label: {
                Label("Share Note", systemImage: "square.and.arrow.up")
            }

            Button {
                showShareToOpenTable = true
            } label: {
                Label("Share to #OPENTABLE", systemImage: "bubble.left.and.bubble.right")
            }
            
            Button {
                copyNoteShareLink()
            } label: {
                Label("Copy Note Link", systemImage: "link")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Share to #OPENTABLE", isPresented: $showShareToOpenTable) {
            Button("Cancel", role: .cancel) { }
            Button("Share") {
                Task {
                    await shareNoteToOpenTable()
                }
            }
        } message: {
            Text("Share this church note to your #OPENTABLE feed? Your followers will be able to see it.")
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await notesService.deleteNote(note)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            ChurchNoteShareOptionsSheet(note: note)
        }
        .overlay(alignment: .bottom) {
            // Toast notification for copy confirmation
            if showCopiedToast {
                Text("Link copied to clipboard")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    )
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Share to OpenTable Function

    private func shareNoteToOpenTable() async {
        isSharing = true

        // Format the note content for sharing
        let shareContent = """
        📝 Church Note: \(note.title)

        \(note.content)

        \(note.scripture.map { "📖 " + $0 } ?? "")

        \(note.sermonTitle.map { "🎤 Sermon: " + $0 } ?? "")
        \(note.churchName.map { "⛪️ " + $0 } ?? "")
        """

        do {
            // Create post via FirebasePostService — pass churchNoteId so AI detection
            // is skipped (church note content is the user's own sermon notes, not AI-generated).
            try await FirebasePostService.shared.createPost(
                content: shareContent.trimmingCharacters(in: .whitespacesAndNewlines),
                category: .openTable,
                topicTag: "Church Notes",
                visibility: .everyone,
                allowComments: true,
                imageURLs: nil,
                linkURL: nil,
                churchNoteId: note.id
            )

            // Success haptic
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }

            dlog("✅ Church note shared to #OPENTABLE")
        } catch {
            dlog("❌ Failed to share church note: \(error)")
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.error)
            }
        }

        isSharing = false
    }
    
    // MARK: - Copy Note Share Link
    
    private func copyNoteShareLink() {
        guard let linkId = note.shareLinkId else {
            dlog("❌ Note has no share link ID")
            return
        }
        
        // Create shareable deep link
        let shareURL = "amenapp://note/\(linkId)"
        UIPasteboard.general.string = shareURL
        
        // Show toast confirmation with animation
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
            showCopiedToast = true
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        dlog("✅ Note link copied: \(shareURL)")
        
        // Hide toast after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCopiedToast = false
                }
            }
        }
    }
}

// MARK: - Church Note Card (Legacy - Keep for backwards compatibility)

struct ChurchNoteCard: View {
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        // Legacy card - redirect to Liquid Glass version
        LiquidGlassNoteCard(note: note, notesService: notesService, onTap: {})
    }
}

// MARK: - New Note View with Liquid Glass

struct NewChurchNoteView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var title = ""
    @State private var sermonTitle = ""
    @State private var churchName = ""
    @State private var pastor = ""
    @State private var selectedDate = Date()
    @State private var content = ""
    @State private var scripture = ""
    @State private var keyPoints: [String] = []
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showSaveConfirmation = false
    @State private var saveConfirmationScale: CGFloat = 0.5
    @State private var worshipSongs: [WorshipSongReference] = []
    @State private var showWorshipPicker = false
    
    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
    var body: some View {
        bodyContent
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                    Color(red: 0.10, green: 0.08, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        dismiss()
                    }
                    .font(AMENFont.semiBold(17))
                    .foregroundStyle(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("New Note")
                        .font(AMENFont.bold(20))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        saveNote()
                    } label: {
                        ZStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.systemScaled(18, weight: .semibold))
                                    .foregroundStyle(canSave ? .white : .white.opacity(0.4))
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(canSave ? 0.15 : 0.05),
                                            .white.opacity(canSave ? 0.08 : 0.02)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    .white.opacity(canSave ? 0.2 : 0.1),
                                    lineWidth: 0.5
                                )
                        )
                    }
                    .disabled(!canSave || isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Title Field
                        GlassTextField(
                            icon: "pencil",
                            placeholder: "Note Title",
                            text: $title,
                            isLarge: true
                        )
                        
                        // Sermon Details Card
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Sermon Details", systemImage: "quote.bubble")
                                .font(AMENFont.bold(16))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            VStack(spacing: 12) {
                                GlassTextField(
                                    icon: "mic",
                                    placeholder: "Sermon Title (Optional)",
                                    text: $sermonTitle
                                )
                                
                                // Date Picker - Left Aligned with Glassmorphic Design
                                HStack {
                                    HStack(spacing: 10) {
                                        Image(systemName: "calendar")
                                            .font(.systemScaled(16, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.7))
                                        
                                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                            .datePickerStyle(.compact)
                                            .labelsHidden()
                                            .tint(.white)
                                            .colorScheme(.dark)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        .white.opacity(0.12),
                                                        .white.opacity(0.06)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                    
                                    Spacer()
                                }
                                
                                HStack(spacing: 12) {
                                    GlassTextField(
                                        icon: "building.2",
                                        placeholder: "Church Name",
                                        text: $churchName
                                    )
                                    
                                    GlassTextField(
                                        icon: "person",
                                        placeholder: "Pastor",
                                        text: $pastor
                                    )
                                }
                            }
                        }
                        .padding(20)
                        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 20))
                        
                        // Scripture
                        GlassTextField(
                            icon: "book.fill",
                            placeholder: "Scripture Reference (e.g., John 3:16)",
                            text: $scripture,
                            tintColor: .purple
                        )
                        
                        // Content Editor with Rich Text Formatting
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Notes", systemImage: "note.text")
                                .font(AMENFont.bold(16))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            RichTextEditorView(
                                text: $content,
                                placeholder: "Start writing your sermon notes...",
                                minHeight: 200
                            )
                            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(20)
                        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 20))
                        
                        // Tags Section
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Tags", systemImage: "tag")
                                .font(AMENFont.bold(16))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            if !tags.isEmpty {
                                AMENFlowLayout(spacing: 8) {
                                    ForEach(tags, id: \.self) { tag in
                                        TagPill(tag: tag) {
                                            withAnimation {
                                                tags.removeAll { $0 == tag }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            HStack(spacing: 12) {
                                GlassTextField(
                                    icon: "tag",
                                    placeholder: "Add a tag",
                                    text: $newTag,
                                    onSubmit: {
                                        addTag()
                                    }
                                )
                                
                                Button {
                                    addTag()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.systemScaled(32))
                                        .foregroundStyle(.cyan.opacity(0.9))
                                }
                                .disabled(newTag.isEmpty)
                            }
                        }
                        .padding(20)
                        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 20))

                        // ── Worship Music Section ──────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Worship Music", systemImage: "music.note.list")
                                    .font(AMENFont.bold(16))
                                    .foregroundStyle(.white.opacity(0.9))

                                Spacer()

                                Button {
                                    showWorshipPicker = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Song")
                                    }
                                    .font(.systemScaled(14, weight: .semibold))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(Color.purple.opacity(0.18))
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if worshipSongs.isEmpty {
                                HStack(spacing: 10) {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.white.opacity(0.3))
                                    Text("Tap \u{201C}Add Song\u{201D} to attach worship music to this note")
                                        .font(.systemScaled(13))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                .padding(.vertical, 4)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(worshipSongs) { song in
                                        HStack(spacing: 10) {
                                            Image(systemName: "music.note")
                                                .font(.systemScaled(14))
                                                .foregroundStyle(.purple)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(song.title)
                                                    .font(.systemScaled(14, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text(song.artist)
                                                    .font(.systemScaled(12))
                                                    .foregroundStyle(.white.opacity(0.55))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button {
                                                withAnimation {
                                                    worshipSongs.removeAll { $0.id == song.id }
                                                }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundStyle(.red.opacity(0.7))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.white.opacity(0.06))
                                        )
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 20))
                        // ─────────────────────────────────────────────────
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showWorshipPicker) {
            WorshipSongPickerSheet(noteId: nil) { ref in
                withAnimation {
                    if !worshipSongs.contains(where: {
                        $0.title == ref.title && $0.artist == ref.artist
                    }) {
                        worshipSongs.append(ref)
                    }
                }
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .overlay {
            if showSaveConfirmation {
                ZStack {
                    // Backdrop blur
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .transition(.opacity)
                    
                    // Confirmation Card
                    VStack(spacing: 16) {
                        // Success Icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.15),
                                            .white.opacity(0.08)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 64, height: 64)
                            
                            Image(systemName: "checkmark")
                                .font(.systemScaled(32, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .scaleEffect(saveConfirmationScale)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: saveConfirmationScale)
                        
                        VStack(spacing: 8) {
                            Text("Note Saved!")
                                .font(AMENFont.bold(22))
                                .foregroundStyle(.white)
                            
                            Text("Your sermon notes have been saved successfully")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.15),
                                        .white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    )
                    .padding(.horizontal, 40)
                    .scaleEffect(saveConfirmationScale)
                    .transition(.scale.combined(with: .opacity))
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showSaveConfirmation)
            }
        }
    }
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !tags.contains(trimmed) else { return }
        
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            tags.append(trimmed)
            newTag = ""
            
            let haptic = UIImpactFeedbackGenerator(style: .light)
            haptic.impactOccurred()
        }
    }
    
    private func saveNote() {
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            errorMessage = "You must be signed in to create notes."
            showErrorAlert = true
            return
        }
        
        guard canSave else { return }
        
        isSaving = true
        
        let note = ChurchNote(
            userId: userId,
            title: title,
            sermonTitle: sermonTitle.isEmpty ? nil : sermonTitle,
            churchName: churchName.isEmpty ? nil : churchName,
            pastor: pastor.isEmpty ? nil : pastor,
            date: selectedDate,
            content: content,
            scripture: scripture.isEmpty ? nil : scripture,
            keyPoints: [],
            tags: tags,
            worshipSongs: worshipSongs
        )
        
        Task {
            do {
                try await notesService.createNote(note)
                
                await MainActor.run {
                    isSaving = false
                    
                    // Show save confirmation
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                        showSaveConfirmation = true
                        saveConfirmationScale = 1.0
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    // Dismiss after showing confirmation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save note. Please try again."
                    showErrorAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Glass TextField

struct GlassTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var isLarge: Bool = false
    var tintColor: Color = .white
    var onSubmit: (() -> Void)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(isLarge ? 18 : 16))
                .foregroundStyle(tintColor.opacity(0.6))
                .frame(width: 24)
            
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.5)))
                .font(.custom(isLarge ? "OpenSans-Bold" : "OpenSans-Regular", size: isLarge ? 20 : 16))
                .foregroundStyle(.white)
                .tint(tintColor)
                .onSubmit {
                    onSubmit?()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isLarge ? 16 : 14)
        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Text("#\(tag)")
                .font(AMENFont.semiBold(14))
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.systemScaled(16))
            }
        }
        .foregroundStyle(.cyan.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .amenGlassEffect(in: Capsule())
    }
}

// MARK: - Flow Layout
// Note: FlowLayout is defined in OnboardingAdvancedComponents.swift and reused here

// MARK: - Church Note Detail View with Liquid Glass

private enum ChurchNoteDetailSheet: Identifiable {
    case shareOptions
    case shareToOpenTable
    case shareWithFriends

    var id: String {
        switch self {
        case .shareOptions: return "shareOptions"
        case .shareToOpenTable: return "shareToOpenTable"
        case .shareWithFriends: return "shareWithFriends"
        }
    }
}

struct ChurchNoteDetailView: View {
    @Environment(\.dismiss) var dismiss
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var showDeleteConfirmation = false
    @State private var activeSheet: ChurchNoteDetailSheet?
    @State private var showCopiedToast = false
    @State private var showPrayerSaved = false
    @State private var localWorshipSongs: [WorshipSongReference] = []

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.12, green: 0.10, blue: 0.18),
                    Color(red: 0.10, green: 0.08, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .amenGlassEffect(in: Circle())
                    }
                    
                    Spacer()
                    
                    // Favorite Button
                    Button {
                        Task {
                            try? await notesService.toggleFavorite(note)
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }
                    } label: {
                        Image(systemName: note.isFavorite ? "star.fill" : "star")
                            .font(.systemScaled(20))
                            .foregroundStyle(note.isFavorite ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .amenGlassEffect(in: Circle())
                    }
                    
                    // Menu Button
                    Menu {
                        Button {
                            shareToOpenTable()
                        } label: {
                            Label("Share to #OPENTABLE", systemImage: "bubble.left.and.bubble.right")
                        }
                        
                        Divider()
                        
                        Button {
                            activeSheet = .shareWithFriends
                        } label: {
                            Label("Share with Friends", systemImage: "person.2.fill")
                        }
                        
                        Button {
                            activeSheet = .shareOptions
                        } label: {
                            Label("Share Externally", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            copyNoteShareLink()
                        } label: {
                            Label("Copy Note Link", systemImage: "link")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.systemScaled(20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .amenGlassEffect(in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title and Metadata
                        VStack(alignment: .leading, spacing: 16) {
                            Text(note.title)
                                .font(AMENFont.bold(32))
                                .foregroundStyle(.white)
                                .lineSpacing(4)
                            
                            if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "quote.bubble.fill")
                                        .font(.systemScaled(16))
                                    Text(sermonTitle)
                                        .font(AMENFont.semiBold(18))
                                }
                                .foregroundStyle(.white.opacity(0.8))
                            }
                            
                            // Metadata Pills
                            AMENFlowLayout(spacing: 10) {
                                if let churchName = note.churchName, !churchName.isEmpty {
                                    MetadataPill(icon: "building.2", text: churchName)
                                }
                                
                                if let pastor = note.pastor, !pastor.isEmpty {
                                    MetadataPill(icon: "person", text: pastor)
                                }
                                
                                MetadataPill(icon: "calendar", text: note.date.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                        .padding(24)
                        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 24))
                        
                        // Scripture
                        if let scripture = note.scripture, !scripture.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "book.fill")
                                    .font(.systemScaled(20))
                                    .foregroundStyle(.purple)
                                
                                Text(scripture)
                                    .font(AMENFont.bold(18))
                                    .foregroundStyle(.purple.opacity(0.9))
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 20))
                        }
                        
                        // Content
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Notes", systemImage: "note.text")
                                .font(AMENFont.bold(18))
                                .foregroundStyle(.white.opacity(0.9))

                            // Accessibility Intelligence Layer — reader controls
                            if AMENFeatureFlags.shared.accessibilityIntelligenceEnabled {
                                VStack(alignment: .leading, spacing: 12) {
                                    AILReadingLevelControl()
                                    AILTranslatePill(originalText: note.content, originalRef: note.id ?? "")
                                }
                            }

                            Text(note.content)
                                .font(AMENFont.regular(17))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(8)
                        }
                        .padding(24)
                        .amenGlassEffect(in: RoundedRectangle(cornerRadius: 24))
                        
                        // Tags
                        if !note.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Tags", systemImage: "tag")
                                    .font(AMENFont.bold(18))
                                    .foregroundStyle(.white.opacity(0.9))

                                AMENFlowLayout(spacing: 10) {
                                    ForEach(note.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(AMENFont.semiBold(15))
                                            .foregroundStyle(.cyan.opacity(0.9))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .amenGlassEffect(in: Capsule())
                                    }
                                }
                            }
                            .padding(24)
                            .amenGlassEffect(in: RoundedRectangle(cornerRadius: 24))
                        }

                        // Saved worship songs — always visible when the note has songs
                        if !localWorshipSongs.isEmpty {
                            SavedWorshipSongsSection(
                                songs: localWorshipSongs,
                                noteId: note.id,
                                onRemove: { song in
                                    localWorshipSongs.removeAll { $0.id == song.id }
                                    Task {
                                        try? await notesService.updateWorshipSongs(localWorshipSongs, for: note)
                                    }
                                }
                            )
                        }

                        // Live "Now Playing" card — only shown while a song for this note is active
                        NoteWorshipSection(noteId: note.id)
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { localWorshipSongs = note.worshipSongs }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await notesService.deleteNote(note)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .shareOptions:
                ChurchNoteShareOptionsSheet(note: note)
            case .shareToOpenTable:
                ShareNoteToOpenTableSheet(note: note)
            case .shareWithFriends:
                ShareWithFriendsSheet(note: note, notesService: notesService)
            }
        }
        .overlay(alignment: .bottom) {
            // Toast notification for copy confirmation
            if showCopiedToast {
                Text("Link copied to clipboard")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                    )
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func defaultPrayerFocusTextLocal(from note: ChurchNote) -> String {
        if let scripture = note.scripture, !scripture.isEmpty {
            return "Pray through \(scripture)"
        }
        let trimmed = note.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if let sentenceEnd = trimmed.firstIndex(of: ".") {
            return String(trimmed[..<sentenceEnd]).prefix(120) + "…"
        }
        return String(trimmed.prefix(120))
    }

    private var prayerFocusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                let focusText = defaultPrayerFocusTextLocal(from: note)
                PrayerFocusStore.shared.saveFocus(text: focusText, noteId: note.id)
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                withAnimation(.easeOut(duration: 0.25)) {
                    showPrayerSaved = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showPrayerSaved = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hands.sparkles")
                        .font(.systemScaled(14, weight: .semibold))
                    Text("Save to this week’s prayer focus")
                        .font(.systemScaled(14, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
                )
            }
            .buttonStyle(.plain)

            if showPrayerSaved {
                Text("Saved to prayer focus")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
    }

    private func defaultPrayerFocusText(from note: ChurchNote) -> String {
        if let scripture = note.scripture, !scripture.isEmpty {
            return "Pray through \(scripture)"
        }
        if !note.keyPoints.isEmpty {
            return note.keyPoints[0]
        }
        let trimmedContent = note.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            if let firstLine = trimmedContent.split(separator: "\n").first {
                return String(firstLine)
            }
            return trimmedContent
        }
        return note.title
    }

    private func generateShareText() -> String {
        var text = "📝 \(note.title)\n\n"
        
        if let sermon = note.sermonTitle {
            text += "🎤 Sermon: \(sermon)\n"
        }
        
        if let church = note.churchName {
            text += "⛪ Church: \(church)\n"
        }
        
        if let pastor = note.pastor {
            text += "👤 Pastor: \(pastor)\n"
        }
        
        if let scripture = note.scripture {
            text += "📖 Scripture: \(scripture)\n"
        }
        
        text += "\n\(note.content)\n"
        
        if !note.tags.isEmpty {
            text += "\n🏷️ " + note.tags.map { "#\($0)" }.joined(separator: " ")
        }
        
        return text
    }
    
    // MARK: - Copy Note Share Link
    
    private func copyNoteShareLink() {
        guard let linkId = note.shareLinkId else {
            dlog("❌ Note has no share link ID")
            return
        }
        
        // Create shareable deep link
        let shareURL = "amenapp://note/\(linkId)"
        UIPasteboard.general.string = shareURL
        
        // Show toast confirmation with animation
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
            showCopiedToast = true
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        dlog("✅ Note link copied: \(shareURL)")
        
        // Hide toast after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCopiedToast = false
                }
            }
        }
    }
    
    // MARK: - Share to OpenTable
    
    private func shareToOpenTable() {
        activeSheet = .shareToOpenTable
    }
}

// MARK: - Metadata Pill

struct MetadataPill: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(14))
            Text(text)
                .font(AMENFont.semiBold(14))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .amenGlassEffect(in: Capsule())
    }
}

// MARK: - Share Sheet
// Note: ShareSheet is defined in ShareSheet.swift and reused here

// MARK: - Threads-Style Monochrome Components

// MARK: - Utility Types
// SpringButtonStyle is defined earlier in the file
// ScrollOffsetPreferenceKey is defined earlier in the file

// MARK: - Threads-Style Header
struct ThreadsStyleHeader: View {
    @Binding var searchText: String
    let isScrolled: Bool
    let onNewNote: () -> Void
    @State private var isSearchFocused = false
    @State private var glowPulse = false
    
    var body: some View {
        VStack(spacing: isScrolled ? 12 : 20) {
            // Title and Add Button
            HStack {
                Text("Notes")
                    .font(.systemScaled(isScrolled ? 28 : 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Glassmorphic Plus Button
                Button(action: onNewNote) {
                    ZStack {
                        // Frosted glass capsule
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .frame(width: 100, height: 44)
                        
                        // Subtle white overlay
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.6),
                                        Color.white.opacity(0.4)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 44)
                        
                        // Blue accent bar (left side)
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.blue,
                                            Color.blue.opacity(0.85)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 50, height: 40)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.systemScaled(18, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                            
                            Spacer()
                        }
                        .frame(width: 100, height: 44)
                        .clipShape(Capsule())
                        
                        // Subtle border
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.1),
                                        Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                            .frame(width: 100, height: 44)
                    }
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    .shadow(color: .blue.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(SpringButtonStyle())
            }
            .padding(.horizontal, 20)
            
            // Glassmorphic Search Bar
            if !isScrolled {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.systemScaled(16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.6))
                    
                    TextField("", text: $searchText, prompt: Text("Search notes...").foregroundStyle(.black.opacity(0.4)))
                        .font(.systemScaled(16, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                        .tint(.blue)
                        .onTapGesture {
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                isSearchFocused = true
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                isSearchFocused = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.black.opacity(0.4))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                        
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSearchFocused ? 0.8 : 0.6),
                                        Color.white.opacity(isSearchFocused ? 0.7 : 0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: isSearchFocused ? [
                                        Color.blue.opacity(0.5),
                                        Color.blue.opacity(0.3)
                                    ] : [
                                        Color.black.opacity(0.15),
                                        Color.black.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSearchFocused ? 2 : 1.5
                            )
                    }
                )
                .shadow(color: isSearchFocused ? .blue.opacity(0.2) : .black.opacity(0.1), radius: isSearchFocused ? 16 : 10, y: 5)
                .scaleEffect(isSearchFocused ? 1.02 : 1.0)
                .padding(.horizontal, 20)
                .transition(.opacity)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSearchFocused)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.95),
                    Color.white.opacity(0.8),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isScrolled)
    }
}

// MARK: - Monochrome Filter Pill
struct MonochromeFilterPill: View {
    let filter: ChurchNotesView.FilterOption
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var accentColor: Color {
        switch filter {
        case .all: return .blue
        case .favorites: return .orange
        case .recent: return .cyan
        case .forYou: return .pink
        case .following: return .green
        case .sharedWithMe: return .indigo
        case .community: return .purple
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.systemScaled(13, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(.systemScaled(14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : .black.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    Capsule()
                        .fill(.ultraThinMaterial)
                    
                    if isSelected {
                        // Selected: colored background
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor,
                                        accentColor.opacity(0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        // Unselected: white glass
                        Capsule()
                            .fill(Color.white.opacity(0.7))
                    }
                    
                    Capsule()
                        .strokeBorder(
                            isSelected ? 
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.15),
                                        Color.black.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                }
            )
            .shadow(color: isSelected ? accentColor.opacity(0.3) : .black.opacity(0.1), radius: isSelected ? 12 : 8, y: isSelected ? 4 : 2)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(SpringButtonStyle())
    }
}

// MARK: - Threads-Style Notes List
struct ThreadsStyleNotesList: View {
    let notes: [ChurchNote]
    @ObservedObject var notesService: ChurchNotesService
    @Binding var scrollOffset: CGFloat
    let onNoteSelected: (ChurchNote) -> Void
    
    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scroll")).minY
                )
            }
            .frame(height: 0)
            
            LazyVStack(spacing: 0) {
                ForEach(notes) { note in
                    ThreadsStyleNoteCard(
                        note: note,
                        notesService: notesService,
                        onTap: { onNoteSelected(note) }
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
    }
}

// MARK: - Threads-Style Note Card
struct ThreadsStyleNoteCard: View {
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    let onTap: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.7))) {
                    isPressed = false
                }
                onTap()
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Content
                VStack(alignment: .leading, spacing: 12) {
                    // Title
                    Text(note.title)
                        .font(.systemScaled(20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Sermon title if available
                    if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "quote.bubble")
                                .font(.systemScaled(12))
                            Text(sermonTitle)
                                .font(.systemScaled(14, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.black.opacity(0.6))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Content preview
                    if !note.content.isEmpty {
                        Text(note.content)
                            .font(.systemScaled(15, weight: .regular, design: .rounded))
                            .foregroundStyle(.black.opacity(0.7))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Metadata row
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.systemScaled(11))
                            Text(note.date, style: .date)
                                .font(.systemScaled(12, weight: .medium, design: .rounded))
                        }
                        
                        if let churchName = note.churchName, !churchName.isEmpty {
                            Text("•")
                            Text(churchName)
                                .font(.systemScaled(12, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Favorite button
                        Button {
                            Task {
                                try? await notesService.toggleFavorite(note)
                                let haptic = UINotificationFeedbackGenerator()
                                haptic.notificationOccurred(note.isFavorite ? .success : .warning)
                            }
                        } label: {
                            Image(systemName: note.isFavorite ? "star.fill" : "star")
                                .font(.systemScaled(16))
                                .foregroundStyle(note.isFavorite ? .orange : .black.opacity(0.4))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .foregroundStyle(.black.opacity(0.5))
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.9),
                                            Color.white.opacity(0.8)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.12),
                                            Color.black.opacity(0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
                .shadow(color: .black.opacity(0.04), radius: 20, y: 10)
                .scaleEffect(isPressed ? 0.98 : 1.0)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .contextMenu {
            Button {
                Task {
                    try? await notesService.toggleFavorite(note)
                }
            } label: {
                Label(note.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: note.isFavorite ? "star.slash" : "star.fill")
            }
            
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await notesService.deleteNote(note)
                }
            }
        }
    }
}

// MARK: - Monochrome Loading View
struct MonochromeLoadingView: View {
    @State private var isAnimating = false
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                        .frame(width: 60 - CGFloat(index * 15), height: 60 - CGFloat(index * 15))
                        .scaleEffect(isAnimating ? 1.3 : 0.7)
                        .opacity(isAnimating ? 0 : 0.8)
                        .animation(
                            .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
                
                Image(systemName: "note.text")
                    .font(.systemScaled(24, weight: .semibold))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 80, height: 80)
            
            Text("Loading Notes...")
                .font(.systemScaled(16, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = true
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Monochrome Empty State
struct MonochromeEmptyState: View {
    let hasSearch: Bool
    let filterType: ChurchNotesView.FilterOption
    let onCreateNote: () -> Void
    @State private var bounce = false
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                    .scaleEffect(bounce ? 1.1 : 1.0)
                
                Image(systemName: hasSearch ? "magnifyingglass" : "note.text")
                    .font(.systemScaled(48, weight: .light))
                    .foregroundStyle(.blue.opacity(0.6))
            }
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: bounce)
            
            VStack(spacing: 12) {
                Text(emptyTitle)
                    .font(.systemScaled(24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(emptySubtitle)
                    .font(.systemScaled(15, weight: .regular, design: .rounded))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if !hasSearch && filterType == .all {
                Button(action: onCreateNote) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.systemScaled(18))
                        Text("Create Note")
                            .font(.systemScaled(16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.blue.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 12, y: 6)
                }
                .buttonStyle(SpringButtonStyle())
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            bounce = true
        }
    }
    
    var emptyTitle: String {
        if hasSearch { return "No Results" }
        switch filterType {
        case .all: return "No Notes Yet"
        case .favorites: return "No Favorites"
        case .recent: return "No Recent Notes"
        case .forYou: return "No Recommendations"
        case .following: return "No Notes from Following"
        case .sharedWithMe: return "No Shared Notes"
        case .community: return "No Community Notes"
        }
    }
    
    var emptySubtitle: String {
        if hasSearch { return "Try different keywords" }
        switch filterType {
        case .all: return "Start capturing your sermon insights"
        case .favorites: return "Star notes to save them here"
        case .recent: return "Notes from the last 7 days appear here"
        case .forYou: return "Your personalized feed will appear here"
        case .following: return "Notes from people you follow appear here"
        case .sharedWithMe: return "Shared notes appear here"
        case .community: return "Community notes appear here"
        }
    }
}

// MARK: - Monochrome New Note View
struct MonochromeNewNoteView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var title = ""
    @State private var sermonTitle = ""
    @State private var churchName = ""
    @State private var pastor = ""
    @State private var selectedDate = Date()
    @State private var content = ""
    @State private var scripture = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var wordCount = 0
    @FocusState private var focusedField: Field?
    
    enum Field {
        case title, sermonTitle, churchName, pastor, scripture, content, tag
    }
    
    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
    var body: some View {
        ZStack {
            // Clean white background with subtle gradient
            LinearGradient(
                colors: [
                    Color.white,
                    Color(white: 0.98),
                    Color(white: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Enhanced Header with glassmorphic Save button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.systemScaled(17, weight: .medium, design: .rounded))
                            .foregroundStyle(.black.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Writer stats in center
                    VStack(spacing: 2) {
                        Text("New Note")
                            .font(.systemScaled(17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        if wordCount > 0 {
                            Text("\(wordCount) words")
                                .font(.systemScaled(11, weight: .medium, design: .rounded))
                                .foregroundStyle(.black.opacity(0.5))
                        }
                    }
                    
                    Spacer()
                    
                    // Glassmorphic Save Button
                    Button {
                        saveNote()
                    } label: {
                        ZStack {
                            // Frosted glass capsule
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .frame(width: 80, height: 36)
                            
                            // White overlay
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.6),
                                            Color.white.opacity(0.4)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 36)
                            
                            // Blue accent (left half) when enabled
                            if canSave {
                                HStack(spacing: 0) {
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.blue,
                                                    Color.blue.opacity(0.85)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: 40, height: 32)
                                    
                                    Spacer()
                                }
                                .frame(width: 80, height: 36)
                                .clipShape(Capsule())
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            // Text
                            Text(isSaving ? "Saving..." : "Save")
                                .font(.systemScaled(15, weight: .semibold, design: .rounded))
                                .foregroundStyle(canSave ? .white : .black.opacity(0.4))
                            
                            // Border
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: canSave ? [
                                            Color.blue.opacity(0.4),
                                            Color.blue.opacity(0.2)
                                        ] : [
                                            Color.black.opacity(0.12),
                                            Color.black.opacity(0.06)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                                .frame(width: 80, height: 36)
                        }
                        .shadow(color: canSave ? .blue.opacity(0.25) : .black.opacity(0.08), radius: 8, y: 4)
                    }
                    .disabled(!canSave || isSaving)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSave)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.8),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                )
                
                Divider()
                    .background(Color.black.opacity(0.1))
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Empowering Title Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("✨ Your Story Matters")
                                .font(.systemScaled(13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue.opacity(0.8))
                                .padding(.horizontal, 4)
                            
                            TextField("", text: $title, prompt: Text("Give your note a powerful title...").foregroundStyle(.black.opacity(0.4)))
                                .font(.systemScaled(28, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .tint(.blue)
                                .focused($focusedField, equals: .title)
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(focusedField == .title ? 0.9 : 0.7),
                                                            Color.white.opacity(focusedField == .title ? 0.85 : 0.6)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: focusedField == .title ? [
                                                            Color.blue.opacity(0.5),
                                                            Color.blue.opacity(0.3)
                                                        ] : [
                                                            Color.black.opacity(0.12),
                                                            Color.black.opacity(0.06)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: focusedField == .title ? 2 : 1.5
                                                )
                                        )
                                )
                                .shadow(color: focusedField == .title ? .blue.opacity(0.2) : .black.opacity(0.08), radius: 12, y: 6)
                        }
                        
                        // Sermon Context Section (Collapsible)
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Sermon Context", systemImage: "quote.bubble")
                                    .font(.systemScaled(15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                
                                Spacer()
                                
                                Text("Optional")
                                    .font(.systemScaled(12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.1))
                                    )
                            }
                            
                            VStack(spacing: 12) {
                                EnhancedTextField(
                                    icon: "mic",
                                    placeholder: "Sermon title",
                                    text: $sermonTitle,
                                    focusedField: $focusedField,
                                    field: .sermonTitle
                                )
                                
                                HStack(spacing: 12) {
                                    EnhancedTextField(
                                        icon: "building.2",
                                        placeholder: "Church",
                                        text: $churchName,
                                        focusedField: $focusedField,
                                        field: .churchName
                                    )
                                    
                                    EnhancedTextField(
                                        icon: "person",
                                        placeholder: "Pastor",
                                        text: $pastor,
                                        focusedField: $focusedField,
                                        field: .pastor
                                    )
                                }
                                
                                // Date Picker
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar")
                                        .font(.systemScaled(16, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .frame(width: 24)
                                    
                                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(.blue)
                                        .colorScheme(.dark)
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.12),
                                                            Color.white.opacity(0.06)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.3),
                                                            Color.white.opacity(0.15)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.5
                                                )
                                        )
                                )
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.08),
                                                    Color.white.opacity(0.04)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.2),
                                                    Color.white.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        
                        // Scripture Reference
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Scripture Reference", systemImage: "book.closed")
                                .font(.systemScaled(13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.purple.opacity(0.9))
                                .padding(.horizontal, 4)
                            
                            EnhancedTextField(
                                icon: "book",
                                placeholder: "e.g., John 3:16 or Psalm 23",
                                text: $scripture,
                                focusedField: $focusedField,
                                field: .scripture,
                                tintColor: .purple
                            )
                        }
                        
                        // Main Content Editor - Writer-Focused
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Your Notes", systemImage: "pencil.line")
                                    .font(.systemScaled(15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                
                                Spacer()
                                
                                if !content.isEmpty {
                                    Text("\(wordCount) words")
                                        .font(.systemScaled(12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.blue.opacity(0.8))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(Color.blue.opacity(0.15))
                                        )
                                }
                            }
                            
                            ZStack(alignment: .topLeading) {
                                if content.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Write your thoughts, insights, and reflections...")
                                            .font(.systemScaled(17, weight: .regular, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.4))
                                        
                                        Text("💡 Tip: Don't worry about perfection—just write!")
                                            .font(.systemScaled(14, weight: .medium, design: .rounded))
                                            .foregroundStyle(.blue.opacity(0.5))
                                    }
                                    .padding(20)
                                }
                                
                                TextEditor(text: $content)
                                    .font(.systemScaled(17, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .frame(minHeight: 280)
                                    .padding(16)
                                    .focused($focusedField, equals: .content)
                                    .onChange(of: content) { oldValue, newValue in
                                        wordCount = newValue.split(separator: " ").count
                                    }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color.white.opacity(focusedField == .content ? 0.15 : 0.12),
                                                        Color.white.opacity(focusedField == .content ? 0.10 : 0.06)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .strokeBorder(
                                                LinearGradient(
                                                    colors: focusedField == .content ? [
                                                        Color.blue.opacity(0.6),
                                                        Color.blue.opacity(0.3)
                                                    ] : [
                                                        Color.white.opacity(0.3),
                                                        Color.white.opacity(0.15)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: focusedField == .content ? 2 : 1.5
                                            )
                                    )
                            )
                            .shadow(color: focusedField == .content ? .blue.opacity(0.3) : .black.opacity(0.2), radius: 12, y: 6)
                        }
                        
                        // Quick Save Reminder
                        if !title.isEmpty && !content.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.systemScaled(16))
                                    .foregroundStyle(.green)
                                
                                Text("Ready to save! Your note looks great.")
                                    .font(.systemScaled(14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.8))
                                
                                Spacer()
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.green.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func saveNote() {
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            errorMessage = "You must be signed in to create notes."
            showErrorAlert = true
            return
        }
        
        guard canSave else { return }
        
        isSaving = true
        
        let note = ChurchNote(
            userId: userId,
            title: title,
            sermonTitle: sermonTitle.isEmpty ? nil : sermonTitle,
            churchName: churchName.isEmpty ? nil : churchName,
            pastor: pastor.isEmpty ? nil : pastor,
            date: selectedDate,
            content: content,
            scripture: scripture.isEmpty ? nil : scripture,
            keyPoints: [],
            tags: tags
        )
        
        Task {
            do {
                try await notesService.createNote(note)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save note. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Monochrome Text Field
struct MonochromeTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24)
            
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.5)))
                .font(.systemScaled(16, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .tint(.white)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Monochrome Note Detail View
struct MonochromeNoteDetailView: View {
    @Environment(\.dismiss) var dismiss
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            // Clean black background
            LinearGradient(
                colors: [
                    Color.black,
                    Color(white: 0.05),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with translucent background
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .fill(Color.white.opacity(0.15))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                                    )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    }
                    
                    Spacer()
                    
                    Button {
                        Task {
                            try? await notesService.toggleFavorite(note)
                            let haptic = UIImpactFeedbackGenerator(style: .medium)
                            haptic.impactOccurred()
                        }
                    } label: {
                        Image(systemName: note.isFavorite ? "star.fill" : "star")
                            .font(.systemScaled(20))
                            .foregroundStyle(note.isFavorite ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .fill(Color.white.opacity(0.15))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                                    )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    }
                    
                    Menu {
                        ShareLink(
                            item: "\(note.title)\n\(note.sermonTitle ?? note.content)",
                            subject: Text(note.title)
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.systemScaled(20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .fill(Color.white.opacity(0.15))
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                                    )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.3),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                )
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title
                        Text(note.title)
                            .font(.systemScaled(32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        
                        // Metadata
                        VStack(alignment: .leading, spacing: 12) {
                            if let sermonTitle = note.sermonTitle {
                                MetadataRow(icon: "mic", text: sermonTitle)
                            }
                            if let churchName = note.churchName {
                                MetadataRow(icon: "building.2", text: churchName)
                            }
                            if let pastor = note.pastor {
                                MetadataRow(icon: "person", text: pastor)
                            }
                            if let scripture = note.scripture {
                                MetadataRow(icon: "book", text: scripture)
                            }
                            MetadataRow(icon: "calendar", text: note.date.formatted(date: .long, time: .omitted))
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.3))
                        
                        // Content
                        Text(note.content)
                            .font(.systemScaled(17, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineSpacing(6)
                    }
                    .padding(20)
                }
            }
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await notesService.deleteNote(note)
                    dismiss()
                }
            }
        }
    }
}

struct MetadataRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            
            Text(text)
                .font(.systemScaled(15, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Enhanced Text Field (Writer-Focused)
struct EnhancedTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var focusedField: FocusState<MonochromeNewNoteView.Field?>.Binding
    let field: MonochromeNewNoteView.Field
    var tintColor: Color = .blue
    
    private var isFocused: Bool {
        focusedField.wrappedValue == field
    }
    
    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isFocused ? 0.9 : 0.7),
                Color.white.opacity(isFocused ? 0.85 : 0.6)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var strokeGradient: LinearGradient {
        if isFocused {
            return LinearGradient(
                colors: [
                    tintColor.opacity(0.5),
                    tintColor.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(.black.opacity(0.6))
                .frame(width: 24)
            
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.black.opacity(0.4)))
                .font(.systemScaled(16, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .tint(tintColor)
                .focused(focusedField, equals: field)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(fillGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(strokeGradient, lineWidth: isFocused ? 2 : 1.5)
                )
        )
        .shadow(color: isFocused ? tintColor.opacity(0.2) : .black.opacity(0.08), radius: 8, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
    }
}

// MARK: - Share Note to OpenTable Sheet

struct ShareNoteToOpenTableSheet: View {
    @Environment(\.dismiss) var dismiss
    let note: ChurchNote
    
    @State private var postContent = ""
    @State private var isPosting = false
    @State private var showSuccessMessage = false
    @ObservedObject private var postsManager = PostsManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.systemScaled(17, weight: .regular))
                    .foregroundStyle(.black.opacity(0.6))
                    
                    Spacer()
                    
                    Text("Share to #OPENTABLE")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Button {
                        shareToOpenTable()
                    } label: {
                        if isPosting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Post")
                                .font(.systemScaled(17, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .disabled(postContent.isEmpty || isPosting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.thinMaterial)

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Text editor for post content
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Thoughts")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(1)
                            
                            TextEditor(text: $postContent)
                                .font(.systemScaled(17, weight: .regular))
                                .foregroundStyle(.primary)
                                .frame(minHeight: 120)
                                .padding(12)
                                .scrollContentBackground(.hidden)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.thinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.68)))
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                                )
                        }
                        
                        // Note Preview
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Note Preview")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(1)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                // Title
                                Text(note.title)
                                    .font(.systemScaled(20, weight: .bold))
                                    .foregroundStyle(.primary)
                                
                                // Sermon info
                                if let sermon = note.sermonTitle {
                                    HStack(spacing: 6) {
                                        Image(systemName: "mic.fill")
                                            .font(.systemScaled(12))
                                        Text(sermon)
                                            .font(.systemScaled(14))
                                    }
                                    .foregroundStyle(.black.opacity(0.6))
                                }
                                
                                // Scripture
                                if let scripture = note.scripture {
                                    HStack(spacing: 6) {
                                        Image(systemName: "book.fill")
                                            .font(.systemScaled(12))
                                        Text(scripture)
                                            .font(.systemScaled(14, weight: .medium))
                                    }
                                    .foregroundStyle(.purple)
                                }
                                
                                // Content preview
                                Text(note.content)
                                    .font(.systemScaled(15))
                                    .foregroundStyle(.black.opacity(0.8))
                                    .lineLimit(4)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.thinMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.65)))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                            )
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                        }
                    }
                    .padding(20)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .alert("Posted to #OPENTABLE", isPresented: $showSuccessMessage) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your church note has been shared to #OPENTABLE!")
        }
        .onAppear {
            // Pre-populate with note title
            postContent = "📝 Church Notes: \(note.title)"
        }
    }
    
    private func shareToOpenTable() {
        guard !postContent.isEmpty else { return }
        
        isPosting = true
        
        Task {
            do {
                // Generate post content
                var fullContent = postContent + "\n\n"
                
                if let sermon = note.sermonTitle {
                    fullContent += "🎤 Sermon: \(sermon)\n"
                }
                
                if let scripture = note.scripture {
                    fullContent += "📖 Scripture: \(scripture)\n"
                }
                
                fullContent += "\n" + note.content
                
                // Post to Firebase — pass churchNoteId to bypass AI detection
                // (church note content is the user's own sermon notes, not AI-generated).
                try await FirebasePostService.shared.createPost(
                    content: fullContent,
                    category: .openTable,
                    topicTag: note.sermonTitle,
                    churchNoteId: note.id
                )
                
                // Write a share event for Cloud Function fanout to followers/church members
                if let sharerId = Auth.auth().currentUser?.uid {
                    lazy var db = Firestore.firestore()
                    do {
                        try await db.collection("churchNoteShareEvents").addDocument(data: [
                            "noteId": note.id ?? "",
                            "noteTitle": note.title,
                            "sharerId": sharerId,
                            "churchName": note.churchName ?? "",
                            "sharedAt": FieldValue.serverTimestamp()
                        ])
                    } catch {
                        print("ChurchNotesView: failed to write share event — \(error.localizedDescription)")
                    }
                }
                
                await MainActor.run {
                    isPosting = false
                    showSuccessMessage = true
                }
            } catch {
                dlog("❌ Failed to share to OpenTable: \(error)")
                await MainActor.run {
                    isPosting = false
                }
            }
        }
    }
}

// MARK: - Elegant Community Church Notes Feed (for ChurchNotesView)

struct ElegantChurchNotesFeedForChurchNotesView: View {
    let posts: [Post]
    @State private var selectedPost: Post?
    @State private var selectedChurchNote: ChurchNote?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Elegant header
                VStack(spacing: 20) {
                    Text("SHARED NOTES")
                        .font(.systemScaled(11, weight: .semibold, design: .default))
                        .tracking(2.5)
                        .foregroundStyle(Color.black.opacity(0.5))
                        .padding(.top, 32)
                    
                    Text("Community\nChurch Notes")
                        .font(.custom("Georgia", size: 40))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .foregroundStyle(Color.black.opacity(0.9))
                        .padding(.horizontal, 32)
                    
                    Text("Discover sermon insights, biblical teachings, and spiritual reflections shared by believers in our community.")
                        .font(.systemScaled(15, weight: .regular, design: .default))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .foregroundStyle(Color.black.opacity(0.55))
                        .padding(.horizontal, 32)
                        .padding(.top, 4)
                }
                .padding(.bottom, 36)
                
                // Church notes list
                if posts.isEmpty {
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.02))
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "book.closed")
                                .font(.systemScaled(48, weight: .light))
                                .foregroundStyle(Color.black.opacity(0.25))
                        }
                        .padding(.top, 80)
                        
                        VStack(spacing: 8) {
                            Text("No Shared Notes Yet")
                                .font(.systemScaled(22, weight: .medium, design: .default))
                                .foregroundStyle(Color.black.opacity(0.7))
                            
                            Text("Be the first to share your sermon notes\nwith the community")
                                .font(.systemScaled(15, weight: .regular, design: .default))
                                .foregroundStyle(Color.black.opacity(0.45))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 100)
                } else {
                    LazyVStack(spacing: 24) {
                        ForEach(posts, id: \.firestoreId) { post in
                            ElegantChurchNoteCardForChurchNotesView(post: post)
                                .onTapGesture {
                                    selectedPost = post
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.95),
                    Color(red: 0.96, green: 0.95, blue: 0.93)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .task {
            // Load church note when a post is selected
            if let post = selectedPost, let churchNoteId = post.churchNoteId {
                await loadChurchNote(churchNoteId: churchNoteId)
            }
        }
        .onChange(of: selectedPost) { _, newValue in
            if let post = newValue, let churchNoteId = post.churchNoteId {
                Task {
                    await loadChurchNote(churchNoteId: churchNoteId)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedChurchNote != nil },
            set: { if !$0 { selectedChurchNote = nil; selectedPost = nil } }
        )) {
            if let note = selectedChurchNote, let post = selectedPost {
                ElegantChurchNoteReadView(churchNote: note, post: post)
            }
        }
    }
    
    private func loadChurchNote(churchNoteId: String) async {
        do {
            let db = FirebaseManager.shared.firestore
            let document = try await db.collection("churchNotes").document(churchNoteId).getDocument()
            
            if document.exists {
                selectedChurchNote = try? document.data(as: ChurchNote.self)
            }
        } catch {
            dlog("Error loading church note: \(error)")
        }
    }
}

// MARK: - Elegant Church Note Card (for ChurchNotesView)

struct ElegantChurchNoteCardForChurchNotesView: View {
    let post: Post
    @State private var churchNote: ChurchNote?
    @State private var isLoading = true
    
    var body: some View {
        // Compact Liquid Glass Pill Card
        HStack(spacing: 12) {
            // Note icon with Liquid Glass background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.06),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: "note.text")
                    .font(.systemScaled(16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
            }
            
            // Compact content
            VStack(alignment: .leading, spacing: 3) {
                if let note = churchNote {
                    Text(note.title)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.black.opacity(0.85))
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(post.authorName)
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.black.opacity(0.5))
                        
                        if let churchName = note.churchName, !churchName.isEmpty {
                            Text("•")
                                .font(.systemScaled(11, weight: .medium))
                                .foregroundStyle(.black.opacity(0.3))
                            
                            Text(churchName)
                                .font(AMENFont.regular(13))
                                .foregroundStyle(.black.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                } else if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Loading note...")
                            .font(AMENFont.regular(13))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.25))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Liquid Glass base
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.95))
                
                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.08),
                            .black.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
        .task {
            await loadChurchNote()
        }
    }
    
    private func loadChurchNote() async {
        guard let churchNoteId = post.churchNoteId else {
            isLoading = false
            return
        }
        
        do {
            let db = FirebaseManager.shared.firestore
            let document = try await db.collection("churchNotes").document(churchNoteId).getDocument()
            
            if document.exists {
                churchNote = try? document.data(as: ChurchNote.self)
            }
            isLoading = false
        } catch {
            dlog("Error loading church note: \(error)")
            isLoading = false
        }
    }
}

// MARK: - Elegant Church Note Read View

struct ElegantChurchNoteReadView: View {
    let churchNote: ChurchNote
    let post: Post
    @Environment(\.dismiss) var dismiss
    @State private var showShareSheet = false
    @State private var showCommentsSheet = false
    @State private var hasAmenned = false
    @State private var amenCount = 0
    @State private var commentCount = 0
    @ObservedObject private var interactionsService = PostInteractionsService.shared
    
    var body: some View {
        ZStack {
            // Background gradient matching the feed
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.97, blue: 0.95),
                    Color(red: 0.96, green: 0.95, blue: 0.93)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with close button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(17, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.6))
                            .frame(width: 32, height: 32)
                    }
                    
                    Spacer()
                    
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(17, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.6))
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.98, green: 0.97, blue: 0.95).opacity(0.95))
                
                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        // Author info
                        HStack(spacing: 12) {
                            if let profileImageURL = post.authorProfileImageURL, !profileImageURL.isEmpty {
                                CachedAsyncImage(url: URL(string: profileImageURL)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(Color.black.opacity(0.08))
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Text(post.authorInitials)
                                            .font(.systemScaled(15, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.6))
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.authorName)
                                    .font(.systemScaled(15, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.85))
                                
                                Text("Shared \(post.timeAgo)")
                                    .font(.systemScaled(13, weight: .regular))
                                    .foregroundStyle(Color.black.opacity(0.45))
                            }
                        }
                        .padding(.top, 24)
                        
                        // Title
                        Text(churchNote.title)
                            .font(.custom("Georgia", size: 36))
                            .foregroundStyle(Color.black.opacity(0.9))
                            .lineSpacing(4)
                        
                        // Metadata section
                        VStack(alignment: .leading, spacing: 12) {
                            if let sermonTitle = churchNote.sermonTitle, !sermonTitle.isEmpty {
                                ElegantMetadataRow(icon: "mic.fill", label: "Sermon", value: sermonTitle)
                            }
                            
                            if let churchName = churchNote.churchName, !churchName.isEmpty {
                                ElegantMetadataRow(icon: "building.2.fill", label: "Church", value: churchName)
                            }
                            
                            if let pastor = churchNote.pastor, !pastor.isEmpty {
                                ElegantMetadataRow(icon: "person.fill", label: "Pastor", value: pastor)
                            }
                            
                            if let scripture = churchNote.scripture, !scripture.isEmpty {
                                ElegantMetadataRow(icon: "book.fill", label: "Scripture", value: scripture)
                            }
                            
                            ElegantMetadataRow(
                                icon: "calendar",
                                label: "Date",
                                value: churchNote.date.formatted(date: .long, time: .omitted)
                            )
                        }
                        .padding(20)
                        .background(Color.white.opacity(0.5))
                        .cornerRadius(12)
                        
                        // Divider
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 1)
                            .padding(.vertical, 8)
                        
                        // Content
                        Text(churchNote.content)
                            .font(.systemScaled(17, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.8))
                            .lineSpacing(8)
                        
                        // Tags if available
                        if !churchNote.tags.isEmpty {
                            AMENFlowLayout(spacing: 8) {
                                ForEach(churchNote.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.systemScaled(14, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.5))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.04))
                                        .cornerRadius(6)
                                }
                            }
                        }

                        // Worship Music — read-only (no remove button for other users' notes)
                        if !churchNote.worshipSongs.isEmpty {
                            ElegantWorshipSongsSection(
                                songs: churchNote.worshipSongs,
                                noteId: churchNote.id
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                
                // AMEN + Comment Interaction Toolbar
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.black.opacity(0.08))
                    
                    HStack(spacing: 20) {
                        // AMEN Button
                        Button {
                            toggleAmen()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: hasAmenned ? "hands.clap.fill" : "hands.clap")
                                    .font(.systemScaled(16, weight: .semibold))
                                    .foregroundStyle(hasAmenned ? .orange : .black.opacity(0.6))
                                
                                Text("AMEN")
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(hasAmenned ? .orange : .black.opacity(0.6))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(hasAmenned ? Color.orange.opacity(0.12) : Color.black.opacity(0.04))
                            )
                        }
                        
                        // Comment Button
                        Button {
                            showCommentsSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: commentCount > 0 ? "bubble.left.fill" : "bubble.left")
                                    .font(.systemScaled(16, weight: .semibold))
                                    .foregroundStyle(commentCount > 0 ? .blue : .black.opacity(0.6))
                                
                                Text("Comment")
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(commentCount > 0 ? .blue : .black.opacity(0.6))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(commentCount > 0 ? Color.blue.opacity(0.12) : Color.black.opacity(0.04))
                            )
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.98, green: 0.97, blue: 0.95).opacity(0.98))
                }
            }
        }
        .task {
            await loadInteractions()
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareText = generateShareText() {
                ShareSheet(items: [shareText])
            }
        }
        .sheet(isPresented: $showCommentsSheet) {
            CommentsView(post: post)
        }
    }
    
    private func generateShareText() -> String? {
        var text = "📖 \(churchNote.title)\n\n"
        
        if let sermon = churchNote.sermonTitle, !sermon.isEmpty {
            text += "Sermon: \(sermon)\n"
        }
        if let church = churchNote.churchName, !church.isEmpty {
            text += "Church: \(church)\n"
        }
        if let pastor = churchNote.pastor, !pastor.isEmpty {
            text += "Pastor: \(pastor)\n"
        }
        if let scripture = churchNote.scripture, !scripture.isEmpty {
            text += "Scripture: \(scripture)\n"
        }
        
        text += "\n\(churchNote.content)\n"
        
        if !churchNote.tags.isEmpty {
            text += "\n" + churchNote.tags.map { "#\($0)" }.joined(separator: " ")
        }
        
        text += "\n\nShared by \(post.authorName) on AMEN"
        
        return text
    }
    
    // MARK: - Load Interactions
    
    private func loadInteractions() async {
        let postId = post.firestoreId
        
        // Check if user has amenned using published property
        await MainActor.run {
            hasAmenned = interactionsService.userAmenedPosts.contains(postId)
        }
        
        // Get interaction counts
        let counts = await interactionsService.getInteractionCounts(postId: postId)
        await MainActor.run {
            amenCount = counts.amenCount
            commentCount = counts.commentCount
        }
    }
    
    // MARK: - Toggle AMEN
    
    private func toggleAmen() {
        let postId = post.firestoreId
        
        // Optimistic update
        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
            hasAmenned.toggle()
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        // Update backend
        Task {
            do {
                try await interactionsService.toggleAmen(postId: postId)
            } catch {
                // Revert on error
                await MainActor.run {
                    withAnimation {
                        hasAmenned.toggle()
                    }
                }
            }
        }
    }
}

// MARK: - Metadata Row Component for Elegant Read View

// MARK: - ElegantWorshipSongsSection
// Read-only worship songs section shown in ElegantChurchNoteReadView (other users' notes).
// Matches the light beige aesthetic of that view — no remove button.
struct ElegantWorshipSongsSection: View {
    let songs: [WorshipSongReference]
    let noteId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.systemScaled(10, weight: .medium))
                Text("WORSHIP")
                    .font(.systemScaled(10, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.black.opacity(0.35))

            VStack(spacing: 6) {
                ForEach(songs) { song in
                    ElegantWorshipSongRow(song: song, noteId: noteId)
                }
            }
        }
    }
}

private struct ElegantWorshipSongRow: View {
    let song: WorshipSongReference
    let noteId: String?

    @Environment(\.openURL) private var openURL
    @State private var showUnavailableAlert = false

    var body: some View {
        HStack(spacing: 10) {
            artworkView

            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.systemScaled(11))
                    .foregroundStyle(Color.black.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button { handlePlayTap() } label: {
                Image(systemName: trailingIcon)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.62))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.black.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
        )
        .alert("Music Unavailable", isPresented: $showUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This attachment can’t be opened right now. Try another link or remove the song from this note.")
        }
    }

    private var artworkView: some View {
        Group {
            if let urlStr = song.albumArtURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        artFallback
                    }
                }
            } else {
                artFallback
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var artFallback: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.black.opacity(0.06))
            .overlay(
                Image(systemName: "music.note")
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.black.opacity(0.55))
            )
    }

    private var statusLine: String {
        let base = song.subtitle ?? song.artist
        let helper = song.availabilityState.helperText
        return base.isEmpty ? helper : "\(base) · \(helper)"
    }

    private var trailingIcon: String {
        switch song.availabilityState {
        case .unavailable:
            return "exclamationmark.circle"
        case .accountRequired:
            return "lock.circle"
        case .viewOnly:
            return "arrow.up.right.circle"
        case .readyToOpen:
            return "arrow.up.right"
        }
    }

    private var preferredURL: URL? {
        guard let deepLinkURL = song.deepLinkURL, let url = URL(string: deepLinkURL) else {
            return nil
        }
        return UIApplication.shared.canOpenURL(url) ? url : nil
    }

    private var webFallbackURL: URL? {
        guard let webURL = song.webURL else { return nil }
        return URL(string: webURL)
    }

    private func handlePlayTap() {
        if let preferredURL {
            openURL(preferredURL)
        } else if let webFallbackURL {
            openURL(webFallbackURL)
        } else {
            showUnavailableAlert = true
        }
    }
}

struct ElegantMetadataRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.4))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.systemScaled(11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.4))
                
                Text(value)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.75))
            }
            
            Spacer()
        }
    }
}

// MARK: - Share With Friends Sheet

struct ShareWithFriendsSheet: View {
    @Environment(\.dismiss) var dismiss
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    
    @ObservedObject private var followService = FollowService.shared
    @State private var selectedFriends = Set<String>()
    @State private var isSharing = false
    @State private var showSuccessToast = false
    @State private var searchText = ""
    
    var filteredFriends: [FollowUserProfile] {
        if searchText.isEmpty {
            return followService.followingList
        } else {
            return followService.followingList.filter { friend in
                friend.displayName.localizedCaseInsensitiveContains(searchText) ||
                friend.username.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Dark gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.08, blue: 0.12),
                        Color(red: 0.12, green: 0.10, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Text("Share with Friends")
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.white)
                        
                        Spacer()
                        
                        Button {
                            shareWithSelectedFriends()
                        } label: {
                            if isSharing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Share")
                                    .font(AMENFont.bold(16))
                                    .foregroundStyle(selectedFriends.isEmpty ? .white.opacity(0.3) : .white)
                            }
                        }
                        .disabled(selectedFriends.isEmpty || isSharing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    
                    // Search Bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.systemScaled(16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        TextField("Search friends...", text: $searchText)
                            .font(AMENFont.regular(16))
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.systemScaled(16))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.1))
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    
                    // Selected Count
                    if !selectedFriends.isEmpty {
                        HStack {
                            Text("\(selectedFriends.count) friend\(selectedFriends.count == 1 ? "" : "s") selected")
                                .font(AMENFont.semiBold(14))
                                .foregroundStyle(.white.opacity(0.7))
                            
                            Spacer()
                            
                            Button {
                                selectedFriends.removeAll()
                            } label: {
                                Text("Clear All")
                                    .font(AMENFont.semiBold(14))
                                    .foregroundStyle(.purple)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                    }
                    
                    // Friends List
                    if followService.followingList.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "person.2.slash")
                                .font(.systemScaled(48))
                                .foregroundStyle(.white.opacity(0.3))
                            
                            Text("No Friends Yet")
                                .font(AMENFont.bold(20))
                                .foregroundStyle(.white)
                            
                            Text("Follow people to share notes with them")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 40)
                    } else if filteredFriends.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.systemScaled(48))
                                .foregroundStyle(.white.opacity(0.3))
                            
                            Text("No Results")
                                .font(AMENFont.bold(20))
                                .foregroundStyle(.white)
                            
                            Text("Try a different search term")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 40)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(filteredFriends) { friend in
                                    FriendSelectionRow(
                                        friend: friend,
                                        isSelected: selectedFriends.contains(friend.id)
                                    ) {
                                        toggleFriendSelection(friend.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .overlay {
            if showSuccessToast {
                VStack {
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.systemScaled(20))
                            .foregroundStyle(.green)
                        
                        Text("Note shared with \(selectedFriends.count) friend\(selectedFriends.count == 1 ? "" : "s")")
                            .font(AMENFont.semiBold(15))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.black.opacity(0.9))
                    )
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            // Load following list when sheet appears
            if followService.followingList.isEmpty {
                followService.startListening()
            }
        }
    }
    
    private func toggleFriendSelection(_ friendId: String) {
        if selectedFriends.contains(friendId) {
            selectedFriends.remove(friendId)
        } else {
            selectedFriends.insert(friendId)
        }
        
        let haptic = UISelectionFeedbackGenerator()
        haptic.selectionChanged()
    }
    
    private func shareWithSelectedFriends() {
        guard !selectedFriends.isEmpty else { return }
        
        isSharing = true
        
        Task {
            do {
                try await notesService.shareWithUsers(note: note, userIds: Array(selectedFriends))
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        showSuccessToast = true
                    }
                    
                    // Auto-hide toast and dismiss sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                            showSuccessToast = false
                        }
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSharing = false
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Friend Selection Row

struct FriendSelectionRow: View {
    let friend: FollowUserProfile
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Profile Image / Initial
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .purple.opacity(0.8),
                                    .purple.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    
                    if let imageURL = friend.profileImageURL, !imageURL.isEmpty {
                        CachedAsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Text(friend.initials)
                                .font(AMENFont.bold(18))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    } else {
                        Text(friend.initials)
                            .font(AMENFont.bold(18))
                            .foregroundStyle(.white)
                    }
                }
                
                // Friend Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.displayName)
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.white)
                    
                    Text("@\(friend.username)")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Selection Indicator
                ZStack {
                    Circle()
                        .strokeBorder(.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 28, height: 28)
                    
                    if isSelected {
                        Circle()
                            .fill(.purple)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.systemScaled(14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.15) : .white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? .purple.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ChurchNotesView()
}

// MARK: - Minimal Typography Design Components (Inspired by Gentle Systems)

// MARK: - Minimal Typography Header (AMEN Liquid Glass)
struct MinimalTypographyHeader: View {
    @Binding var searchText: String
    @Binding var selectedFilter: ChurchNotesView.FilterOption
    let isScrolled: Bool
    let onNewNote: () -> Void
    var notes: [ChurchNote] = []
    @State private var showSemanticSearch = false
    @Namespace private var filterNS

    var body: some View {
        VStack(spacing: 0) {
            // ── Title row ──────────────────────────────────────────────
            HStack(alignment: .firstTextBaseline) {
                Text("Church Notes")
                    .font(.systemScaled(isScrolled ? 22 : 34, weight: .semibold))
                    .foregroundStyle(.primary)
                    .tracking(-0.5)
                    .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isScrolled)

                Spacer()

                // Berean semantic (AI) search
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showSemanticSearch = true
                } label: {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(.thinMaterial)
                                .overlay(Circle().fill(Color.purple.opacity(0.08)))
                                .overlay(Circle().strokeBorder(Color.purple.opacity(0.18), lineWidth: 0.75))
                        )
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showSemanticSearch) {
                    NavigationStack {
                        BereanSemanticSearchView(notes: notes)
                            .navigationTitle("Smart Search")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") { showSemanticSearch = false }
                                }
                            }
                    }
                    .presentationDetents([.large])
                }

                // New note
                Button(action: onNewNote) {
                    Image(systemName: "plus")
                        .font(.systemScaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(.thinMaterial)
                                .overlay(Circle().fill(Color.white.opacity(0.5)))
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                        )
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, isScrolled ? 10 : 6)

            // ── Subtitle (collapses on scroll) ─────────────────────────
            if !isScrolled {
                Text("Capture sermon insights, reflections, and scriptures.")
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Search bar ─────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.systemScaled(15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search notes, scriptures…", text: $searchText)
                    .font(.systemScaled(16))
                    .foregroundStyle(.primary)
                    .tint(.primary)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(16))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // ── Filter chips ───────────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ChurchNotesView.FilterOption.allCases, id: \.self) { filter in
                        let isActive = selectedFilter == filter
                        Button {
                            withAnimation(Motion.adaptive(.spring(response: 0.28, dampingFraction: 0.76))) {
                                selectedFilter = filter
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(filter.rawValue)
                                .font(.systemScaled(13, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    ZStack {
                                        if isActive {
                                            Capsule()
                                                .fill(.thinMaterial)
                                                .overlay(Capsule().fill(Color.white.opacity(0.80)))
                                                .overlay(Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 1))
                                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                                                .matchedGeometryEffect(id: "filterActive", in: filterNS)
                                        } else {
                                            Capsule()
                                                .fill(Color.black.opacity(0.05))
                                                .overlay(Capsule().strokeBorder(Color.black.opacity(0.04), lineWidth: 0.75))
                                        }
                                    }
                                )
                                .scaleEffect(isActive ? 1.02 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: isActive)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }

            // ── Hair-line separator ────────────────────────────────────
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
        .background(.thinMaterial)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isScrolled)
    }
}

// MARK: - Minimal Notes List (AMEN Liquid Glass)
struct MinimalNotesList: View {
    let notes: [ChurchNote]
    @ObservedObject var notesService: ChurchNotesService
    @Binding var scrollOffset: CGFloat
    let onNoteSelected: (ChurchNote) -> Void

    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: geometry.frame(in: .named("scroll")).minY
                )
            }
            .frame(height: 0)

            if let insights = ChurchNotesInsights.make(from: notes) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your rhythm")
                        .font(.systemScaled(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)

                    if let rhythm = insights.attendanceRhythm {
                        AttendanceRhythmCard(title: rhythm.title, subtitle: rhythm.subtitle)
                    }

                    if let focus = insights.prayerFocus {
                        PrayerFocusCard(text: focus.text)
                    }

                    if !insights.favoriteThemes.isEmpty {
                        FavoriteThemesRow(themes: insights.favoriteThemes)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            LazyVStack(spacing: 10) {
                ForEach(notes) { note in
                    MinimalNoteRow(
                        note: note,
                        notesService: notesService,
                        onTap: { onNoteSelected(note) }
                    )
                    .scrollTransition(.animated(.spring(response: 0.3, dampingFraction: 0.8))) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                            .opacity(phase.isIdentity ? 1.0 : 0.6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
    }
}

// MARK: - Minimal Note Row (AMEN Liquid Glass card)
struct MinimalNoteRow: View {
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    let onTap: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                // ── Left: title + sermon context
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title)
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                        Text(sermonTitle)
                            .font(.systemScaled(14, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Tag pills (up to 3)
                    if !note.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(note.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.systemScaled(11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.05))
                                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                                    )
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                // ── Right: share + date + favorite
                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Text(note.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.systemScaled(13, weight: .regular))
                        .foregroundStyle(.secondary)

                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.systemScaled(11))
                            .foregroundStyle(Color.cnGold)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .noteRowCard()
            .scaleEffect(isPressed ? 0.975 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .contextMenu {
            Button {
                showShareSheet = true
            } label: {
                Label("Share Note", systemImage: "square.and.arrow.up")
            }

            Button {
                Task { try? await notesService.toggleFavorite(note) }
            } label: {
                Label(
                    note.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: note.isFavorite ? "star.slash" : "star.fill"
                )
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ChurchNoteShareOptionsSheet(note: note)
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { try? await notesService.deleteNote(note) }
            }
        }
    }
}

// MARK: - Minimal Loading View (AMEN Liquid Glass)
struct MinimalLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.secondary)
                .scaleEffect(1.1)

            Text("Loading notes…")
                .font(.systemScaled(15, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }
}

// MARK: - Minimal Empty State (AMEN Liquid Glass)
struct MinimalEmptyState: View {
    let hasSearch: Bool
    let filterType: ChurchNotesView.FilterOption
    let onCreateNote: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Glass icon container
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(0.60)))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.05), radius: 12, y: 4)

                Image(systemName: hasSearch ? "magnifyingglass" : "note.text")
                    .font(.systemScaled(32, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .scaleEffect(appeared ? 1.0 : 0.82)
            .opacity(appeared ? 1.0 : 0)

            VStack(spacing: 10) {
                Text(emptyTitle)
                    .font(.systemScaled(24, weight: .semibold))
                    .foregroundStyle(.primary)
                    .tracking(-0.3)

                Text(emptySubtitle)
                    .font(.systemScaled(16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
            }
            .opacity(appeared ? 1.0 : 0)
            .offset(y: appeared ? 0 : 10)

            if !hasSearch && filterType == .all {
                Button(action: onCreateNote) {
                    Text("Create First Note")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(.thinMaterial)
                                .overlay(Capsule().fill(Color.white.opacity(0.70)))
                                .overlay(Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 1))
                        )
                        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                }
                .opacity(appeared ? 1.0 : 0)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.52, dampingFraction: 0.80)).delay(0.1)) {
                appeared = true
            }
        }
    }
    
    var emptyTitle: String {
        if hasSearch { return "No Results" }
        switch filterType {
        case .all: return "No Notes Yet"
        case .favorites: return "No Favorites"
        case .recent: return "No Recent Notes"
        case .forYou: return "No Recommendations"
        case .following: return "No Notes from Following"
        case .sharedWithMe: return "No Shared Notes"
        case .community: return "No Community Notes"
        }
    }
    
    var emptySubtitle: String {
        if hasSearch { return "Try different keywords" }
        switch filterType {
        case .all: return "Start capturing your sermon insights and reflections"
        case .favorites: return "Star notes to save them here"
        case .recent: return "Notes from the last 7 days will appear here"
        case .forYou: return "Your personalized feed will appear here"
        case .following: return "Notes from people you follow will appear here"
        case .sharedWithMe: return "Shared notes will appear here"
        case .community: return "Community notes will appear here"
        }
    }
}

// MARK: - Minimal New Note Sheet (Text Editor Style)
struct MinimalNewNoteSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var title = ""
    @State private var sermonTitle = ""
    @State private var churchName = ""
    @State private var pastor = ""
    @State private var selectedDate = Date()
    @State private var content = ""
    @State private var scripture = ""
    @State private var tags: [String] = []
    @State private var isSaving = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingToolbar = false
    @State private var editorScrollOffset: CGFloat = 0
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var isEditorFocused = false
    @State private var worshipSongs: [WorshipSongReference] = []
    @State private var showWorshipPicker = false

    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
    /// Drives formatting toolbar compression — 0 = fully visible, 1 = fully hidden
    private var toolbarCompression: CGFloat {
        min(max((-editorScrollOffset - 20) / 60, 0), 1.0)
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header (Liquid Glass bar)
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.systemScaled(17, weight: .regular))
                    .foregroundStyle(.secondary)

                    Spacer()

                    Text("New Note")
                        .font(.systemScaled(17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        saveNote()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.primary)
                        } else {
                            Text("Save")
                                .font(.systemScaled(17, weight: .semibold))
                                .foregroundStyle(canSave ? .primary : Color.primary.opacity(0.3))
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.thinMaterial)

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Scroll offset tracker — drives formatting toolbar compression
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("noteEditorScroll")).minY
                            )
                        }
                        .frame(height: 0)
                        
                        // Title field (large)
                        TextField("Note Title", text: $title)
                            .font(.systemScaled(32, weight: .medium))
                            .foregroundStyle(.primary)
                            .tint(.black)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Sermon context (collapsible section)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Sermon Context")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(1)
                                .padding(.horizontal, 20)
                            
                            VStack(spacing: 12) {
                                MinimalTextField(icon: "mic", placeholder: "Sermon title", text: $sermonTitle)
                                MinimalTextField(icon: "building.2", placeholder: "Church name", text: $churchName)
                                MinimalTextField(icon: "person", placeholder: "Pastor", text: $pastor)
                                
                                // Date picker
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.systemScaled(16))
                                        .foregroundStyle(.black.opacity(0.4))
                                        .frame(width: 24)
                                    
                                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(.black)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.thinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.68)))
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                                )
                                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                                .padding(.horizontal, 20)
                            }
                        }

                        // Scripture
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Scripture Reference")
                                .font(.systemScaled(13, weight: .medium))
                                .foregroundStyle(.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(1)
                                .padding(.horizontal, 20)
                            
                            MinimalTextField(icon: "book", placeholder: "e.g., John 3:16", text: $scripture)
                        }
                        
                        // Main content editor
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Your Notes")
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.5))
                                    .textCase(.uppercase)
                                    .tracking(1)
                                
                                Spacer()
                                
                                // Formatting toolbar toggle
                                Button {
                                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                        showingToolbar.toggle()
                                    }
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: showingToolbar ? "textformat" : "textformat")
                                            .font(.systemScaled(12, weight: .medium))
                                        Text(showingToolbar ? "Hide" : "Format")
                                            .font(.systemScaled(12, weight: .medium))
                                    }
                                    .foregroundStyle(.black.opacity(0.5))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(showingToolbar ? Color.black.opacity(0.06) : Color.clear)
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Formatting toolbar — compresses as user scrolls into the note
                            if showingToolbar {
                                TextFormattingToolbar(
                                    content: $content,
                                    selectedRange: $editorSelection,
                                    onApplyFormatting: {
                                        isEditorFocused = true
                                    }
                                )
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                                .opacity(1.0 - toolbarCompression)
                                .scaleEffect(y: 1.0 - toolbarCompression * 0.15, anchor: .top)
                                .frame(height: max(0, (1.0 - toolbarCompression) * 52), alignment: .top)
                                .clipped()
                                .animation(Motion.adaptive(.interactiveSpring(response: 0.22, dampingFraction: 0.78)), value: toolbarCompression)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                            
                            ZStack(alignment: .topLeading) {
                                if content.isEmpty {
                                    Text("Start writing…")
                                        .font(.systemScaled(17, weight: .regular))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 36)
                                        .padding(.vertical, 30)
                                }

                                RichTextEditor(
                                    text: $content,
                                    selectedRange: $editorSelection,
                                    isFocused: $isEditorFocused
                                )
                                .frame(minHeight: 300)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.thinMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.70)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                isEditorFocused ? Color.black.opacity(0.14) : Color.black.opacity(0.07),
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                            .padding(.horizontal, 20)
                            .animation(.easeInOut(duration: 0.18), value: isEditorFocused)
                        }

                        // Worship Music section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Worship Music")
                                    .font(.systemScaled(13, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.5))
                                    .textCase(.uppercase)
                                    .tracking(1)
                                Spacer()
                                Button {
                                    showWorshipPicker = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.systemScaled(12, weight: .semibold))
                                        Text("Add Song")
                                            .font(.systemScaled(12, weight: .medium))
                                    }
                                    .foregroundStyle(.black.opacity(0.6))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.black.opacity(0.06)))
                                    .overlay(Capsule().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
                                }
                            }
                            .padding(.horizontal, 20)

                            if worshipSongs.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "music.note")
                                        .font(.systemScaled(14))
                                        .foregroundStyle(.secondary)
                                    Text("Add worship songs from this sermon")
                                        .font(.systemScaled(14))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.thinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.60)))
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.75))
                                )
                                .padding(.horizontal, 20)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(worshipSongs) { song in
                                        HStack(spacing: 12) {
                                            Image(systemName: "music.note")
                                                .font(.systemScaled(14))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 32, height: 32)
                                                .background(Color.black.opacity(0.05))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(song.title)
                                                    .font(.systemScaled(14, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                Text(song.artist)
                                                    .font(.systemScaled(12))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Button {
                                                worshipSongs.removeAll { $0.id == song.id }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.systemScaled(12, weight: .medium))
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 28, height: 28)
                                                    .background(Color.black.opacity(0.05))
                                                    .clipShape(Circle())
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(.thinMaterial)
                                                .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.68)))
                                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
                                        )
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                .coordinateSpace(name: "noteEditorScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                        editorScrollOffset = value
                    }
                }
            }
        }
        .sheet(isPresented: $showWorshipPicker) {
            WorshipSongPickerSheet(noteId: nil) { song in
                if !worshipSongs.contains(where: { $0.title == song.title && $0.artist == song.artist }) {
                    worshipSongs.append(song)
                }
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func saveNote() {
        guard let userId = FirebaseManager.shared.currentUser?.uid else {
            errorMessage = "You must be signed in to create notes."
            showErrorAlert = true
            return
        }
        
        guard canSave else {
            dlog("⚠️ Cannot save: title=\(title.isEmpty ? "empty" : "ok"), content=\(content.isEmpty ? "empty" : "ok")")
            return
        }
        
        isSaving = true
        
        let note = ChurchNote(
            userId: userId,
            title: title,
            sermonTitle: sermonTitle.isEmpty ? nil : sermonTitle,
            churchName: churchName.isEmpty ? nil : churchName,
            pastor: pastor.isEmpty ? nil : pastor,
            date: selectedDate,
            content: content,
            scripture: scripture.isEmpty ? nil : scripture,
            keyPoints: [],
            tags: tags,
            worshipSongs: worshipSongs
        )
        
        dlog("💾 Attempting to save note:")
        dlog("   Title: \(note.title)")
        dlog("   Content length: \(note.content.count) chars")
        dlog("   User ID: \(userId)")
        
        Task {
            do {
                try await notesService.createNote(note)
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    dlog("✅ Note saved successfully, dismissing sheet")
                    dismiss()
                }
            } catch {
                dlog("❌ Save failed: \(error)")
                dlog("   Error details: \(error.localizedDescription)")
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save note: \(error.localizedDescription)"
                    showErrorAlert = true
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

// MARK: - Church Notes Insights (Private)

private struct ChurchNotesInsights {
    struct Rhythm {
        let title: String
        let subtitle: String
    }
    struct PrayerFocus {
        let text: String
    }

    let attendanceRhythm: Rhythm?
    let favoriteThemes: [String]
    let prayerFocus: PrayerFocus?

    static func make(from notes: [ChurchNote]) -> ChurchNotesInsights? {
        guard !notes.isEmpty else { return nil }

        let rhythm = AttendanceRhythmInsights.compute(from: notes)
        let themes = FavoriteThemeInsights.compute(from: notes)
        let focus = PrayerFocusStore.shared.latestFocus()

        if rhythm == nil && themes.isEmpty && focus == nil { return nil }
        return ChurchNotesInsights(attendanceRhythm: rhythm, favoriteThemes: themes, prayerFocus: focus)
    }
}

private struct AttendanceRhythmInsights {
    static func compute(from notes: [ChurchNote]) -> ChurchNotesInsights.Rhythm? {
        let dates = notes.map { $0.date }.sorted(by: >)
        guard let mostRecent = dates.first else { return nil }

        let calendar = Calendar.current
        let weeks = dates.map { calendar.dateComponents([.weekOfYear, .yearForWeekOfYear], from: $0) }
        let uniqueWeeks = Set(weeks.compactMap { comp -> String? in
            guard let week = comp.weekOfYear, let year = comp.yearForWeekOfYear else { return nil }
            return "\(year)-\(week)"
        })
        let streak = computeWeeklyStreak(from: dates)

        let title: String
        if streak >= 3 {
            title = "\(streak)-week rhythm"
        } else if streak == 2 {
            title = "2-week rhythm"
        } else {
            title = "Recent reflection"
        }

        let subtitle = "\(uniqueWeeks.count) weeks reflected · last note \(mostRecent.formatted(.dateTime.month(.abbreviated).day()))"
        return ChurchNotesInsights.Rhythm(title: title, subtitle: subtitle)
    }

    private static func computeWeeklyStreak(from dates: [Date]) -> Int {
        let calendar = Calendar.current
        guard let mostRecent = dates.first else { return 0 }
        var streak = 0
        var current = mostRecent

        while true {
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: current)?.start
            guard let weekStart = startOfWeek else { break }
            let hasNoteThisWeek = dates.contains { date in
                let interval = calendar.dateInterval(of: .weekOfYear, for: date)
                return interval?.contains(weekStart) ?? false
            }
            if !hasNoteThisWeek { break }
            streak += 1
            guard let prevWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart) else { break }
            current = prevWeek
        }
        return streak
    }
}

private struct FavoriteThemeInsights {
    static func compute(from notes: [ChurchNote]) -> [String] {
        var counts: [String: Int] = [:]
        notes.forEach { note in
            let tags = (note.tags + note.claudeTags).map { $0.lowercased() }
            for tag in tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }
}

private final class PrayerFocusStore {
    static let shared = PrayerFocusStore()
    private let storageKey = "churchNotesPrayerFocus"

    private init() {}

    func saveFocus(text: String, noteId: String?) {
        let item = PrayerFocusItem(id: UUID().uuidString, text: text, noteId: noteId, createdAt: Date())
        var items = loadAll()
        items.insert(item, at: 0)
        persist(items: items)
    }

    func latestFocus() -> ChurchNotesInsights.PrayerFocus? {
        guard let item = loadAll().first else { return nil }
        return ChurchNotesInsights.PrayerFocus(text: item.text)
    }

    private func loadAll() -> [PrayerFocusItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PrayerFocusItem].self, from: data)) ?? []
    }

    private func persist(items: [PrayerFocusItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct PrayerFocusItem: Codable {
    let id: String
    let text: String
    let noteId: String?
    let createdAt: Date
}

private struct AttendanceRhythmCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.circle.fill")
                .font(.systemScaled(16))
                .foregroundStyle(.black.opacity(0.75))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.systemScaled(12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6)))
    }
}

private struct PrayerFocusCard: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hands.sparkles")
                .font(.systemScaled(16))
                .foregroundStyle(.black.opacity(0.75))
            Text(text)
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6)))
    }
}

private struct FavoriteThemesRow: View {
    let themes: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(themes.prefix(4), id: \.self) { theme in
                Text(theme)
                    .font(.systemScaled(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.05)))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Rich Text Editor
struct RichTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 17, weight: .regular)
        textView.textColor = UIColor.black
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
        }
        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selectedRange = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }
    }
}

// MARK: - Minimal Text Field (AMEN Liquid Glass)
struct MinimalTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            TextField(placeholder, text: $text)
                .font(.systemScaled(16))
                .foregroundStyle(.primary)
                .tint(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.68)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.07), lineWidth: 0.75))
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
        .padding(.horizontal, 20)
    }
}

// MARK: - Minimal Note Detail Sheet
struct MinimalNoteDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var showCopiedToast = false
    @State private var localWorshipSongs: [WorshipSongReference] = []
    @State private var showPrayerSaved = false

    // AI Features
    @State private var noteSummary: NoteSummary?
    @State private var isGeneratingSummary = false
    @State private var scriptureReferences: [AIScriptureRef] = []
    @State private var isLoadingScripture = false
    @State private var showAISection = false
    
    var body: some View {
        bodyContent
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.systemScaled(20, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button {
                            Task {
                                try? await notesService.toggleFavorite(note)
                            }
                        } label: {
                            Image(systemName: note.isFavorite ? "star.fill" : "star")
                                .font(.systemScaled(20))
                                .foregroundStyle(.primary)
                        }
                        
                        Menu {
                            Button {
                                showShareSheet = true
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            
                            Button {
                                copyNoteShareLink()
                            } label: {
                                Label("Copy Note Link", systemImage: "link")
                            }
                            
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.systemScaled(20, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.thinMaterial)

                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title
                        Text(note.title)
                            .font(.systemScaled(38, weight: .medium))
                            .foregroundStyle(.primary)
                            .tracking(-1)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                        
                        // Metadata rows (minimal)
                        VStack(alignment: .leading, spacing: 8) {
                            if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                                MinimalMetadataRow(label: "Sermon", value: sermonTitle)
                            }
                            if let churchName = note.churchName, !churchName.isEmpty {
                                MinimalMetadataRow(label: "Church", value: churchName)
                            }
                            if let pastor = note.pastor, !pastor.isEmpty {
                                MinimalMetadataRow(label: "Pastor", value: pastor)
                            }
                            if let scripture = note.scripture, !scripture.isEmpty {
                                MinimalMetadataRow(label: "Scripture", value: scripture)
                            }
                            MinimalMetadataRow(label: "Date", value: note.date.formatted(date: .long, time: .omitted))
                        }
                        .padding(.horizontal, 20)
                        
                        Divider()
                            .background(Color.black.opacity(0.1))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        
                        // AI Features Section
                        VStack(alignment: .leading, spacing: 16) {
                            // AI Features Toggle Button
                            Button {
                                withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                                    showAISection.toggle()
                                }
                                
                                if showAISection && noteSummary == nil && !isGeneratingSummary {
                                    generateSummary()
                                }
                                if showAISection && scriptureReferences.isEmpty && !isLoadingScripture {
                                    loadScriptureReferences()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "sparkles")
                                        .font(.systemScaled(16, weight: .semibold))
                                    
                                    Text("AI Insights")
                                        .font(.systemScaled(16, weight: .semibold))
                                    
                                    Spacer()
                                    
                                    Image(systemName: showAISection ? "chevron.up" : "chevron.down")
                                        .font(.systemScaled(14, weight: .medium))
                                }
                                .foregroundStyle(.purple)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.purple.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.purple.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                            
                            if showAISection {
                                // AI Summary
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "brain.head.profile")
                                            .font(.systemScaled(14, weight: .semibold))
                                        Text("AI Summary")
                                            .font(.systemScaled(15, weight: .semibold))
                                        
                                        if isGeneratingSummary {
                                            Spacer()
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                    }
                                    .foregroundStyle(.black.opacity(0.8))
                                    
                                    if let summary = noteSummary {
                                        VStack(alignment: .leading, spacing: 12) {
                                            // Main Theme
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Main Theme")
                                                    .font(.systemScaled(13, weight: .medium))
                                                    .foregroundStyle(.black.opacity(0.5))
                                                Text(summary.mainTheme)
                                                    .font(.systemScaled(15, weight: .regular))
                                                    .foregroundStyle(.primary)
                                            }
                                            
                                            // Key Points
                                            if !summary.keyPoints.isEmpty {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("Key Points")
                                                        .font(.systemScaled(13, weight: .medium))
                                                        .foregroundStyle(.black.opacity(0.5))
                                                    ForEach(summary.keyPoints, id: \.self) { point in
                                                        HStack(alignment: .top, spacing: 8) {
                                                            Text("•")
                                                                .font(.systemScaled(15, weight: .bold))
                                                            Text(point)
                                                                .font(.systemScaled(14, weight: .regular))
                                                        }
                                                        .foregroundStyle(.primary)
                                                    }
                                                }
                                            }
                                            
                                            // Action Steps
                                            if !summary.actionSteps.isEmpty {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("Action Steps")
                                                        .font(.systemScaled(13, weight: .medium))
                                                        .foregroundStyle(.black.opacity(0.5))
                                                    ForEach(summary.actionSteps, id: \.self) { step in
                                                        HStack(alignment: .top, spacing: 8) {
                                                            Image(systemName: "checkmark.circle.fill")
                                                                .font(.systemScaled(12))
                                                                .foregroundStyle(.green)
                                                            Text(step)
                                                                .font(.systemScaled(14, weight: .regular))
                                                                .foregroundStyle(.primary)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color.white)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                                                )
                                        )
                                    } else if !isGeneratingSummary {
                                        Text("Failed to generate summary")
                                            .font(.systemScaled(14, weight: .regular))
                                            .foregroundStyle(.black.opacity(0.5))
                                            .italic()
                                    }
                                }
                                
                                // Scripture Cross-References
                                if !scriptureReferences.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: "book.closed.fill")
                                                .font(.systemScaled(14, weight: .semibold))
                                            Text("Related Scripture")
                                                .font(.systemScaled(15, weight: .semibold))
                                        }
                                        .foregroundStyle(.black.opacity(0.8))
                                        
                                        VStack(spacing: 8) {
                                            ForEach(scriptureReferences.prefix(5)) { reference in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(reference.verse)
                                                        .font(.systemScaled(14, weight: .semibold))
                                                        .foregroundStyle(.blue)
                                                    Text(reference.description)
                                                        .font(.systemScaled(13, weight: .regular))
                                                        .foregroundStyle(.black.opacity(0.7))
                                                }
                                                .padding(10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.blue.opacity(0.05))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .strokeBorder(Color.blue.opacity(0.1), lineWidth: 1)
                                                        )
                                                )
                                            }
                                        }
                                    }
                                } else if isLoadingScripture {
                                    HStack {
                                        Image(systemName: "book.closed.fill")
                                            .font(.systemScaled(14, weight: .semibold))
                                        Text("Loading related scripture...")
                                            .font(.systemScaled(15, weight: .semibold))
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                    .foregroundStyle(.black.opacity(0.5))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        // Content
                        Text(note.content)
                            .font(.systemScaled(17, weight: .regular))
                            .foregroundStyle(.primary)
                            .lineSpacing(6)
                            .padding(.horizontal, 20)

                        prayerFocusSection

                        // Worship songs
                        if !localWorshipSongs.isEmpty {
                            SavedWorshipSongsSection(
                                songs: localWorshipSongs,
                                noteId: note.id,
                                onRemove: { song in
                                    localWorshipSongs.removeAll { $0.id == song.id }
                                    Task {
                                        try? await notesService.updateWorshipSongs(localWorshipSongs, for: note)
                                    }
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { localWorshipSongs = note.worshipSongs }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await notesService.deleteNote(note)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareText()])
        }
    }

    private var prayerFocusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                let focusText = defaultPrayerFocusTextLocal(from: note)
                PrayerFocusStore.shared.saveFocus(text: focusText, noteId: note.id)
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                withAnimation(.easeOut(duration: 0.25)) {
                    showPrayerSaved = true
                }
                Task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showPrayerSaved = false
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hands.sparkles")
                        .font(.systemScaled(14, weight: .semibold))
                    Text("Save to this week’s prayer focus")
                        .font(.systemScaled(14, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.75))
                )
            }
            .buttonStyle(.plain)

            if showPrayerSaved {
                Text("Saved to prayer focus")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
    }

    private func defaultPrayerFocusTextLocal(from note: ChurchNote) -> String {
        if let scripture = note.scripture, !scripture.isEmpty {
            return "Pray through \(scripture)"
        }
        if !note.keyPoints.isEmpty {
            return note.keyPoints[0]
        }
        let trimmed = note.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if let sentenceEnd = trimmed.firstIndex(of: ".") {
            return String(trimmed[..<sentenceEnd]).prefix(120) + "…"
        }
        return String(trimmed.prefix(120))
    }

    private func generateShareText() -> String {
        var text = "📝 \(note.title)\n\n"
        
        if let sermon = note.sermonTitle {
            text += "Sermon: \(sermon)\n"
        }
        if let church = note.churchName {
            text += "Church: \(church)\n"
        }
        if let pastor = note.pastor {
            text += "Pastor: \(pastor)\n"
        }
        if let scripture = note.scripture {
            text += "Scripture: \(scripture)\n"
        }
        
        text += "\n\(note.content)\n"
        
        if !note.tags.isEmpty {
            text += "\n" + note.tags.map { "#\($0)" }.joined(separator: " ")
        }
        
        return text
    }
    
    // MARK: - Copy Note Share Link
    
    private func copyNoteShareLink() {
        guard let linkId = note.shareLinkId else {
            dlog("❌ Note has no share link ID")
            return
        }
        
        // Create shareable deep link
        let shareURL = "amenapp://note/\(linkId)"
        UIPasteboard.general.string = shareURL
        
        // Show toast confirmation with animation
        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
            showCopiedToast = true
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        dlog("✅ Note link copied: \(shareURL)")
        
        // Hide toast after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCopiedToast = false
                }
            }
        }
    }
    
    // MARK: - AI Features
    
    private func generateSummary() {
        isGeneratingSummary = true
        
        Task {
            let userId = FirebaseManager.shared.currentUser?.uid ?? ""
            do {
                // Route through BereanOrchestrator (multi-provider, RAG-grounded, circuit-broken)
                let jsonString = try await BereanOrchestrator.shared.summarizeChurchNote(
                    content: note.content,
                    userId: userId
                )
                // Parse structured JSON into NoteSummary
                let summary = parseBereanNoteSummary(jsonString)
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                        noteSummary = summary
                        isGeneratingSummary = false
                    }
                }
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                dlog("✅ [Berean] Note summary generated via orchestrator")
            } catch {
                // Graceful degradation: orchestrator failed (all providers down), hide spinner
                dlog("⚠️ [Berean] Note summary unavailable: \(error)")
                await MainActor.run {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                        isGeneratingSummary = false
                    }
                }
            }
        }
    }
    
    /// Parse Berean orchestrator JSON output into NoteSummary model
    private func parseBereanNoteSummary(_ json: String) -> NoteSummary? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // If orchestrator returned plain text (emergency local fallback), wrap it
            return NoteSummary(
                mainTheme: json,
                scripture: [],
                keyPoints: [],
                actionSteps: [],
                generatedAt: Date()
            )
        }
        return NoteSummary(
            mainTheme: obj["mainTheme"] as? String ?? obj["theme"] as? String ?? "Summary",
            scripture: obj["scripture"] as? [String] ?? [],
            keyPoints: obj["keyPoints"] as? [String] ?? obj["key_points"] as? [String] ?? [],
            actionSteps: obj["actionSteps"] as? [String] ?? obj["action_steps"] as? [String] ?? [],
            generatedAt: Date()
        )
    }
    
    private func loadScriptureReferences() {
        // Extract verse references from note content and scripture field
        var allText = note.content
        if let scripture = note.scripture {
            allText += " " + scripture
        }
        
        let extractedVerses = AIScriptureCrossRefService.shared.extractVerseReferences(from: allText)
        
        guard !extractedVerses.isEmpty else {
            dlog("ℹ️ No scripture references found in note")
            return
        }
        
        isLoadingScripture = true
        
        Task {
            do {
                // Get references for the first verse found
                if let firstVerse = extractedVerses.first {
                    let references = try await AIScriptureCrossRefService.shared.findRelatedVerses(for: firstVerse)
                    
                    await MainActor.run {
                        withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.7))) {
                            scriptureReferences = references
                            isLoadingScripture = false
                        }
                    }
                    
                    if !references.isEmpty {
                        let haptic = UINotificationFeedbackGenerator()
                        haptic.notificationOccurred(.success)
                        dlog("✅ Found \(references.count) related scripture references")
                    } else {
                        dlog("⚠️ Scripture references unavailable (Cloud Function not deployed)")
                    }
                }
            } catch {
                // This shouldn't happen anymore since findRelatedVerses doesn't throw
                dlog("❌ Failed to load scripture references: \(error)")
                await MainActor.run {
                    isLoadingScripture = false
                }
            }
        }
    }
}

// MARK: - Minimal Metadata Row
struct MinimalMetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.systemScaled(15, weight: .regular))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.systemScaled(15, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Text Formatting Toolbar
struct TextFormattingToolbar: View {
    @Binding var content: String
    @Binding var selectedRange: NSRange
    let onApplyFormatting: () -> Void
    @State private var selectedButton: FormattingOption? = nil
    
    enum FormattingOption {
        case bold, italic, underline, strikethrough, bulletList, numberedList, heading, quote
        
        var icon: String {
            switch self {
            case .bold: return "bold"
            case .italic: return "italic"
            case .underline: return "underline"
            case .strikethrough: return "strikethrough"
            case .bulletList: return "list.bullet"
            case .numberedList: return "list.number"
            case .heading: return "textformat.size"
            case .quote: return "quote.opening"
            }
        }
        
        var prefix: String {
            switch self {
            case .bold: return "**"
            case .italic: return "_"
            case .underline: return "__"
            case .strikethrough: return "~~"
            case .bulletList: return "• "
            case .numberedList: return "1. "
            case .heading: return "# "
            case .quote: return "> "
            }
        }
        
        var suffix: String {
            switch self {
            case .bold: return "**"
            case .italic: return "_"
            case .underline: return "__"
            case .strikethrough: return "~~"
            case .bulletList, .numberedList, .heading, .quote: return ""
            }
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([FormattingOption.bold, .italic, .underline, .heading, .bulletList, .numberedList, .quote], id: \.icon) { option in
                    FormattingButton(
                        option: option,
                        isSelected: selectedButton == option,
                        action: {
                            applyFormatting(option)
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func applyFormatting(_ option: FormattingOption) {
        // Flash animation
        withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.6))) {
            selectedButton = option
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Reset after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.6))) {
                selectedButton = nil
            }
        }
        
        // Apply formatting to selection or insert at cursor
        let nsText = content as NSString
        let range = selectedRange
        if option == .bulletList || option == .numberedList || option == .heading || option == .quote {
            let lineRange = nsText.lineRange(for: range)
            let prefix = option.prefix
            let updated = nsText.replacingCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
            content = updated
            let newCursor = lineRange.location + prefix.count
            selectedRange = NSRange(location: newCursor, length: 0)
        } else {
            if range.length == 0 {
                let insert = option.prefix + option.suffix
                let updated = nsText.replacingCharacters(in: NSRange(location: range.location, length: 0), with: insert)
                content = updated
                let cursor = range.location + option.prefix.count
                selectedRange = NSRange(location: cursor, length: 0)
            } else {
                let selectedText = nsText.substring(with: range)
                let wrapped = option.prefix + selectedText + option.suffix
                let updated = nsText.replacingCharacters(in: range, with: wrapped)
                content = updated
                let newLocation = range.location + option.prefix.count
                selectedRange = NSRange(location: newLocation, length: selectedText.count)
            }
        }
        onApplyFormatting()
    }
}

struct FormattingButton: View {
    let option: TextFormattingToolbar.FormattingOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: option.icon)
                .font(.systemScaled(16, weight: .medium))
                .foregroundStyle(isSelected ? .white : .black.opacity(0.6))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isSelected ? Color.black.opacity(0.8) : Color.black.opacity(0.04))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.black.opacity(0.15) : Color.black.opacity(0.08),
                            lineWidth: isSelected ? 0 : 0.5
                        )
                )
                .scaleEffect(isSelected ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ChurchNotesView()
}
