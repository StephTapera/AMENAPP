//
//  VerseFullDrawerView.swift
//  AMENAPP
//
//  Full premium scripture drawer - Stage 2 of two-stage attach flow
//  Comprehensive search, filter tabs, sticky header, sticky footer
//

import SwiftUI

struct VerseFullDrawerView: View {
    @Binding var searchText: String
    @Binding var selectedVerse: BibleVerse?
    @Binding var translation: LocalBibleTranslation
    @ObservedObject var searchEngine: VerseSmartSearchEngine
    @ObservedObject var baseViewModel: AttachVerseViewModel
    
    @FocusState private var isSearchFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    
    let onAttach: () -> Void
    let onDismiss: () -> Void
    
    @State private var appear = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Sticky header
                stickyHeader
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            }
                            .opacity(scrollOffset > 20 ? 1 : 0)
                            .animation(Motion.adaptive(.easeOut(duration: 0.2)), value: scrollOffset)
                    }
                    .zIndex(10)
                
                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Filter mode tabs
                        filterTabs
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        
                        // Results
                        resultsSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, selectedVerse != nil ? 100 : 40)
                    }
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .named("scroll")).minY) { _, newValue in
                                    scrollOffset = -newValue
                                }
                        }
                    }
                }
                .coordinateSpace(name: "scroll")
            }
            
            // Sticky footer (when verse selected)
            if let verse = selectedVerse {
                SelectedVerseFooter(
                    verse: verse,
                    onAttach: onAttach,
                    onClear: {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            selectedVerse = nil
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: VerseGlassTokens.radiusXL, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: VerseGlassTokens.radiusXL, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [VerseGlassTokens.glassHighlight, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .scaleEffect(appear ? 1.0 : 0.96)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.82))) {
                appear = true
            }
            
            // Perform search if text exists
            if !searchText.isEmpty {
                performSearch()
            }
        }
    }
    
    // MARK: - Sticky Header
    
    private var stickyHeader: some View {
        VStack(spacing: 0) {
            // Drag handle
            GlassDragHandle()
            
            // Title row
            HStack(spacing: 12) {
                GlassIconOrb(icon: "book.closed.fill", size: 44, iconSize: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attach a Verse")
                        .font(.systemScaled(19, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    
                    Text("Search by reference, topic, person, phrase, or date")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 36, height: 36)
                        .background {
                            Circle()
                                .fill(VerseGlassTokens.glassFill)
                                .overlay {
                                    Circle()
                                        .strokeBorder(VerseGlassTokens.glassStroke, lineWidth: 0.5)
                                }
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            // Search capsule
            VerseSearchCapsule(
                text: $searchText,
                isFocused: $isSearchFocused,
                onSubmit: performSearch,
                onClear: clearSearch
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Translation picker
            translationPicker
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
    }
    
    // MARK: - Translation Picker
    
    private var translationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LocalBibleTranslation.allCases, id: \.self) { trans in
                    VerseGlassCapsuleButton(
                        trans.rawValue,
                        isSelected: translation == trans
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            translation = trans
                        }
                        if !searchText.isEmpty {
                            performSearch()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Filter Tabs
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(VerseSearchMode.allCases) { mode in
                    VerseGlassCapsuleButton(
                        mode.rawValue,
                        icon: mode.icon,
                        isSelected: searchEngine.searchMode == mode
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            searchEngine.searchMode = mode
                        }
                        applyFilter(mode)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Results Section
    
    @ViewBuilder
    private var resultsSection: some View {
        if searchEngine.isSearching {
            loadingView
        } else if !searchEngine.results.isEmpty {
            resultsGrid
        } else if !searchText.isEmpty {
            emptySearchState
        } else {
            defaultSuggestionsView
        }
    }
    
    private var resultsGrid: some View {
        LazyVStack(spacing: 12) {
            ForEach(searchEngine.results) { result in
                VerseResultCard(
                    result: result,
                    isSelected: selectedVerse?.id == result.verse.id
                ) {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                        if selectedVerse?.id == result.verse.id {
                            selectedVerse = nil
                        } else {
                            selectedVerse = result.verse
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(VerseGlassTokens.accentPrimary.opacity(0.5))
                        .frame(width: 9, height: 9)
                        .scaleEffect(searchEngine.isSearching ? 1.4 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: searchEngine.isSearching
                        )
                }
            }
            .padding(.top, 40)
            
            Text("Searching scriptures…")
                .font(.systemScaled(14))
                .foregroundStyle(Color.secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(36))
                .foregroundStyle(VerseGlassTokens.accentPrimary.opacity(0.4))
                .padding(.top, 40)
            
            Text("No verses found")
                .font(.systemScaled(16, weight: .semibold))
                .foregroundStyle(Color.primary)
            
            Text("Try a different keyword, topic, or Bible reference")
                .font(.systemScaled(13))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            
            // Suggested alternatives
            VStack(spacing: 10) {
                Text("Try these searches:")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .padding(.top, 12)
                
                HStack(spacing: 8) {
                    ForEach(["hope", "strength", "John 3:16"].prefix(3), id: \.self) { suggestion in
                        Button {
                            searchText = suggestion
                            performSearch()
                        } label: {
                            Text(suggestion)
                                .font(.systemScaled(12, weight: .medium))
                                .foregroundStyle(VerseGlassTokens.accentPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule()
                                        .fill(VerseGlassTokens.accentSubtle)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 30)
    }
    
    // MARK: - Default Suggestions
    
    private var defaultSuggestionsView: some View {
        VStack(spacing: 20) {
            // Popular section
            popularSection
            
            // Topic suggestions
            topicSuggestionsSection
        }
    }
    
    private var popularSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Popular Verses")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            
            LazyVStack(spacing: 10) {
                ForEach(searchEngine.getPopularVerses(translation: translation).prefix(6)) { result in
                    VerseResultCard(
                        result: result,
                        isSelected: selectedVerse?.id == result.verse.id
                    ) {
                        withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                            if selectedVerse?.id == result.verse.id {
                                selectedVerse = nil
                            } else {
                                selectedVerse = result.verse
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var topicSuggestionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Browse by Topic")
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(Array(VerseTopic.allCases.prefix(12)), id: \.self) { topic in
                    Button {
                        searchText = topic.rawValue.lowercased()
                        performSearch()
                    } label: {
                        Text(topic.rawValue)
                            .font(.systemScaled(13, weight: .medium))
                            .foregroundStyle(VerseGlassTokens.accentPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background {
                                RoundedRectangle(cornerRadius: VerseGlassTokens.radiusSmall, style: .continuous)
                                    .fill(VerseGlassTokens.accentSubtle)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: VerseGlassTokens.radiusSmall, style: .continuous)
                                            .strokeBorder(VerseGlassTokens.accentPrimary.opacity(0.2), lineWidth: 0.5)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func performSearch() {
        Task {
            await searchEngine.search(query: searchText, translation: translation, baseViewModel: baseViewModel)
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchEngine.results = []
        selectedVerse = nil
    }
    
    private func applyFilter(_ mode: VerseSearchMode) {
        // Apply mode-specific filtering or suggestions
        switch mode {
        case .all:
            if !searchText.isEmpty {
                performSearch()
            }
        case .topics:
            // Could show topic browser
            break
        case .people:
            // Could show people browser
            break
        case .seasonal:
            // Could show seasonal/calendar browser
            break
        case .recent:
            // Could load recent searches
            break
        case .saved:
            // Could load saved verses
            break
        }
    }
}
