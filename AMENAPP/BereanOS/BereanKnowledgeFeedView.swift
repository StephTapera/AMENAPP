// BereanKnowledgeFeedView.swift
// AMENAPP — Berean OS
//
// Social Knowledge Feed — curated, anti-doom-scroll design.
// Filter bar: All | Research | Projects | Mentorship | Community
// Explicit load-more only (no infinite scroll), capped at 3 pages.
// End state: "You're caught up!" card — no auto-refresh.

import SwiftUI

// MARK: - BereanKnowledgeFeedView

struct BereanKnowledgeFeedView: View {

    @StateObject private var service = BereanKnowledgeFeedService.shared

    @State private var selectedFilter: BereanFeedItemType? = nil
    @State private var loadError: Error?

    // MARK: - Feature Flag Guard

    var body: some View {
        if !AMENFeatureFlags.shared.bereanOSSocialKnowledgeFeedEnabled {
            ContentUnavailableView(
                "Knowledge Feed",
                systemImage: "newspaper",
                description: Text("Coming soon")
            )
        } else {
            feedContent
        }
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                filterBar
                    .padding(.horizontal, 16)

                if service.feedItems.isEmpty && service.isLoading {
                    loadingPlaceholders
                } else if service.feedItems.isEmpty && !service.isLoading {
                    emptyState
                } else {
                    filteredItemsList
                    footerSection
                }
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Knowledge Feed")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.regularMaterial, for: .navigationBar)
        .task {
            try? await service.loadFeed()
        }
        .alert("Error", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK") { loadError = nil }
        } message: {
            Text(loadError?.localizedDescription ?? "An error occurred.")
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                filterChip(label: "All",        icon: "square.grid.2x2.fill",         filter: nil)
                filterChip(label: "Research",   icon: "magnifyingglass.circle.fill",   filter: .research)
                filterChip(label: "Projects",   icon: "arrow.clockwise.circle.fill",   filter: .projectUpdate)
                filterChip(label: "Mentorship", icon: "person.bust.fill",              filter: .mentorGuidance)
                filterChip(label: "Community",  icon: "book.fill",                     filter: .learningThread)
            }
            .padding(.horizontal, 2)
        }
    }

    private func filterChip(label: String, icon: String, filter: BereanFeedItemType?) -> some View {
        let isSelected = selectedFilter == filter
        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedFilter = filter
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(.secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter\(isSelected ? ", selected" : "")")
    }

    // MARK: - Filtered Items

    private var filteredFeedItems: [BereanFeedItem] {
        guard let filter = selectedFilter else { return service.feedItems }
        return service.feedItems.filter { $0.itemType == filter }
    }

    private var filteredItemsList: some View {
        ForEach(filteredFeedItems) { item in
            BereanFeedItemCard(item: item)
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        Group {
            if service.hasReachedEnd {
                caughtUpCard
            } else if service.loadCount < 3 {
                loadMoreButton
            }
        }
        .padding(.horizontal, 16)
    }

    private var loadMoreButton: some View {
        Button {
            Task {
                do {
                    try await service.loadMore()
                } catch {
                    loadError = error
                }
            }
        } label: {
            HStack {
                if service.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(service.isLoading ? "Loading\u{2026}" : "Load More")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .disabled(service.isLoading)
        .accessibilityLabel("Load more feed items")
    }

    private var caughtUpCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("You\u{2019}re caught up!")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Check back later for new knowledge from the community.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
        .accessibilityLabel("You are caught up with the knowledge feed")
    }

    // MARK: - Loading Placeholders

    private var loadingPlaceholders: some View {
        ForEach(0..<4, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemFill))
                .frame(height: 140)
                .padding(.horizontal, 16)
                .opacity(0.6)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Feed Items",
            systemImage: "newspaper",
            description: Text("Knowledge items will appear here when the community shares projects and insights.")
        )
        .padding(.top, 40)
    }
}
