// DiscoverySearchView.swift
// AMEN Connect Discovery Engine — Wave 3, Lane M
// Search destination: pre-typing (suggested + browse) → post-typing (Algolia instant results)
// All results safety-stamped. Staggered entrance animation with reduce-motion fallback.

import SwiftUI

struct DiscoverySearchView: View {
    @Bindable var viewModel: ConnectDiscoveryViewModel
    @State private var query = ""
    @State private var showPreview: DiscoveryCard? = nil
    @FocusState private var isSearchFocused: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        searchContent
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, placement: .navigationBarDrawer, prompt: "Search communities, churches, events…")
            .focused($isSearchFocused)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                Task {
                    if newValue.isEmpty {
                        viewModel.clearSearch()
                        await viewModel.search(query: "")
                    } else {
                        await viewModel.search(query: newValue)
                    }
                }
            }
            .task {
                // Pre-load suggested on appear
                await viewModel.search(query: "")
            }
        }
        .sheet(item: $showPreview) { card in
            DiscoveryPreviewSheet(card: card)
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var searchContent: some View {
        if query.isEmpty {
            preTypingContent
        } else {
            postTypingContent
        }
    }

    // MARK: - Pre-typing: suggested + browse shelves

    @ViewBuilder
    private var preTypingContent: some View {
        if let result = viewModel.currentSearchResult, !result.suggested.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Suggested")
                cardGrid(result.suggested)
            }
        }

        if let result = viewModel.currentSearchResult {
            ForEach(result.browseShelves) { shelf in
                VStack(alignment: .leading, spacing: 10) {
                    DiscoveryShelfHeader(shelf: shelf)
                    horizontalCards(shelf.items)
                }
            }
        }

        if viewModel.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    // MARK: - Post-typing: instant results

    @ViewBuilder
    private var postTypingContent: some View {
        if viewModel.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let result = viewModel.currentSearchResult {
            if result.matches.isEmpty {
                emptySearchView
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("\(result.matches.count) results")
                    // Staggered materialize entrance
                    LazyVStack(spacing: 12) {
                        ForEach(Array(result.matches.enumerated()), id: \.element.id) { index, card in
                            DiscoveryCardView(
                                card: card,
                                onTap: { _ in },
                                onPreview: { showPreview = $0 }
                            )
                            .frame(maxWidth: .infinity)
                            .transition(searchResultTransition(index: index))
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Staggered entrance transition

    private func searchResultTransition(index: Int) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        let delay = Double(index) * 0.04
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.94))
                .animation(.spring(response: 0.32, dampingFraction: 0.82).delay(delay)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
    }

    private func cardGrid(_ cards: [DiscoveryCard]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(cards) { card in
                DiscoveryCardView(card: card, onTap: { _ in }, onPreview: { showPreview = $0 })
            }
        }
        .padding(.horizontal, 16)
    }

    private func horizontalCards(_ cards: [DiscoveryCard]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(cards) { card in
                    DiscoveryCardView(card: card, onTap: { _ in }, onPreview: { showPreview = $0 })
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptySearchView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("No results for \"\(query)\"")
                .font(.system(size: 16, weight: .semibold))
            Text("Try a different search term.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results for \(query). Try a different search term.")
    }
}
