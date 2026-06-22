// TeachingLibraryModule.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// The teaching library: a TeachingSearchView pinned at the top ("search inside all
// teachings"), then the catalog grouped by series. Standalone teachings (no series)
// are collected under "Other teachings". CalmCap-bounded with a "Load more" that pages
// via CreatorHubService.pageTeachings. Skeleton-first.
//
// Conventions: black primary text; glass TeachingCards (no glass-on-glass — section
// headers are plain text on the page background); AmenTheme.Colors.* tokens; Dynamic
// Type; VoiceOver — section headers carry .isHeader; cards are combined buttons.

import SwiftUI

struct TeachingLibraryModule: View {
    let creatorId: String
    let teachings: [CreatorHubTeaching]

    /// Play a teaching (host opens the player).
    var onPlay: (CreatorHubTeaching) -> Void = { _ in }
    /// Search-hit deep link into a teaching at a timestamp.
    var onJumpToTimestamp: (_ teachingId: String, _ timestampSec: Double) -> Void = { _, _ in }

    /// CalmCap: bound how many teachings render before "Load more".
    var initialVisible: Int = 12

    @State private var maxVisible: Int = 12
    @State private var loaded: [CreatorHubTeaching] = []
    @State private var nextCursor: String?
    @State private var didInitialLoad = false
    @State private var isPaging = false
    @State private var pageError: String?

    private var allTeachings: [CreatorHubTeaching] { loaded.isEmpty ? teachings : loaded }
    private var window: [CreatorHubTeaching] { Array(allTeachings.prefix(maxVisible)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TeachingSearchView(creatorId: creatorId, onJumpToTimestamp: onJumpToTimestamp)

            if !didInitialLoad && teachings.isEmpty {
                skeleton
            } else if allTeachings.isEmpty {
                emptyState
            } else {
                ForEach(seriesGroups, id: \.title) { group in
                    seriesSection(group)
                }
                loadMore
            }
        }
        .padding(.horizontal, 16)
        .onAppear {
            if loaded.isEmpty { loaded = teachings }
            maxVisible = max(maxVisible, initialVisible)
            didInitialLoad = true
        }
    }

    // MARK: - Series grouping

    private struct SeriesGroup {
        let title: String
        let teachings: [CreatorHubTeaching]
    }

    private var seriesGroups: [SeriesGroup] {
        var order: [String] = []
        var buckets: [String: [CreatorHubTeaching]] = [:]
        let otherKey = "Other teachings"

        for teaching in window {
            let key = (teaching.series?.isEmpty == false) ? teaching.series! : otherKey
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(teaching)
        }

        // Keep "Other teachings" last.
        let sortedKeys = order.sorted { lhs, rhs in
            if lhs == otherKey { return false }
            if rhs == otherKey { return true }
            return false
        }
        return sortedKeys.map { SeriesGroup(title: $0, teachings: buckets[$0] ?? []) }
    }

    private func seriesSection(_ group: SeriesGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(group.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(group.teachings) { teaching in
                TeachingCard(teaching: teaching, onPlay: onPlay)
            }
        }
    }

    // MARK: - Load more (CalmCap-bounded pagination)

    @ViewBuilder
    private var loadMore: some View {
        let hasMoreWindow = allTeachings.count > maxVisible
        if hasMoreWindow || nextCursor != nil {
            VStack(spacing: 8) {
                Button {
                    Task { await loadNextPage() }
                } label: {
                    HStack(spacing: 6) {
                        if isPaging {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(isPaging ? "Loading…" : "Load more")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AmenTheme.Colors.surfaceChip)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPaging)
                .accessibilityLabel("Load more teachings")

                if let pageError {
                    Text(pageError)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.statusError)
                }
            }
        }
    }

    private func loadNextPage() async {
        if allTeachings.count > maxVisible {
            maxVisible += 12
            return
        }
        guard !isPaging else { return }
        isPaging = true
        pageError = nil
        defer { isPaging = false }
        do {
            let (items, cursorOut) = try await CreatorHubService.shared.pageTeachings(
                creatorId: creatorId,
                cursor: nextCursor
            )
            loaded.append(contentsOf: items)
            nextCursor = cursorOut
            maxVisible += items.count
        } catch {
            pageError = "Couldn't load more teachings."
        }
    }

    // MARK: - Skeleton / empty

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonCardRow()
            }
        }
        .accessibilityLabel("Loading teachings")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.title)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No teachings yet")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("This ministry hasn't published teachings yet.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}
