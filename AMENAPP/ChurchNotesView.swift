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

struct ChurchNotesView: View {
    @StateObject private var notesService = ChurchNotesService()
    @ObservedObject private var postsManager = PostsManager.shared
    @State private var showingNewNote = false
    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all
    @State private var selectedNote: ChurchNote?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var isSearchFocused = false
    @Namespace private var animation
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case favorites = "Favorites"
        case recent = "Recent"
        case community = "Shared"
        
        var icon: String {
            switch self {
            case .all: return "note.text"
            case .favorites: return "star.fill"
            case .recent: return "clock.fill"
            case .community: return "person.3.fill"
            }
        }
    }
    
    var filteredNotes: [ChurchNote] {
        var filtered = notesService.notes
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .favorites:
            filtered = filtered.filter { $0.isFavorite }
        case .recent:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            filtered = filtered.filter { $0.date >= sevenDaysAgo }
        case .community:
            // Community notes are shown separately, return empty for this filter
            return []
        }
        
        // Apply search
        if !searchText.isEmpty {
            filtered = notesService.searchNotes(query: searchText)
        }
        
        return filtered.sorted { $0.date > $1.date }
    }
    
    var body: some View {
        ZStack {
            // Minimal light gray background (matching the design)
            Color(red: 0.96, green: 0.96, blue: 0.96)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Minimal Typography Header
                MinimalTypographyHeader(
                    searchText: $searchText,
                    selectedFilter: $selectedFilter,
                    isScrolled: scrollOffset < -20,
                    onNewNote: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            showingNewNote = true
                        }
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                    }
                )
                
                // Content with minimal list design or community feed
                ZStack {
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
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
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
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedNote = note
                                }
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: notesService.isLoading)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: filteredNotes.isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showingNewNote) {
            MinimalNewNoteSheet(notesService: notesService)
        }
        .sheet(item: $selectedNote) { note in
            MinimalNoteDetailSheet(note: note, notesService: notesService)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Start real-time listener when view appears
            notesService.startListening()
        }
        .onDisappear {
            // Stop listener when view disappears
            notesService.stopListening()
        }
    }
}

// MARK: - Animated Gradient Background (Private to ChurchNotesView)

private struct ChurchNotesAnimatedGradientBackground: View {
    @State private var animateGradient = false
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
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

// MARK: - Color Extension for Hex Support

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
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
                            .font(.custom("OpenSans-Regular", size: 14))
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        headerScale = 0.95
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
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
                            .font(.system(size: 20, weight: .semibold))
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
                            .font(.system(size: 16, weight: .semibold))
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
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    TextField("", text: $searchText, prompt: Text("Search notes, sermons, scriptures...").foregroundStyle(.white.opacity(0.4)))
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.white)
                        .tint(Color(hex: "A67C52"))
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isSearchFocused = true
                            }
                        }
                        .onChange(of: searchText) { oldValue, newValue in
                            if !newValue.isEmpty && !oldValue.isEmpty {
                                let haptic = UISelectionFeedbackGenerator()
                                haptic.selectionChanged()
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                searchText = ""
                                isSearchFocused = false
                            }
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
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
                            .font(.system(size: 16, weight: .semibold))
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
                    .font(.system(size: 14, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 15))
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
                        .font(.system(size: 32))
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
                .font(.custom("OpenSans-SemiBold", size: 18))
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
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 140, height: 140)
                        .glassEffect(GlassEffectStyle.regular, in: Circle())
                }
                
                // Message
                VStack(spacing: 12) {
                    Text(emptyTitle)
                        .font(.custom("OpenSans-Bold", size: 28))
                        .foregroundStyle(.white)
                    
                    Text(emptySubtitle)
                        .font(.custom("OpenSans-Regular", size: 16))
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
                                .font(.system(size: 20))
                            Text("Create Your First Note")
                                .font(.custom("OpenSans-Bold", size: 17))
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
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                cardScale = 0.97
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                            .font(.custom("OpenSans-Bold", size: 20))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "quote.bubble.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.purple.opacity(0.8))
                                Text(sermonTitle)
                                    .font(.custom("OpenSans-SemiBold", size: 14))
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
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                                cardRotation = note.isFavorite ? -10 : 10
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                                .font(.system(size: 20))
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
                        .font(.custom("OpenSans-Regular", size: 15))
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
                            .font(.system(size: 13))
                        Text(scripture)
                            .font(.custom("OpenSans-SemiBold", size: 14))
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
                            .font(.system(size: 12))
                        Text(note.date, style: .date)
                            .font(.custom("OpenSans-Regular", size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    
                    if let churchName = note.churchName, !churchName.isEmpty {
                        Text("•")
                            .foregroundStyle(.white.opacity(0.3))
                        
                        HStack(spacing: 6) {
                            Image(systemName: "building.2")
                                .font(.system(size: 12))
                            Text(churchName)
                                .font(.custom("OpenSans-Regular", size: 13))
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
                                    .font(.custom("OpenSans-SemiBold", size: 11))
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
                                .font(.system(size: 14, weight: .semibold))
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
                    .font(.custom("OpenSans-SemiBold", size: 14))
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
            // Create post via FirebasePostService
            try await FirebasePostService.shared.createPost(
                content: shareContent.trimmingCharacters(in: .whitespacesAndNewlines),
                category: .openTable,
                topicTag: "Church Notes",
                visibility: .everyone,
                allowComments: true,
                imageURLs: nil,
                linkURL: nil
            )

            // Success haptic
            await MainActor.run {
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }

            print("✅ Church note shared to #OPENTABLE")
        } catch {
            print("❌ Failed to share church note: \(error)")
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
            print("❌ Note has no share link ID")
            return
        }
        
        // Create shareable deep link
        let shareURL = "amenapp://note/\(linkId)"
        UIPasteboard.general.string = shareURL
        
        // Show toast confirmation with animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        print("✅ Note link copied: \(shareURL)")
        
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
    
    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
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
                    Button("Cancel") {
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 17))
                    .foregroundStyle(.white.opacity(0.8))
                    
                    Spacer()
                    
                    Text("New Note")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .medium)
                        haptic.impactOccurred()
                        saveNote()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save")
                                .font(.custom("OpenSans-Bold", size: 17))
                                .foregroundStyle(canSave ? .white : .white.opacity(0.4))
                        }
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
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            VStack(spacing: 12) {
                                GlassTextField(
                                    icon: "mic",
                                    placeholder: "Sermon Title (Optional)",
                                    text: $sermonTitle
                                )
                                
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
                                
                                // Date Picker
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .frame(width: 24)
                                    
                                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(.purple)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(20)
                        .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 20))
                        
                        // Scripture
                        GlassTextField(
                            icon: "book.fill",
                            placeholder: "Scripture Reference (e.g., John 3:16)",
                            text: $scripture,
                            tintColor: .purple
                        )
                        
                        // Content Editor
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Notes", systemImage: "note.text")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            ZStack(alignment: .topLeading) {
                                if content.isEmpty {
                                    Text("Start writing your sermon notes...")
                                        .font(.custom("OpenSans-Regular", size: 16))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                }
                                
                                TextEditor(text: $content)
                                    .font(.custom("OpenSans-Regular", size: 16))
                                    .foregroundStyle(.white)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .frame(minHeight: 200)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                            }
                            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(20)
                        .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 20))
                        
                        // Tags Section
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Tags", systemImage: "tag")
                                .font(.custom("OpenSans-Bold", size: 16))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            if !tags.isEmpty {
                                FlowLayout(spacing: 8) {
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
                                        .font(.system(size: 32))
                                        .foregroundStyle(.cyan.opacity(0.9))
                                }
                                .disabled(newTag.isEmpty)
                            }
                        }
                        .padding(20)
                        .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 20))
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
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !tags.contains(trimmed) else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
            tags: tags
        )
        
        Task {
            do {
                try await notesService.createNote(note)
                
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    dismiss()
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
                .font(.system(size: isLarge ? 18 : 16))
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
        .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: String
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Text("#\(tag)")
                .font(.custom("OpenSans-SemiBold", size: 14))
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
            }
        }
        .foregroundStyle(.cyan.opacity(0.9))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(GlassEffectStyle.regular.tint(.cyan), in: Capsule())
    }
}

// MARK: - Flow Layout
// Note: FlowLayout is defined in OnboardingAdvancedComponents.swift and reused here

// MARK: - Church Note Detail View with Liquid Glass

struct ChurchNoteDetailView: View {
    @Environment(\.dismiss) var dismiss
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var showCopiedToast = false
    @State private var showShareToOpenTableSheet = false
    
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
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(GlassEffectStyle.regular.interactive(), in: Circle())
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
                            .font(.system(size: 20))
                            .foregroundStyle(note.isFavorite ? .yellow : .white)
                            .frame(width: 44, height: 44)
                            .glassEffect(GlassEffectStyle.regular.interactive(), in: Circle())
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
                            showShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
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
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(GlassEffectStyle.regular.interactive(), in: Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title and Metadata
                        VStack(alignment: .leading, spacing: 16) {
                            Text(note.title)
                                .font(.custom("OpenSans-Bold", size: 32))
                                .foregroundStyle(.white)
                                .lineSpacing(4)
                            
                            if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "quote.bubble.fill")
                                        .font(.system(size: 16))
                                    Text(sermonTitle)
                                        .font(.custom("OpenSans-SemiBold", size: 18))
                                }
                                .foregroundStyle(.white.opacity(0.8))
                            }
                            
                            // Metadata Pills
                            FlowLayout(spacing: 10) {
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
                        .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 24))
                        
                        // Scripture
                        if let scripture = note.scripture, !scripture.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.purple)
                                
                                Text(scripture)
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(.purple.opacity(0.9))
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(GlassEffectStyle.regular.tint(.purple), in: RoundedRectangle(cornerRadius: 20))
                        }
                        
                        // Content
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Notes", systemImage: "note.text")
                                .font(.custom("OpenSans-Bold", size: 18))
                                .foregroundStyle(.white.opacity(0.9))
                            
                            Text(note.content)
                                .font(.custom("OpenSans-Regular", size: 17))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineSpacing(8)
                        }
                        .padding(24)
                        .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 24))
                        
                        // Tags
                        if !note.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Label("Tags", systemImage: "tag")
                                    .font(.custom("OpenSans-Bold", size: 18))
                                    .foregroundStyle(.white.opacity(0.9))
                                
                                FlowLayout(spacing: 10) {
                                    ForEach(note.tags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.custom("OpenSans-SemiBold", size: 15))
                                            .foregroundStyle(.cyan.opacity(0.9))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .glassEffect(GlassEffectStyle.regular.tint(.cyan), in: Capsule())
                                    }
                                }
                            }
                            .padding(24)
                            .glassEffect(GlassEffectStyle.regular, in: RoundedRectangle(cornerRadius: 24))
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
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
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet) {
            ChurchNoteShareOptionsSheet(note: note)
        }
        .sheet(isPresented: $showShareToOpenTableSheet) {
            ShareNoteToOpenTableSheet(note: note)
        }
        .overlay(alignment: .bottom) {
            // Toast notification for copy confirmation
            if showCopiedToast {
                Text("Link copied to clipboard")
                    .font(.system(size: 14, weight: .semibold))
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
            print("❌ Note has no share link ID")
            return
        }
        
        // Create shareable deep link
        let shareURL = "amenapp://note/\(linkId)"
        UIPasteboard.general.string = shareURL
        
        // Show toast confirmation with animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        print("✅ Note link copied: \(shareURL)")
        
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
        showShareToOpenTableSheet = true
    }
}

// MARK: - Metadata Pill

struct MetadataPill: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(text)
                .font(.custom("OpenSans-SemiBold", size: 14))
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(GlassEffectStyle.regular, in: Capsule())
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
                    .font(.system(size: isScrolled ? 28 : 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                
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
                                        .font(.system(size: 18, weight: .semibold))
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.6))
                    
                    TextField("", text: $searchText, prompt: Text("Search notes...").foregroundStyle(.black.opacity(0.4)))
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.black)
                        .tint(.blue)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isSearchFocused = true
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isSearchFocused = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
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
        case .community: return .purple
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.system(size: 13, weight: .semibold))
                
                Text(filter.rawValue)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
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
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Sermon title if available
                    if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "quote.bubble")
                                .font(.system(size: 12))
                            Text(sermonTitle)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.black.opacity(0.6))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Content preview
                    if !note.content.isEmpty {
                        Text(note.content)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(.black.opacity(0.7))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Metadata row
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                            Text(note.date, style: .date)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        
                        if let churchName = note.churchName, !churchName.isEmpty {
                            Text("•")
                            Text(churchName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
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
                                .font(.system(size: 16))
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 80, height: 80)
            
            Text("Loading Notes...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
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
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.blue.opacity(0.6))
            }
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: bounce)
            
            VStack(spacing: 12) {
                Text(emptyTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                
                Text(emptySubtitle)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if !hasSearch && filterType == .all {
                Button(action: onCreateNote) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Create Note")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
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
        case .community: return "No Community Notes"
        }
    }
    
    var emptySubtitle: String {
        if hasSearch { return "Try different keywords" }
        switch filterType {
        case .all: return "Start capturing your sermon insights"
        case .favorites: return "Star notes to save them here"
        case .recent: return "Notes from the last 7 days appear here"
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
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.black.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Writer stats in center
                    VStack(spacing: 2) {
                        Text("New Note")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black)
                        
                        if wordCount > 0 {
                            Text("\(wordCount) words")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
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
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue.opacity(0.8))
                                .padding(.horizontal, 4)
                            
                            TextField("", text: $title, prompt: Text("Give your note a powerful title...").foregroundStyle(.black.opacity(0.4)))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
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
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                
                                Spacer()
                                
                                Text("Optional")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
                                        .font(.system(size: 16, weight: .medium))
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
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.9))
                                
                                Spacer()
                                
                                if !content.isEmpty {
                                    Text("\(wordCount) words")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
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
                                            .font(.system(size: 17, weight: .regular, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.4))
                                        
                                        Text("💡 Tip: Don't worry about perfection—just write!")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(.blue.opacity(0.5))
                                    }
                                    .padding(20)
                                }
                                
                                TextEditor(text: $content)
                                    .font(.system(size: 17, weight: .regular, design: .rounded))
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
                                    .font(.system(size: 16))
                                    .foregroundStyle(.green)
                                
                                Text("Ready to save! Your note looks great.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24)
            
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.5)))
                .font(.system(size: 16, weight: .regular, design: .rounded))
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
                            .font(.system(size: 20, weight: .semibold))
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
                            .font(.system(size: 20))
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
                        Button {
                            // Share functionality - handled by share button in footer
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .semibold))
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
                            .font(.system(size: 32, weight: .bold, design: .rounded))
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
                            .font(.system(size: 17, weight: .regular, design: .rounded))
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.black.opacity(0.6))
                .frame(width: 24)
            
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.black.opacity(0.4)))
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.black)
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
    @StateObject private var postsManager = PostsManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.black.opacity(0.6))
                    
                    Spacer()
                    
                    Text("Share to #OPENTABLE")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                    
                    Spacer()
                    
                    Button {
                        shareToOpenTable()
                    } label: {
                        if isPosting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Post")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                        }
                    }
                    .disabled(postContent.isEmpty || isPosting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.98, green: 0.98, blue: 0.98))
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Text editor for post content
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Thoughts")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(1)
                            
                            TextEditor(text: $postContent)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.black)
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                )
                        }
                        
                        // Note Preview
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Note Preview")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.black.opacity(0.5))
                                .textCase(.uppercase)
                                .tracking(1)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                // Title
                                Text(note.title)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.black)
                                
                                // Sermon info
                                if let sermon = note.sermonTitle {
                                    HStack(spacing: 6) {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 12))
                                        Text(sermon)
                                            .font(.system(size: 14))
                                    }
                                    .foregroundStyle(.black.opacity(0.6))
                                }
                                
                                // Scripture
                                if let scripture = note.scripture {
                                    HStack(spacing: 6) {
                                        Image(systemName: "book.fill")
                                            .font(.system(size: 12))
                                        Text(scripture)
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundStyle(.purple)
                                }
                                
                                // Content preview
                                Text(note.content)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.black.opacity(0.8))
                                    .lineLimit(4)
                            }
                            .padding(16)
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(20)
                }
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
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
                
                // Post to Firebase using the correct function signature
                try await FirebasePostService.shared.createPost(
                    content: fullContent,
                    category: .openTable,
                    topicTag: note.sermonTitle
                )
                
                await MainActor.run {
                    isPosting = false
                    showSuccessMessage = true
                }
            } catch {
                print("❌ Failed to share to OpenTable: \(error)")
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
                        .font(.system(size: 11, weight: .semibold, design: .default))
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
                        .font(.system(size: 15, weight: .regular, design: .default))
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
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(Color.black.opacity(0.25))
                        }
                        .padding(.top, 80)
                        
                        VStack(spacing: 8) {
                            Text("No Shared Notes Yet")
                                .font(.system(size: 22, weight: .medium, design: .default))
                                .foregroundStyle(Color.black.opacity(0.7))
                            
                            Text("Be the first to share your sermon notes\nwith the community")
                                .font(.system(size: 15, weight: .regular, design: .default))
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
        .onChange(of: selectedPost) { newValue in
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
            print("Error loading church note: \(error)")
        }
    }
}

// MARK: - Elegant Church Note Card (for ChurchNotesView)

struct ElegantChurchNoteCardForChurchNotesView: View {
    let post: Post
    @State private var churchNote: ChurchNote?
    @State private var isLoading = true
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile image
            if let profileImageURL = post.authorProfileImageURL, !profileImageURL.isEmpty {
                AsyncImage(url: URL(string: profileImageURL)) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.black.opacity(0.08))
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(post.authorInitials)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.6))
                    )
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(post.authorName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.85))
                
                if let note = churchNote {
                    Text(note.title)
                        .font(.custom("Georgia", size: 17))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else if isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Loading...")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.4))
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.3))
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.9))
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.06),
                            Color.black.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
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
            
            if let data = document.data() {
                churchNote = try? document.data(as: ChurchNote.self)
            }
            isLoading = false
        } catch {
            print("Error loading church note: \(error)")
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
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.6))
                            .frame(width: 32, height: 32)
                    }
                    
                    Spacer()
                    
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
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
                                AsyncImage(url: URL(string: profileImageURL)) { image in
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
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Color.black.opacity(0.6))
                                    )
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.authorName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.85))
                                
                                Text("Shared \(post.timeAgo)")
                                    .font(.system(size: 13, weight: .regular))
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
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.8))
                            .lineSpacing(8)
                        
                        // Tags if available
                        if !churchNote.tags.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(churchNote.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.5))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.04))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareText = generateShareText() {
                ShareSheet(items: [shareText])
            }
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
}

// MARK: - Metadata Row Component for Elegant Read View

struct ElegantMetadataRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.4))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color.black.opacity(0.4))
                
                Text(value)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.75))
            }
            
            Spacer()
        }
    }
}

#Preview {
    ChurchNotesView()
}

// MARK: - Minimal Typography Design Components (Inspired by Gentle Systems)

// MARK: - Minimal Typography Header
struct MinimalTypographyHeader: View {
    @Binding var searchText: String
    @Binding var selectedFilter: ChurchNotesView.FilterOption
    let isScrolled: Bool
    let onNewNote: () -> Void
    @State private var isSearching = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Top navigation tabs (like "Gentle Systems | Work | About")
            HStack(spacing: 0) {
                ForEach(ChurchNotesView.FilterOption.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                        let haptic = UISelectionFeedbackGenerator()
                        haptic.selectionChanged()
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 15, weight: selectedFilter == filter ? .medium : .regular))
                            .foregroundStyle(selectedFilter == filter ? Color.black : Color.black.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                }
                
                Spacer()
                
                // New note button (minimal)
                Button(action: onNewNote) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .background(Color(red: 0.96, green: 0.96, blue: 0.96))
            
            Divider()
                .background(Color.black.opacity(0.1))
                .padding(.top, 8)
            
            // Large title (like "Work")
            if !isScrolled {
                HStack {
                    Text("Church Notes")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.black)
                        .tracking(-1)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
                
                // Subtitle description (like the work description)
                HStack {
                    Text("Capture sermon insights, reflections, and scriptures. Your notes help you grow in faith and remember what matters most.")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Search bar (minimal, appears when searching)
            if isSearching || !searchText.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.4))
                    
                    TextField("Search notes...", text: $searchText)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.black)
                        .tint(.black)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearching = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.black.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.96))
        .animation(.easeInOut(duration: 0.3), value: isScrolled)
    }
}

// MARK: - Minimal Notes List
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
            
            LazyVStack(spacing: 0) {
                ForEach(notes) { note in
                    MinimalNoteRow(
                        note: note,
                        notesService: notesService,
                        onTap: { onNoteSelected(note) }
                    )
                }
            }
            .padding(.top, 8)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            scrollOffset = value
        }
    }
}

// MARK: - Minimal Note Row (List item like in the design)
struct MinimalNoteRow: View {
    let note: ChurchNote
    @ObservedObject var notesService: ChurchNotesService
    let onTap: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    // Left side: Title and metadata
                    VStack(alignment: .leading, spacing: 8) {
                        // Note title
                        Text(note.title)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Sermon title if available
                        if let sermonTitle = note.sermonTitle, !sermonTitle.isEmpty {
                            Text(sermonTitle)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.black.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Right side: Share button and Date
                    VStack(alignment: .trailing, spacing: 8) {
                        // Share button
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.black.opacity(0.4))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Date (like "2025" in the design)
                        Text(note.date.formatted(.dateTime.year()))
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.black.opacity(0.4))
                        
                        // Favorite indicator
                        if note.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.black.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                
                // Divider
                Divider()
                    .background(Color.black.opacity(0.1))
                    .padding(.leading, 20)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                showShareSheet = true
            } label: {
                Label("Share Note", systemImage: "square.and.arrow.up")
            }
            
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
        .sheet(isPresented: $showShareSheet) {
            ChurchNoteShareOptionsSheet(note: note)
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

// MARK: - Minimal Loading View
struct MinimalLoadingView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.black)
                .scaleEffect(1.2)
            
            Text("Loading notes...")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Minimal Empty State
struct MinimalEmptyState: View {
    let hasSearch: Bool
    let filterType: ChurchNotesView.FilterOption
    let onCreateNote: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Text(emptyTitle)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.black)
                    .tracking(-0.5)
                
                Text(emptySubtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.black.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            
            if !hasSearch && filterType == .all {
                Button(action: onCreateNote) {
                    Text("Create First Note")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var emptyTitle: String {
        if hasSearch { return "No Results" }
        switch filterType {
        case .all: return "No Notes Yet"
        case .favorites: return "No Favorites"
        case .recent: return "No Recent Notes"
        case .community: return "No Community Notes"
        }
    }
    
    var emptySubtitle: String {
        if hasSearch { return "Try different keywords" }
        switch filterType {
        case .all: return "Start capturing your sermon insights and reflections"
        case .favorites: return "Star notes to save them here"
        case .recent: return "Notes from the last 7 days will appear here"
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
    @FocusState private var isContentFocused: Bool
    
    var canSave: Bool {
        !title.isEmpty && !content.isEmpty
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.96, blue: 0.96)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.black.opacity(0.6))
                    
                    Spacer()
                    
                    Text("New Note")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.black)
                    
                    Spacer()
                    
                    Button {
                        saveNote()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Save")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(canSave ? .black : .black.opacity(0.3))
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                
                Divider()
                    .background(Color.black.opacity(0.1))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title field (large)
                        TextField("Note Title", text: $title)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.black)
                            .tint(.black)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Sermon context (collapsible section)
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Sermon Context")
                                .font(.system(size: 13, weight: .medium))
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
                                        .font(.system(size: 16))
                                        .foregroundStyle(.black.opacity(0.4))
                                        .frame(width: 24)
                                    
                                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                        .labelsHidden()
                                        .tint(.black)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Scripture
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Scripture Reference")
                                .font(.system(size: 13, weight: .medium))
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
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.black.opacity(0.5))
                                    .textCase(.uppercase)
                                    .tracking(1)
                                
                                Spacer()
                                
                                // Formatting toolbar toggle
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showingToolbar.toggle()
                                    }
                                    let haptic = UIImpactFeedbackGenerator(style: .light)
                                    haptic.impactOccurred()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: showingToolbar ? "textformat" : "textformat")
                                            .font(.system(size: 12, weight: .medium))
                                        Text(showingToolbar ? "Hide" : "Format")
                                            .font(.system(size: 12, weight: .medium))
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
                            
                            // Formatting toolbar
                            if showingToolbar {
                                TextFormattingToolbar(content: $content)
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            
                            ZStack(alignment: .topLeading) {
                                if content.isEmpty {
                                    Text("Start writing...")
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundStyle(.black.opacity(0.3))
                                        .padding(.horizontal, 36)
                                        .padding(.vertical, 30)
                                }
                                
                                TextEditor(text: $content)
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(.black)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .frame(minHeight: 300)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .focused($isContentFocused)
                            }
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isContentFocused ? Color.black.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                            .animation(.easeInOut(duration: 0.2), value: isContentFocused)
                        }
                    }
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
        
        guard canSave else {
            print("⚠️ Cannot save: title=\(title.isEmpty ? "empty" : "ok"), content=\(content.isEmpty ? "empty" : "ok")")
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
            tags: tags
        )
        
        print("💾 Attempting to save note:")
        print("   Title: \(note.title)")
        print("   Content length: \(note.content.count) chars")
        print("   User ID: \(userId)")
        
        Task {
            do {
                try await notesService.createNote(note)
                await MainActor.run {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    print("✅ Note saved successfully, dismissing sheet")
                    dismiss()
                }
            } catch {
                print("❌ Save failed: \(error)")
                print("   Error details: \(error.localizedDescription)")
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
// MARK: - Minimal Text Field
struct MinimalTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.black.opacity(0.4))
                .frame(width: 24)
            
            TextField(placeholder, text: $text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.black)
                .tint(.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
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
    
    // AI Features
    @State private var noteSummary: NoteSummary?
    @State private var isGeneratingSummary = false
    @State private var scriptureReferences: [ScriptureReference] = []
    @State private var isLoadingScripture = false
    @State private var showAISection = false
    
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.96, blue: 0.96)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.black)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button {
                            Task {
                                try? await notesService.toggleFavorite(note)
                            }
                        } label: {
                            Image(systemName: note.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .foregroundStyle(.black)
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
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.96, green: 0.96, blue: 0.96))
                
                Divider()
                    .background(Color.black.opacity(0.1))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Title
                        Text(note.title)
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.black)
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
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
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
                                        .font(.system(size: 16, weight: .semibold))
                                    
                                    Text("AI Insights")
                                        .font(.system(size: 16, weight: .semibold))
                                    
                                    Spacer()
                                    
                                    Image(systemName: showAISection ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 14, weight: .medium))
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
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("AI Summary")
                                            .font(.system(size: 15, weight: .semibold))
                                        
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
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundStyle(.black.opacity(0.5))
                                                Text(summary.mainTheme)
                                                    .font(.system(size: 15, weight: .regular))
                                                    .foregroundStyle(.black)
                                            }
                                            
                                            // Key Points
                                            if !summary.keyPoints.isEmpty {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("Key Points")
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(.black.opacity(0.5))
                                                    ForEach(summary.keyPoints, id: \.self) { point in
                                                        HStack(alignment: .top, spacing: 8) {
                                                            Text("•")
                                                                .font(.system(size: 15, weight: .bold))
                                                            Text(point)
                                                                .font(.system(size: 14, weight: .regular))
                                                        }
                                                        .foregroundStyle(.black)
                                                    }
                                                }
                                            }
                                            
                                            // Action Steps
                                            if !summary.actionSteps.isEmpty {
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text("Action Steps")
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(.black.opacity(0.5))
                                                    ForEach(summary.actionSteps, id: \.self) { step in
                                                        HStack(alignment: .top, spacing: 8) {
                                                            Image(systemName: "checkmark.circle.fill")
                                                                .font(.system(size: 12))
                                                                .foregroundStyle(.green)
                                                            Text(step)
                                                                .font(.system(size: 14, weight: .regular))
                                                                .foregroundStyle(.black)
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
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(.black.opacity(0.5))
                                            .italic()
                                    }
                                }
                                
                                // Scripture Cross-References
                                if !scriptureReferences.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Image(systemName: "book.closed.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                            Text("Related Scripture")
                                                .font(.system(size: 15, weight: .semibold))
                                        }
                                        .foregroundStyle(.black.opacity(0.8))
                                        
                                        VStack(spacing: 8) {
                                            ForEach(scriptureReferences.prefix(5)) { reference in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(reference.verse)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundStyle(.blue)
                                                    Text(reference.description)
                                                        .font(.system(size: 13, weight: .regular))
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
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("Loading related scripture...")
                                            .font(.system(size: 15, weight: .semibold))
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
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(.black)
                            .lineSpacing(6)
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 40)
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [generateShareText()])
        }
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
            print("❌ Note has no share link ID")
            return
        }
        
        // Create shareable deep link
        let shareURL = "amenapp://note/\(linkId)"
        UIPasteboard.general.string = shareURL
        
        // Show toast confirmation with animation
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            showCopiedToast = true
        }
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
        
        print("✅ Note link copied: \(shareURL)")
        
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
            do {
                let summary = try await AINoteSummarizationService.shared.summarizeNote(content: note.content)
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        noteSummary = summary
                        isGeneratingSummary = false
                    }
                }
                
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
                
                print("✅ AI Summary generated successfully")
            } catch {
                print("❌ Failed to generate summary: \(error)")
                await MainActor.run {
                    isGeneratingSummary = false
                }
            }
        }
    }
    
    private func loadScriptureReferences() {
        // Extract verse references from note content and scripture field
        var allText = note.content
        if let scripture = note.scripture {
            allText += " " + scripture
        }
        
        let extractedVerses = AIScriptureCrossRefService.shared.extractVerseReferences(from: allText)
        
        guard !extractedVerses.isEmpty else {
            print("ℹ️ No scripture references found in note")
            return
        }
        
        isLoadingScripture = true
        
        Task {
            do {
                // Get references for the first verse found
                if let firstVerse = extractedVerses.first {
                    let references = try await AIScriptureCrossRefService.shared.findRelatedVerses(for: firstVerse)
                    
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            scriptureReferences = references
                            isLoadingScripture = false
                        }
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    
                    print("✅ Found \(references.count) related scripture references")
                }
            } catch {
                print("❌ Failed to load scripture references: \(error)")
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
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black.opacity(0.5))
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Text Formatting Toolbar
struct TextFormattingToolbar: View {
    @Binding var content: String
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
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            selectedButton = option
        }
        
        // Haptic feedback
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        
        // Reset after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                selectedButton = nil
            }
        }
        
        // Apply formatting to content
        if option == .bulletList || option == .numberedList || option == .heading || option == .quote {
            // Line-based formatting
            if content.isEmpty {
                content = option.prefix
            } else if let lastLine = content.components(separatedBy: "\n").last, !lastLine.isEmpty {
                content += "\n" + option.prefix
            } else {
                content += option.prefix
            }
        } else {
            // Wrap formatting (bold, italic, etc.)
            if content.isEmpty {
                content = option.prefix + option.suffix
            } else {
                // Add formatting at the end
                content += "\n" + option.prefix + option.suffix
            }
        }
    }
}

struct FormattingButton: View {
    let option: TextFormattingToolbar.FormattingOption
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: option.icon)
                .font(.system(size: 16, weight: .medium))
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

