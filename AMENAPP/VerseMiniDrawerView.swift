//
//  VerseMiniDrawerView.swift
//  AMENAPP
//
//  Compact mini verse picker - Stage 1 of two-stage scripture attach flow
//  28-40% screen height, smart suggestions, quick search, expand affordance
//

import SwiftUI

struct VerseMiniDrawerView: View {
    @Binding var searchText: String
    @Binding var selectedVerse: BibleVerse?
    @Binding var translation: BibleTranslation
    @ObservedObject var searchEngine: VerseSmartSearchEngine
    @ObservedObject var baseViewModel: AttachVerseViewModel
    
    @FocusState private var isSearchFocused: Bool
    
    let onExpand: () -> Void
    let onAttach: () -> Void
    let onDismiss: () -> Void
    
    @State private var appear = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            GlassDragHandle()
                .opacity(appear ? 1 : 0)
            
            // Header
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .opacity(appear ? 1 : 0)
            
            // Search capsule
            VerseSearchCapsule(
                text: $searchText,
                isFocused: $isSearchFocused,
                onSubmit: performSearch,
                onClear: clearSearch
            )
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 20)
            
            // Quick suggestion chips
            suggestionChipsRow
                .padding(.top, 12)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 15)
            
            // Quick results or popular picks
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    if searchEngine.isSearching {
                        loadingView
                    } else if !searchEngine.results.isEmpty {
                        quickResults
                    } else if !searchText.isEmpty {
                        emptySearchState
                    } else {
                        popularVerses
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .opacity(appear ? 1 : 0)
            
            // Expand button
            expandButton
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)
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
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.82))) {
                appear = true
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            GlassIconOrb(icon: "book.closed.fill", size: 40, iconSize: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Attach a Verse")
                    .font(.systemScaled(18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                
                Text("Search by reference, topic, or phrase")
                    .font(.systemScaled(12))
                    .foregroundStyle(Color.secondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.systemScaled(14, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(VerseGlassTokens.glassFill)
                    }
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Suggestion Chips
    
    private var suggestionChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VerseSuggestion.topical.prefix(6)) { suggestion in
                    VerseSuggestionChip(suggestion: suggestion) {
                        searchText = suggestion.query
                        performSearch()
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Quick Results (Top 4)
    
    private var quickResults: some View {
        ForEach(Array(searchEngine.results.prefix(4))) { result in
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
    
    // MARK: - Popular Verses (Default)
    
    private var popularVerses: some View {
        Group {
            HStack {
                Text("Popular Verses")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
            .padding(.bottom, 4)
            
            ForEach(searchEngine.getPopularVerses(translation: translation).prefix(4)) { result in
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
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(VerseGlassTokens.accentPrimary.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(searchEngine.isSearching ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: searchEngine.isSearching
                        )
                }
            }
            .padding(.top, 20)
            
            Text("Searching scriptures…")
                .font(.systemScaled(13))
                .foregroundStyle(Color.secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(28))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .padding(.top, 20)
            
            Text("No verses found")
                .font(.systemScaled(14, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.6))
            
            Text("Try a different search or expand for more options")
                .font(.systemScaled(12))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Expand Button
    
    private var expandButton: some View {
        Button(action: onExpand) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.systemScaled(13, weight: .medium))
                
                Text("Expand for full search")
                    .font(.systemScaled(14, weight: .semibold))
            }
            .foregroundStyle(VerseGlassTokens.accentPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                    .fill(VerseGlassTokens.accentSubtle)
                    .overlay {
                        RoundedRectangle(cornerRadius: VerseGlassTokens.radiusMedium, style: .continuous)
                            .strokeBorder(VerseGlassTokens.accentPrimary.opacity(0.3), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
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
}
