// TeachingSearchView.swift
// AMEN — Creator Profiles (ministry hubs) — Wave 3
//
// "Search inside all teachings" — a glass search field that, on submit, queries
// CreatorHubService.searchTeachings and renders [CreatorHubTeachingSearchHit] with the
// matched snippet and scripture references. Tapping a hit calls
// onJumpToTimestamp(teachingId, timestampSec) so the host can deep-link into the player.
//
// States: idle (no query), loading (skeleton), no-results, results.
//
// Conventions: black primary text; glass input bar (search) over the page background;
// flat result rows (no glass-on-glass); AmenTheme.Colors.* tokens; Dynamic Type;
// VoiceOver labels on the field and every result row.

import SwiftUI

struct TeachingSearchView: View {
    let creatorId: String

    /// Tapping a hit deep-links the host into the teaching at the matched timestamp.
    var onJumpToTimestamp: (_ teachingId: String, _ timestampSec: Double) -> Void = { _, _ in }

    @State private var query: String = ""
    @State private var hits: [CreatorHubTeachingSearchHit] = []
    @State private var isSearching = false
    @State private var didSearch = false
    @State private var searchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField
            results
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .accessibilityHidden(true)

            TextField("Search inside all teachings", text: $query)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
                .accessibilityLabel("Search inside all teachings")

            if !query.isEmpty {
                Button {
                    query = ""
                    hits = []
                    didSearch = false
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .amenGlassInputBar(cornerRadius: 22)
    }

    // MARK: - Results states

    @ViewBuilder
    private var results: some View {
        if isSearching {
            loadingState
        } else if let searchError {
            errorState(searchError)
        } else if didSearch && hits.isEmpty {
            noResultsState
        } else if !hits.isEmpty {
            resultsList
        } else {
            EmptyView()  // idle — nothing searched yet
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonCardRow(showsLeadingThumb: false)
            }
        }
        .accessibilityLabel("Searching teachings")
    }

    private func errorState(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AmenTheme.Colors.statusError)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text("No matches found")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Text("Try a different word or scripture reference.")
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private var resultsList: some View {
        VStack(spacing: 10) {
            ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                hitRow(hit)
            }
        }
    }

    private func hitRow(_ hit: CreatorHubTeachingSearchHit) -> some View {
        Button {
            onJumpToTimestamp(hit.teaching.id, hit.timestampSec ?? 0)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(hit.teaching.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let ts = hit.timestampSec {
                        Label(timestampLabel(ts), systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.statusInfo)
                    }
                }

                Text(hit.snippet)
                    .font(.subheadline)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !hit.scriptureRefs.isEmpty {
                    scriptureChips(hit.scriptureRefs)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .amenFlatCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hitAccessibilityLabel(hit))
        .accessibilityHint("Jumps to this moment in the teaching")
        .accessibilityAddTraits(.isButton)
    }

    private func scriptureChips(_ refs: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(refs, id: \.self) { ref in
                    Label(ref, systemImage: "book.closed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AmenTheme.Colors.amenGoldText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AmenTheme.Colors.surfaceChip))
                }
            }
        }
    }

    private func timestampLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func hitAccessibilityLabel(_ hit: CreatorHubTeachingSearchHit) -> String {
        var parts: [String] = [hit.teaching.title, hit.snippet]
        if !hit.scriptureRefs.isEmpty {
            parts.append("Scriptures: \(hit.scriptureRefs.joined(separator: ", "))")
        }
        if let ts = hit.timestampSec {
            parts.append("At \(timestampLabel(ts))")
        }
        return parts.joined(separator: ". ")
    }

    // MARK: - Behavior

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            didSearch = false
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            hits = try await CreatorHubService.shared.searchTeachings(
                creatorId: creatorId,
                query: trimmed
            )
            didSearch = true
        } catch {
            searchError = "Search is unavailable right now. Please try again."
            didSearch = true
        }
    }
}
