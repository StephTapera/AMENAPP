// CommunityNotesBrowseView.swift
// AMENAPP — Community Notes category grid + search
//
// Structural pattern: Apple News Browse (2-column colored tile grid + search bar).
// AMEN identity: amenGold search icon, "Ask Berean or search notes" placeholder,
// faith-native category names, faith-native empty state copy.
// Reuses AMENGlassCard, ChurchBadgeChip, CommunityNoteCardView from this module.

import SwiftUI

@available(iOS 26.0, *)
@MainActor
struct CommunityNotesBrowseView: View {

    @State private var searchQuery: String = ""
    @State private var searchResults: [CommunityNotesSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var selectedCategory: NoteCategory? = nil
    @State private var searchError: String? = nil
    @StateObject private var service = CommunityNotesService.shared

    @FocusState private var searchFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heading
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    if searchQuery.isEmpty {
                        categoryGrid
                    } else {
                        searchResultsSection
                    }
                }
                .padding(.bottom, 40)
            }
            .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
            .navigationDestination(item: $selectedCategory) { cat in
                CommunityNotesFeedView(initialCategory: cat)
                    .navigationTitle(cat.displayName)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Heading

    private var heading: some View {
        Text("Browse Notes")
            .font(.largeTitle.bold())
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)

            ZStack(alignment: .leading) {
                if searchQuery.isEmpty {
                    Text("Ask Berean or search notes")
                        .font(.subheadline)
                        .foregroundStyle(AmenTheme.Colors.textPlaceholder)
                        .allowsHitTesting(false)
                }
                TextField("", text: $searchQuery)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { triggerSearch() }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            if !searchQuery.isEmpty {
                if isSearching {
                    ProgressView()
                        .tint(AmenTheme.Colors.amenGold)
                        .scaleEffect(0.85)
                } else {
                    Button {
                        searchQuery = ""
                        searchResults = []
                        searchError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AmenTheme.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.75)
        }
        .shadow(color: AmenTheme.Colors.shadowCard, radius: 8, y: 3)
        .accessibilityLabel("Search community notes or ask Berean")
    }

    // MARK: - Category Grid

    private var categoryGrid: some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(NoteCategory.allCases) { cat in
                categoryTile(cat)
            }
        }
        .padding(.horizontal, 20)
    }

    private func categoryTile(_ cat: NoteCategory) -> some View {
        Button {
            selectedCategory = cat
        } label: {
            AMENGlassCard(
                width: tileDimension,
                height: 100,
                tintColor: cat.tint
            ) {
                VStack(spacing: 8) {
                    Image(systemName: cat.icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(cat.tint)
                    Text(cat.displayName)
                        .font(.headline.bold())
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.80)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cat.displayName)
        .accessibilityHint("View all \(cat.displayName) notes")
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsSection: some View {
        if isSearching {
            searchingPlaceholder
        } else if let err = searchError {
            searchErrorView(message: err)
        } else if searchResults.isEmpty && !searchQuery.isEmpty {
            emptySearchState
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                    NavigationLink(destination: searchResultDetailPlaceholder(result)) {
                        CommunityNoteCardView(searchResult: result)
                            .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)
                    .staggeredReveal(index: index, baseDelay: 0.04, maxDelay: 0.20)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var searchingPlaceholder: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.shimmerBase)
                    .frame(height: 88)
                    .padding(.horizontal, 20)
                    .amenSkeleton()
            }
        }
        .padding(.top, 8)
    }

    private func searchErrorView(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(AmenTheme.Colors.amenGold)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { triggerSearch() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.amenGold)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.largeTitle)
                .foregroundStyle(AmenTheme.Colors.amenGold.opacity(0.55))
            Text("Be the first to share what God is speaking to you")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
    }

    // MARK: - Search Result Detail Placeholder

    private func searchResultDetailPlaceholder(_ result: CommunityNotesSearchResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(result.title)
                    .font(.title2.bold())
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 20)
                Text(result.excerpt)
                    .font(.body)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.horizontal, 20)
            }
            .padding(.top, 20)
        }
        .navigationTitle(result.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .background(AmenTheme.Colors.backgroundPrimary.ignoresSafeArea())
    }

    // MARK: - Helpers

    private var tileDimension: CGFloat {
        let screen = UIScreen.main.bounds.width
        // 20 leading + 12 gap + 20 trailing = 52 total horizontal insets
        return (screen - 52) / 2
    }

    private func triggerSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searchFocused = false
        Task { await performSearch() }
    }

    private func performSearch() async {
        isSearching = true
        searchError = nil
        do {
            searchResults = try await service.search(query: searchQuery, mode: "hybrid")
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 26.0, *)
#Preview("CommunityNotesBrowseView") {
    CommunityNotesBrowseView()
}
#endif
