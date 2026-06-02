import SwiftUI

// MARK: - Covenant Search View
// Scoped search: all, posts, rooms, messages, events, scripture, creators.
// Results respect permissions — locked content shown with paywall prompt.

struct AmenCovenantSearchView: View {
    var covenantId: String? = nil
    @StateObject private var searchService = AmenCovenantSearchService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedScope: CovenantSearchScope = .all
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                scopePills
                    .padding(.vertical, 8)
                Divider()

                if query.isEmpty {
                    recentQueriesView
                } else if searchService.isSearching {
                    searchingState
                } else if searchService.results.isEmpty {
                    emptyState
                } else {
                    resultsView
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        searchService.clearResults()
                        dismiss()
                    }
                }
            }
            .onAppear { isFocused = true }
            .onChange(of: query) { _, newValue in
                Task { await searchService.search(query: newValue, scope: selectedScope, covenantId: covenantId) }
            }
            .onChange(of: selectedScope) { _, newValue in
                guard !query.isEmpty else { return }
                Task { await searchService.search(query: query, scope: newValue, covenantId: covenantId) }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search communities…", text: $query)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await searchService.search(query: query, scope: selectedScope, covenantId: covenantId) }
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Scope Pills

    private var scopePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CovenantSearchScope.allCases, id: \.self) { scope in
                    Button {
                        selectedScope = scope
                    } label: {
                        Label(scope.displayName, systemImage: scope.icon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(selectedScope == scope ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selectedScope == scope ? Color.purple : Color(uiColor: .secondarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Recent Queries

    private var recentQueriesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !searchService.recentQueries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            ForEach(searchService.recentQueries, id: \.self) { q in
                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28)
                                    Button { query = q } label: {
                                        Text(q)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    Button { searchService.removeRecentQuery(q) } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                Divider().padding(.leading, 56)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal, 16)
                    }
                }

                Text("Search for posts, rooms, events, scripture, and creators.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 20)
        }
    }

    // MARK: - Searching State

    private var searchingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Searching…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No results found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try a different search term or scope.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        List {
            let grouped = Dictionary(grouping: searchService.results, by: \.scope)
            ForEach(CovenantSearchScope.allCases, id: \.self) { scope in
                if let items = grouped[scope], !items.isEmpty {
                    Section(scope.displayName) {
                        ForEach(items) { result in
                            CovenantSearchResultRow(result: result)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Search Result Row

private struct CovenantSearchResultRow: View {
    let result: CovenantSearchResult
    @State private var showPaywall = false

    var body: some View {
        Button {
            if result.isLocked {
                showPaywall = true
            } else if let link = result.deepLink {
                AmenCovenantDeepLinkResolver.shared.resolve(link)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: result.scope.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.purple.opacity(0.1)))

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(result.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        if result.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let sub = result.subtitle {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
