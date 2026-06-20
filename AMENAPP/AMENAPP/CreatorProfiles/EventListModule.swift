// EventListModule.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// Vertical list of EventCard, grouped by status (Live / Upcoming / Past) and
// CalmCap-bounded: at most `maxVisible` cards are shown, with a "Load more" affordance
// that pages via CreatorHubService.pageEvents. Skeleton-first while the first page
// hydrates.
//
// Conventions: white bg under content; glass EventCards (no glass-on-glass — section
// headers are plain text on the page background); AmenTheme.Colors.* tokens; Dynamic
// Type; VoiceOver labels; reduce-motion respected by the skeleton primitives.

import SwiftUI

struct EventListModule: View {
    let creatorId: String
    let events: [CreatorHubEvent]

    /// Add-to-Calendar — bubbled up from each EventCard to the host (EventKit intent).
    var onAddToCalendar: (CreatorHubCalendarPayload) -> Void = { _ in }
    var onShare: (CreatorHubEvent) -> Void = { _ in }

    /// CalmCap: never overwhelm — show a bounded window, reveal more on request.
    var initialVisible: Int = 12

    @State private var maxVisible: Int = 12
    @State private var loaded: [CreatorHubEvent] = []
    @State private var nextCursor: String?
    @State private var didInitialLoad = false
    @State private var isPaging = false
    @State private var pageError: String?

    private var allEvents: [CreatorHubEvent] { loaded.isEmpty ? events : loaded }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !didInitialLoad && events.isEmpty {
                skeleton
            } else if allEvents.isEmpty {
                emptyState
            } else {
                ForEach(sections, id: \.title) { section in
                    sectionView(section)
                }
                loadMore
            }
        }
        .padding(.horizontal, 16)
        .onAppear {
            if loaded.isEmpty { loaded = events }
            maxVisible = max(maxVisible, initialVisible)
            didInitialLoad = true
        }
    }

    // MARK: - Sections

    private struct Section {
        let title: String
        let events: [CreatorHubEvent]
    }

    private var sections: [Section] {
        let window = Array(allEvents.prefix(maxVisible))
        let live = window.filter { $0.status == .live }
        let upcoming = window
            .filter { $0.status == .scheduled || $0.status == .draft }
            .sorted { $0.startsAt < $1.startsAt }
        let past = window
            .filter { $0.status == .ended || $0.status == .canceled }
            .sorted { $0.startsAt > $1.startsAt }

        var result: [Section] = []
        if !live.isEmpty { result.append(Section(title: "Live", events: live)) }
        if !upcoming.isEmpty { result.append(Section(title: "Upcoming", events: upcoming)) }
        if !past.isEmpty { result.append(Section(title: "Past", events: past)) }
        return result
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(section.events) { event in
                CreatorHubEventCard(
                    creatorId: creatorId,
                    event: event,
                    onAddToCalendar: onAddToCalendar,
                    onShare: onShare
                )
            }
        }
    }

    // MARK: - Load more (CalmCap-bounded pagination)

    @ViewBuilder
    private var loadMore: some View {
        let hasMoreWindow = allEvents.count > maxVisible
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
                .accessibilityLabel("Load more events")

                if let pageError {
                    Text(pageError)
                        .font(.caption)
                        .foregroundStyle(AmenTheme.Colors.statusError)
                }
            }
        }
    }

    private func loadNextPage() async {
        // If we still have un-shown items within the current window cap, just reveal more.
        if allEvents.count > maxVisible {
            maxVisible += 12
            return
        }
        guard !isPaging else { return }
        isPaging = true
        pageError = nil
        defer { isPaging = false }
        do {
            let (items, cursorOut) = try await CreatorHubService.shared.pageEvents(
                creatorId: creatorId,
                cursor: nextCursor
            )
            loaded.append(contentsOf: items)
            nextCursor = cursorOut
            maxVisible += items.count
        } catch {
            pageError = "Couldn't load more events."
        }
    }

    // MARK: - Skeleton / empty

    private var skeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonCardRow()
            }
        }
        .accessibilityLabel("Loading events")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No events yet")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Check back soon for upcoming gatherings.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}
