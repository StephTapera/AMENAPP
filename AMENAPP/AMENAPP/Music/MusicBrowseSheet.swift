// MUSIC FEATURE — Agent B
// MusicBrowseSheet.swift
// AMENAPP
//
// Full-screen sheet for browsing and searching worship music.
// - Trending tracks load on appear via MusicSearchService.
// - Search is debounced: waits 350 ms after the last keystroke before querying.
// - Selecting a track writes to the `selectedMusic` binding and dismisses.
// - Preview play/pause is handled by AudioPlaybackManager without dismissing.

import SwiftUI

struct MusicBrowseSheet: View {
    @Binding var selectedMusic: MusicAttachment?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var service = MusicSearchService()
    @State private var searchText = ""
    @ObservedObject private var player = AudioPlaybackManager.shared

    // Debounce task handle
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            // Sheet background — glass material so the compose area bleeds through
            Color.clear
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                Divider()
                    .foregroundStyle(AmenTheme.Colors.separatorSubtle)

                contentArea
            }
        }
        .presentationBackground(.thinMaterial)
        .task {
            await service.loadTrending()
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        ZStack {
            // Drag indicator
            Capsule()
                .fill(AmenTheme.Colors.textQuaternary)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .accessibilityLabel("Close music picker")
            }

            Text("Music")
                .font(.headline)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 16)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AmenTheme.Colors.textSecondary)

            TextField("Search worship music", text: $searchText)
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .tint(AmenTheme.Colors.amenGold)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    triggerSearch(immediate: true)
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchTask?.cancel()
                    searchTask = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .amenGlassInputBar(cornerRadius: 14)
        .onChange(of: searchText) { _, _ in
            triggerSearch(immediate: false)
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if service.isLoading {
            loadingView
        } else if searchText.isEmpty {
            trendingList
        } else {
            searchResultsList
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 80, height: 80)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AmenTheme.Colors.textSecondary)
                    .scaleEffect(1.2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Loading music")
    }

    private var trendingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !service.trendingTracks.isEmpty {
                    sectionHeader("Trending")

                    ForEach(service.trendingTracks) { track in
                        MusicRowView(
                            track: track,
                            isCurrentlyPlaying: player.currentTrackID == track.id,
                            onSelect: {
                                selectedMusic = track
                                dismiss()
                            },
                            onPreview: {
                                player.togglePlay(track)
                            }
                        )
                        .staggeredReveal(
                            index: service.trendingTracks.firstIndex(where: { $0.id == track.id }) ?? 0
                        )

                        if track.id != service.trendingTracks.last?.id {
                            Divider()
                                .padding(.leading, 76)
                                .foregroundStyle(AmenTheme.Colors.separatorSubtle)
                        }
                    }
                } else {
                    emptyStateView(message: "No worship music found")
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if service.searchResults.isEmpty {
                    emptyStateView(message: "No worship music found")
                } else {
                    ForEach(service.searchResults) { track in
                        MusicRowView(
                            track: track,
                            isCurrentlyPlaying: player.currentTrackID == track.id,
                            onSelect: {
                                selectedMusic = track
                                dismiss()
                            },
                            onPreview: {
                                player.togglePlay(track)
                            }
                        )
                        .staggeredReveal(
                            index: service.searchResults.firstIndex(where: { $0.id == track.id }) ?? 0
                        )

                        if track.id != service.searchResults.last?.id {
                            Divider()
                                .padding(.leading, 76)
                                .foregroundStyle(AmenTheme.Colors.separatorSubtle)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Reusable subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(AmenTheme.Colors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: "music.note.list")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Search debounce

    private func triggerSearch(immediate: Bool) {
        searchTask?.cancel()
        let query = searchText
        searchTask = Task {
            if !immediate {
                // 350 ms debounce
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard !Task.isCancelled else { return }
            await service.search(query: query)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    Color.gray
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            MusicBrowseSheet(selectedMusic: .constant(nil))
        }
}
#endif
