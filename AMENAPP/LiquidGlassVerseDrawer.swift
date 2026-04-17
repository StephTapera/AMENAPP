//
//  LiquidGlassVerseDrawer.swift
//  AMENAPP
//
//  Liquid Glass redesign for "Attach a Verse" flow in CreatePostView
//  Two-stage presentation: Mini drawer (28-40%) → Full drawer (expandable)
//  Smarter search: direct reference, topic, person, date, natural language
//

import SwiftUI
import Combine

// MARK: - Search Intent Detection

enum VerseSearchIntent {
    case directReference    // "John 3:16", "Phil 4:13"
    case topic             // "peace", "hope", "anxiety"
    case person            // "David", "Paul", "Moses"
    case date              // "Christmas", "Easter", "Sunday"
    case naturalLanguage   // "verse about grief", "what does bible say about peace"
    
    static func detect(_ query: String) -> VerseSearchIntent {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Direct reference pattern
        let refPattern = try? NSRegularExpression(pattern: #"^[1-3]?\s?[A-Za-z]+\.?\s+\d+:\d+"#)
        if let regex = refPattern, regex.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) != nil {
            return .directReference
        }
        
        // Natural language pattern
        if q.contains("verse about") || q.contains("bible say") || q.contains("scripture about") {
            return .naturalLanguage
        }
        
        // Person-based
        let biblicalPeople = ["david", "paul", "moses", "peter", "john", "jesus", "abraham", "joshua", "daniel", "mary"]
        if biblicalPeople.contains(where: { q.contains($0) }) {
            return .person
        }
        
        // Date/Context
        let dateContexts = ["christmas", "easter", "sunday", "morning", "evening", "advent", "lent"]
        if dateContexts.contains(where: { q.contains($0) }) {
            return .date
        }
        
        // Default to topic
        return .topic
    }
}

// MARK: - Verse Search Service

@MainActor
class LiquidGlassVerseSearchService: ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [BibleVerse] = []
    @Published var isLoading = false
    @Published var searchIntent: VerseSearchIntent = .topic
    @Published var selectedTranslation: BibleTranslation = .NIV
    
    private var searchTask: Task<Void, Never>?
    
    // Smart suggestions based on intent
    var contextualSuggestions: [String] {
        switch searchIntent {
        case .directReference:
            return ["John 3:16", "Philippians 4:13", "Psalm 23:1", "Romans 8:28"]
        case .topic:
            return ["peace", "hope", "strength", "love", "faith", "joy"]
        case .person:
            return ["David", "Paul", "Moses", "Peter", "Joshua", "Daniel"]
        case .date:
            return ["Christmas", "Easter", "Sunday morning", "Advent"]
        case .naturalLanguage:
            return ["verse about peace", "verse about grief", "verse about waiting"]
        }
    }
    
    func search() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            return
        }
        
        searchTask?.cancel()
        isLoading = true
        searchIntent = VerseSearchIntent.detect(query)
        
        searchTask = Task {
            // 400ms debounce for natural typing
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            
            var apiResults: [BibleVerse] = []
            
            do {
                let version = selectedTranslation.apiVersion
                
                switch searchIntent {
                case .directReference:
                    // Direct verse fetch
                    let passage = try await YouVersionBibleService.shared.fetchVerse(
                        reference: query, version: version
                    )
                    apiResults = [BibleVerse(
                        reference: passage.reference,
                        text: passage.text,
                        translation: selectedTranslation.rawValue
                    )]
                    
                case .naturalLanguage:
                    // Extract topic from natural language
                    let extractedTopic = extractTopicFromNaturalLanguage(query)
                    let passages = try await YouVersionBibleService.shared.searchVerses(
                        query: extractedTopic, version: version, limit: 12
                    )
                    apiResults = passages.map { BibleVerse(
                        reference: $0.reference,
                        text: $0.text,
                        translation: selectedTranslation.rawValue
                    )}
                    
                default:
                    // Keyword search for topic, person, date
                    let passages = try await YouVersionBibleService.shared.searchVerses(
                        query: query, version: version, limit: 12
                    )
                    apiResults = passages.map { BibleVerse(
                        reference: $0.reference,
                        text: $0.text,
                        translation: selectedTranslation.rawValue
                    )}
                }
            } catch {
                dlog("⚠️ [LiquidGlassVerse] API failed, using local fallback")
                apiResults = LocalVerseLibrary.search(query, translation: selectedTranslation)
            }
            
            guard !Task.isCancelled else { return }
            results = apiResults
            isLoading = false
        }
    }
    
    private func extractTopicFromNaturalLanguage(_ query: String) -> String {
        let q = query.lowercased()
        // Remove common phrase patterns
        var topic = q
            .replacingOccurrences(of: "verse about ", with: "")
            .replacingOccurrences(of: "what does bible say about ", with: "")
            .replacingOccurrences(of: "what does the bible say about ", with: "")
            .replacingOccurrences(of: "scripture about ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return topic
    }
}

// MARK: - Mini Drawer View (Stage 1: 28-40% height)

struct LiquidGlassVerseMiniDrawerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = LiquidGlassVerseSearchService()
    @State private var selectedVerse: BibleVerse? = nil
    @FocusState private var searchFocused: Bool
    @State private var appeared = false
    
    var onAttach: (BibleVerse) -> Void
    var onExpand: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // Header
            miniHeader
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            
            // Search capsule
            searchCapsule
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            
            // Contextual suggestion chips
            suggestionChips
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            
            // Quick results (3-4 verses max)
            if searchService.isLoading {
                loadingIndicator
                    .padding(.top, 20)
            } else if !searchService.results.isEmpty {
                quickResults
            } else if searchService.searchQuery.isEmpty {
                emptyPrompt
            } else {
                noResults
            }
            
            Spacer(minLength: 8)
            
            // Footer with "See more" or "Attach" button
            miniFooter
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .background(liquidGlassBackground)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 30)
        .onAppear {
            withAnimation(Motion.adaptive(.spring(response: 0.45, dampingFraction: 0.82))) {
                appeared = true
            }
        }
    }
    
    // MARK: - Drag Handle
    
    private var dragHandle: some View {
        Capsule()
            .fill(Color.black.opacity(0.12))
            .frame(width: 36, height: 4)
    }
    
    // MARK: - Mini Header
    
    private var miniHeader: some View {
        HStack {
            Text("Attach a Verse")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                    dismiss()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .background(Circle().fill(.ultraThinMaterial))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(SubtlePressStyle())
        }
    }
    
    // MARK: - Search Capsule
    
    private var searchCapsule: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: searchFocused ? .semibold : .regular))
                .foregroundStyle(searchFocused ? Color.black.opacity(0.75) : Color.black.opacity(0.35))
            
            TextField("John 3:16 · peace · David · Christmas", text: $searchService.searchQuery)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { searchService.search() }
                .onChange(of: searchService.searchQuery) { _, _ in searchService.search() }
            
            if !searchService.searchQuery.isEmpty {
                Button {
                    searchService.searchQuery = ""
                    searchService.results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.6))
                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(
                            searchFocused ? Color.black.opacity(0.15) : Color.black.opacity(0.06),
                            lineWidth: searchFocused ? 1 : 0.5
                        )
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        )
        .animation(.easeOut(duration: 0.2), value: searchFocused)
    }
    
    // MARK: - Suggestion Chips
    
    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searchService.contextualSuggestions, id: \.self) { suggestion in
                    Button {
                        searchService.searchQuery = suggestion
                        searchService.search()
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.5))
                                    .background(Capsule().fill(.ultraThinMaterial))
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                            )
                    }
                    .buttonStyle(SubtlePressStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Quick Results (3-4 max)
    
    private var quickResults: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(Array(searchService.results.prefix(4)), id: \.id) { verse in
                    LiquidGlassVerseResultCard(
                        verse: verse,
                        isSelected: selectedVerse?.id == verse.id,
                        onTap: {
                            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                                selectedVerse = verse
                            }
                        }
                    )
                }
                
                // Show more button if there are additional results
                if searchService.results.count > 4 {
                    Button {
                        onExpand()
                    } label: {
                        HStack(spacing: 6) {
                            Text("See \(searchService.results.count - 4) more results")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.5))
                                .background(Capsule().fill(.ultraThinMaterial))
                                .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                        )
                    }
                    .buttonStyle(SubtlePressStyle())
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Loading Indicator
    
    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: 7, height: 7)
                    .scaleEffect(searchService.isLoading ? 1.2 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: searchService.isLoading
                    )
            }
        }
    }
    
    // MARK: - Empty Prompt
    
    private var emptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Search by reference, topic, or person")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
    }
    
    // MARK: - No Results
    
    private var noResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No verses found")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Try a different search")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 30)
    }
    
    // MARK: - Mini Footer
    
    private var miniFooter: some View {
        HStack(spacing: 12) {
            // Expand button
            if !searchService.results.isEmpty && searchService.results.count > 4 {
                Button {
                    onExpand()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13))
                        Text("Expand")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.6))
                            .background(Capsule().fill(.ultraThinMaterial))
                            .overlay(Capsule().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    )
                }
                .buttonStyle(SubtlePressStyle())
            }
            
            Spacer()
            
            // Attach button
            Button {
                if let verse = selectedVerse {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        onAttach(verse)
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Attach")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(selectedVerse != nil ? Color.white : Color.black.opacity(0.35))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(selectedVerse != nil ? Color.black.opacity(0.85) : Color.white.opacity(0.4))
                        .background(Capsule().fill(.ultraThinMaterial))
                        .shadow(
                            color: selectedVerse != nil ? .black.opacity(0.15) : .black.opacity(0.04),
                            radius: selectedVerse != nil ? 8 : 4,
                            y: selectedVerse != nil ? 3 : 2
                        )
                )
            }
            .buttonStyle(SubtlePressStyle())
            .disabled(selectedVerse == nil)
            .animation(.easeOut(duration: 0.2), value: selectedVerse != nil)
        }
    }
    
    // MARK: - Liquid Glass Background
    
    private var liquidGlassBackground: some View {
        ZStack {
            Color(.systemBackground)
            
            // Top-to-bottom gradient for depth
            LinearGradient(
                colors: [
                    Color.white.opacity(0.3),
                    Color.white.opacity(0.1),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Verse Result Card

struct LiquidGlassVerseResultCard: View {
    let verse: BibleVerse
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Reference
                Text(verse.reference)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Color.black.opacity(0.65))
                
                // Text (truncated to 2 lines in mini view)
                Text(verse.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.5))
                    .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? Color.black.opacity(0.12) : Color.black.opacity(0.06),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
                    .shadow(
                        color: isSelected ? .black.opacity(0.08) : .black.opacity(0.03),
                        radius: isSelected ? 8 : 4,
                        y: isSelected ? 3 : 2
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Full Drawer View (Stage 2: Expandable)

struct LiquidGlassVerseFullDrawerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchService = LiquidGlassVerseSearchService()
    @State private var selectedVerse: BibleVerse? = nil
    @State private var selectedFilter: VerseFilter = .all
    @FocusState private var searchFocused: Bool
    @State private var appeared = false
    
    var onAttach: (BibleVerse) -> Void
    
    enum VerseFilter: String, CaseIterable {
        case all = "All"
        case psalms = "Psalms"
        case gospels = "Gospels"
        case epistles = "Epistles"
        case oldTestament = "Old Testament"
        case newTestament = "New Testament"
        
        func matches(_ verse: BibleVerse) -> Bool {
            switch self {
            case .all:
                return true
            case .psalms:
                return verse.reference.lowercased().contains("psalm")
            case .gospels:
                let gospels = ["matthew", "mark", "luke", "john"]
                return gospels.contains(where: { verse.reference.lowercased().contains($0) })
            case .epistles:
                let epistles = ["romans", "corinthians", "galatians", "ephesians", "philippians", "colossians", "thessalonians", "timothy", "titus", "philemon", "hebrews", "james", "peter", "john", "jude"]
                return epistles.contains(where: { verse.reference.lowercased().contains($0) })
            case .oldTestament:
                // Simplified: check if NOT in New Testament books
                let ntBooks = ["matthew", "mark", "luke", "john", "acts", "romans", "corinthians", "galatians", "ephesians", "philippians", "colossians", "thessalonians", "timothy", "titus", "philemon", "hebrews", "james", "peter", "jude", "revelation"]
                return !ntBooks.contains(where: { verse.reference.lowercased().contains($0) })
            case .newTestament:
                let ntBooks = ["matthew", "mark", "luke", "john", "acts", "romans", "corinthians", "galatians", "ephesians", "philippians", "colossians", "thessalonians", "timothy", "titus", "philemon", "hebrews", "james", "peter", "jude", "revelation"]
                return ntBooks.contains(where: { verse.reference.lowercased().contains($0) })
            }
        }
    }
    
    var filteredResults: [BibleVerse] {
        searchService.results.filter { selectedFilter.matches($0) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom header
                fullHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                
                // Search capsule
                searchCapsule
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                
                // Translation picker
                translationPicker
                    .padding(.bottom, 12)
                
                // Filter tabs
                filterTabs
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                
                // Suggestion chips (contextual)
                if searchService.searchQuery.isEmpty {
                    suggestionChips
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                
                // Results list
                if searchService.isLoading {
                    loadingIndicator
                        .frame(maxHeight: .infinity)
                } else if !filteredResults.isEmpty {
                    fullResults
                } else if searchService.searchQuery.isEmpty {
                    emptyPrompt
                        .frame(maxHeight: .infinity)
                } else {
                    noResults
                        .frame(maxHeight: .infinity)
                }
                
                // Selected verse footer
                if selectedVerse != nil {
                    selectedVerseFooter
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            Rectangle()
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.06), radius: 12, y: -4)
                        )
                }
            }
            .background(Color(.systemBackground))
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 40)
            .onAppear {
                withAnimation(Motion.adaptive(.spring(response: 0.5, dampingFraction: 0.85))) {
                    appeared = true
                }
            }
        }
    }
    
    // MARK: - Full Header
    
    private var fullHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Attach a Verse")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Search across all scripture")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.75))) {
                    dismiss()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .background(Circle().fill(.ultraThinMaterial))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(SubtlePressStyle())
        }
    }
    
    // MARK: - Search Capsule
    
    private var searchCapsule: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: searchFocused ? .semibold : .regular))
                .foregroundStyle(searchFocused ? Color.black.opacity(0.75) : Color.black.opacity(0.35))
            
            TextField("Search reference, topic, person, or ask a question...", text: $searchService.searchQuery)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { searchService.search() }
                .onChange(of: searchService.searchQuery) { _, _ in searchService.search() }
            
            if !searchService.searchQuery.isEmpty {
                Button {
                    searchService.searchQuery = ""
                    searchService.results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.6))
                .background(RoundedRectangle(cornerRadius: 22).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(
                            searchFocused ? Color.black.opacity(0.15) : Color.black.opacity(0.06),
                            lineWidth: searchFocused ? 1 : 0.5
                        )
                )
                .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
        )
        .animation(.easeOut(duration: 0.2), value: searchFocused)
    }
    
    // MARK: - Translation Picker
    
    private var translationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BibleTranslation.allCases, id: \.self) { translation in
                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                            searchService.selectedTranslation = translation
                        }
                        if !searchService.searchQuery.isEmpty {
                            searchService.search()
                        }
                    } label: {
                        Text(translation.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(
                                searchService.selectedTranslation == translation
                                ? Color.white
                                : Color.black.opacity(0.65)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(
                                        searchService.selectedTranslation == translation
                                        ? Color.black.opacity(0.85)
                                        : Color.white.opacity(0.5)
                                    )
                                    .background(Capsule().fill(.ultraThinMaterial))
                                    .overlay(
                                        Capsule().strokeBorder(
                                            searchService.selectedTranslation == translation
                                            ? Color.clear
                                            : Color.black.opacity(0.06),
                                            lineWidth: 0.5
                                        )
                                    )
                                    .shadow(
                                        color: searchService.selectedTranslation == translation
                                        ? .black.opacity(0.12)
                                        : .black.opacity(0.03),
                                        radius: searchService.selectedTranslation == translation ? 6 : 3,
                                        y: searchService.selectedTranslation == translation ? 3 : 2
                                    )
                            )
                    }
                    .buttonStyle(SubtlePressStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Filter Tabs
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VerseFilter.allCases, id: \.self) { filter in
                    let isSelected = selectedFilter == filter
                    let foregroundColor = isSelected ? Color.black.opacity(0.85) : Color.black.opacity(0.5)
                    let capsuleFill = isSelected ? Color.white.opacity(0.85) : Color.clear
                    let capsuleStroke = isSelected ? Color.black.opacity(0.08) : Color.clear
                    let capsuleShadow = isSelected ? Color.black.opacity(0.06) : Color.clear

                    Button {
                        withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(foregroundColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(capsuleFill)
                                    .background(
                                        Group {
                                            if isSelected {
                                                Capsule().fill(.ultraThinMaterial)
                                            }
                                        }
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(
                                            capsuleStroke,
                                            lineWidth: isSelected ? 0.5 : 0
                                        )
                                    )
                                    .shadow(
                                        color: capsuleShadow,
                                        radius: 6,
                                        y: 2
                                    )
                            )
                    }
                    .buttonStyle(SubtlePressStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Suggestion Chips
    
    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(searchService.contextualSuggestions, id: \.self) { suggestion in
                    Button {
                        searchService.searchQuery = suggestion
                        searchService.search()
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.5))
                                    .background(Capsule().fill(.ultraThinMaterial))
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                            )
                    }
                    .buttonStyle(SubtlePressStyle())
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }
    
    // MARK: - Full Results
    
    private var fullResults: some View {
        ScrollView(showsIndicators: true) {
            LazyVStack(spacing: 12) {
                ForEach(filteredResults, id: \.id) { verse in
                    FullLiquidGlassVerseResultCard(
                        verse: verse,
                        isSelected: selectedVerse?.id == verse.id,
                        onTap: {
                            withAnimation(Motion.adaptive(.spring(response: 0.25, dampingFraction: 0.75))) {
                                selectedVerse = verse
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, selectedVerse != nil ? 100 : 20)
        }
    }
    
    // MARK: - Loading Indicator
    
    private var loadingIndicator: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: 8, height: 8)
                        .scaleEffect(searchService.isLoading ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: searchService.isLoading
                        )
                }
            }
            Text("Searching scriptures...")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Empty Prompt
    
    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.04))
                    .frame(width: 80, height: 80)
                Image(systemName: "book.closed")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text("Search for a verse")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Try a reference, topic, person, or question")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - No Results
    
    private var noResults: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.04))
                    .frame(width: 72, height: 72)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text("No verses found")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Try a different search or filter")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // MARK: - Selected Verse Footer
    
    private var selectedVerseFooter: some View {
        HStack(spacing: 12) {
            // Verse preview
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedVerse?.reference ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(selectedVerse?.text ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Attach button
            Button {
                if let verse = selectedVerse {
                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                        onAttach(verse)
                        dismiss()
                    }
                }
            } label: {
                Text("Attach")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                    )
            }
            .buttonStyle(SubtlePressStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Full Verse Result Card

struct FullLiquidGlassVerseResultCard: View {
    let verse: BibleVerse
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Reference with selection indicator
                HStack {
                    Text(verse.reference)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Color.black.opacity(0.65))
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                // Full text (no truncation in full view)
                Text(verse.text)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                
                // Translation
                Text(verse.translation)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
                    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Color.black.opacity(0.12) : Color.black.opacity(0.06),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    )
                    .shadow(
                        color: isSelected ? .black.opacity(0.1) : .black.opacity(0.04),
                        radius: isSelected ? 10 : 6,
                        y: isSelected ? 4 : 2
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Subtle Press Style

private struct SubtlePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
