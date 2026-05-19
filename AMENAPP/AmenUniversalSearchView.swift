// AmenUniversalSearchView.swift
// AMENAPP
// Standalone full-screen search modal presentable from any context in the app —
// Berean chat, Selah, creation flow, command palette.
// Composes UniversalSearchViewModel, UniversalSearchResultsView, SearchScopeTabBar,
// and BereanSearchAnswerCard (all pre-existing) into a single self-contained sheet.

import SwiftUI

struct AmenUniversalSearchView: View {

    // Optional pre-fill (e.g. launched from Berean with a verse reference)
    var initialQuery: String = ""
    var onDismiss: (() -> Void)? = nil

    @StateObject private var vm = UniversalSearchViewModel()
    @State private var query: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBarRow

                // Scope tabs (only when actively searching)
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SearchScopeTabBar(selected: $vm.searchScope)
                }

                // Body
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    idleBody
                } else {
                    activeBody
                }
            }
            .navigationBarHidden(true)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .onAppear {
            query = initialQuery
            isFocused = true
            if !initialQuery.isEmpty {
                vm.scheduleSearch(query: initialQuery)
            } else {
                Task { await vm.loadTrendingTopics() }
            }
        }
        .onChange(of: query) { _, newValue in
            vm.scheduleSearch(query: newValue)
        }
    }

    // MARK: - Search Bar

    private var searchBarRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16, weight: .medium))

                TextField("Search people, verses, churches…", text: $query)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        vm.addRecentSearch(query)
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !query.isEmpty {
                    Button {
                        query = ""
                        vm.scheduleSearch(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            Button("Cancel") {
                isFocused = false
                onDismiss?()
            }
            .foregroundStyle(Color.accentColor)
            .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Idle State (no query)

    private var idleBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Recent searches
                if !vm.recentSearches.isEmpty {
                    recentSearchesSection
                }

                // Trending topics
                trendingSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recent", trailingAction: ("Clear", { vm.clearAllRecentSearches() }))

            ForEach(vm.recentSearches, id: \.self) { term in
                Button {
                    query = term
                    vm.scheduleSearch(query: term)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)

                        Text(term)
                            .foregroundStyle(.primary)
                            .font(.body)

                        Spacer()

                        Button {
                            vm.removeRecentSearch(term)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                Divider()
            }
        }
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Trending", trailingAction: nil)

            if vm.isTrendingLoading {
                trendingShimmer
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(vm.trendingTopics.prefix(8)) { topic in
                        NavigationLink {
                            DiscoveryTopicPageView(topic: topic)
                        } label: {
                            trendingTopicCell(topic)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func trendingTopicCell(_ topic: DiscoveryTopic) -> some View {
        HStack(spacing: 8) {
            Image(systemName: topic.icon)
                .font(.system(size: 16))
                .foregroundStyle(topic.iconColor)
                .frame(width: 32, height: 32)
                .background(topic.iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text("#\(topic.title)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(topic.postCount) posts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var trendingShimmer: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 52)
                    .redacted(reason: .placeholder)
            }
        }
    }

    // MARK: - Active State (query entered)

    private var activeBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {

                // Berean AI answer card (for question-form queries)
                if vm.bereanAnswerLoading || !vm.bereanAnswer.isEmpty {
                    bereanAnswerCard
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }

                // Delegate to existing results view
                if vm.isLoading {
                    loadingIndicator
                } else {
                    UniversalSearchResultsView(query: query, viewModel: vm, searchText: $query)
                }
            }
        }
    }

    private var bereanAnswerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text("Berean Answer")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                if vm.bereanAnswerLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if !vm.bereanAnswer.isEmpty {
                Text(vm.bereanAnswer)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Searching…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, trailingAction: (String, () -> Void)?) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            if let (label, action) = trailingAction {
                Button(label, action: action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Modifier for easy presentation

extension View {
    func amenUniversalSearch(isPresented: Binding<Bool>, initialQuery: String = "") -> some View {
        self.sheet(isPresented: isPresented) {
            AmenUniversalSearchView(initialQuery: initialQuery) {
                isPresented.wrappedValue = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }
}
