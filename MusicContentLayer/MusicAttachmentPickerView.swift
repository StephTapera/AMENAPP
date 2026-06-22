// MusicAttachmentPickerView.swift
// AMENAPP — MusicContentLayer
//
// Sheet for picking a music, sermon, or resource attachment to add to a post.
// Tabs: Songs | Sermons | Playlists | Church Resources
// Uses LiquidGlassAttachmentCard in .compact mode.

import SwiftUI

// MARK: - Mock Data

let mockMusicResults: [ContentAttachment] = [
    ContentAttachment(
        id: "mock-music-1",
        type: .song,
        musicResource: MusicResource(
            id: "mock-mr-1",
            title: "Way Maker",
            artistName: "Sinach",
            albumName: "Way Maker",
            artworkURL: nil,
            previewURL: URL(string: "https://example.com/p1.mp3"),
            durationSeconds: 242,
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Way Maker",
        displaySubtitle: "Sinach",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-music-2",
        type: .song,
        musicResource: MusicResource(
            id: "mock-mr-2",
            title: "Goodness of God",
            artistName: "Bethel Music",
            albumName: "Victory",
            artworkURL: nil,
            previewURL: URL(string: "https://example.com/p2.mp3"),
            durationSeconds: 320,
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Goodness of God",
        displaySubtitle: "Bethel Music",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-music-3",
        type: .song,
        musicResource: MusicResource(
            id: "mock-mr-3",
            title: "Reckless Love",
            artistName: "Cory Asbury",
            albumName: "Reckless Love",
            artworkURL: nil,
            previewURL: nil,
            durationSeconds: 285,
            isVerifiedClean: true,
            rightsPolicy: .memberOnly,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Reckless Love",
        displaySubtitle: "Cory Asbury",
        displayArtworkURL: nil,
        rightsPolicy: .memberOnly,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-music-4",
        type: .album,
        musicResource: MusicResource(
            id: "mock-mr-4",
            title: "Graves Into Gardens",
            artistName: "Elevation Worship",
            albumName: nil,
            artworkURL: nil,
            previewURL: URL(string: "https://example.com/p4.mp3"),
            durationSeconds: 0,
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Graves Into Gardens",
        displaySubtitle: "Elevation Worship",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-music-5",
        type: .worshipSet,
        musicResource: MusicResource(
            id: "mock-mr-5",
            title: "Sunday Morning Worship Set",
            artistName: "Life.Church Worship",
            albumName: nil,
            artworkURL: nil,
            previewURL: URL(string: "https://example.com/p5.mp3"),
            durationSeconds: 3600,
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Sunday Morning Worship Set",
        displaySubtitle: "Life.Church Worship",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    )
]

let mockSermonResults: [ContentAttachment] = [
    ContentAttachment(
        id: "mock-sermon-1",
        type: .sermonClip,
        musicResource: nil,
        sermonResource: SermonResource(
            id: "mock-sr-1",
            title: "Greater Things",
            speakerName: "Steven Furtick",
            seriesName: "Greater Things Series",
            churchName: "Elevation Church",
            artworkURL: nil,
            audioURL: URL(string: "https://example.com/s1.mp3"),
            videoURL: nil,
            durationSeconds: 2700,
            scriptureReferences: ["John 14:12"],
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        profileID: nil,
        externalURL: nil,
        displayTitle: "Greater Things",
        displaySubtitle: "Steven Furtick • Elevation Church",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-sermon-2",
        type: .sermonClip,
        musicResource: nil,
        sermonResource: SermonResource(
            id: "mock-sr-2",
            title: "The Power of Prayer",
            speakerName: "T.D. Jakes",
            seriesName: nil,
            churchName: "The Potter's House",
            artworkURL: nil,
            audioURL: URL(string: "https://example.com/s2.mp3"),
            videoURL: nil,
            durationSeconds: 3600,
            scriptureReferences: ["Matthew 6:9-13"],
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        profileID: nil,
        externalURL: nil,
        displayTitle: "The Power of Prayer",
        displaySubtitle: "T.D. Jakes • The Potter's House",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-sermon-3",
        type: .sermonClip,
        musicResource: nil,
        sermonResource: SermonResource(
            id: "mock-sr-3",
            title: "Faith Over Fear",
            speakerName: "Craig Groeschel",
            seriesName: "Fear Is Not the Boss of You",
            churchName: "Life.Church",
            artworkURL: nil,
            audioURL: URL(string: "https://example.com/s3.mp3"),
            videoURL: nil,
            durationSeconds: 2400,
            scriptureReferences: ["Isaiah 41:10"],
            isVerifiedClean: true,
            rightsPolicy: .free,
            visibility: .public,
            moderationStatus: .approved,
            createdAt: "2026-06-10T00:00:00Z"
        ),
        profileID: nil,
        externalURL: nil,
        displayTitle: "Faith Over Fear",
        displaySubtitle: "Craig Groeschel • Life.Church",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    )
]

private let mockPlaylistResults: [ContentAttachment] = [
    ContentAttachment(
        id: "mock-playlist-1",
        type: .playlist,
        musicResource: nil,
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Sunday Morning Praise",
        displaySubtitle: "Community Playlist • 24 songs",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-playlist-2",
        type: .playlist,
        musicResource: nil,
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Prayer & Meditation",
        displaySubtitle: "Curated by AMEN • 18 songs",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    )
]

private let mockChurchResourceResults: [ContentAttachment] = [
    ContentAttachment(
        id: "mock-church-1",
        type: .churchProfile,
        musicResource: nil,
        sermonResource: nil,
        profileID: "church-profile-elevation",
        externalURL: nil,
        displayTitle: "Elevation Church",
        displaySubtitle: "Charlotte, NC",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    ),
    ContentAttachment(
        id: "mock-church-2",
        type: .devotionalAudio,
        musicResource: nil,
        sermonResource: nil,
        profileID: nil,
        externalURL: nil,
        displayTitle: "Daily Devotional: Walk in the Word",
        displaySubtitle: "James Boice Ministries",
        displayArtworkURL: nil,
        rightsPolicy: .free,
        visibility: .public,
        isVerifiedClean: true,
        createdAt: "2026-06-10T00:00:00Z"
    )
]

// MARK: - PickerTab

private enum PickerTab: String, CaseIterable, Identifiable {
    case songs          = "Songs"
    case sermons        = "Sermons"
    case playlists      = "Playlists"
    case churchResources = "Church Resources"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .songs:            return "music.note"
        case .sermons:          return "mic.fill"
        case .playlists:        return "list.bullet"
        case .churchResources:  return "building.columns.fill"
        }
    }
}

// MARK: - MusicAttachmentPickerView

struct MusicAttachmentPickerView: View {

    let onSelect: (ContentAttachment) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText: String = ""
    @State private var selectedTab: PickerTab = .songs
    @State private var isLoading: Bool = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                tabBar
                Divider()
                contentArea
            }
            .navigationTitle("Add Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(searchPlaceholder, text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onChange(of: searchText) { _, _ in
                    simulateSearch()
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchPlaceholder: String {
        switch selectedTab {
        case .songs:            return "Search songs, albums, worship sets…"
        case .sermons:          return "Search sermons, speakers, churches…"
        case .playlists:        return "Search playlists…"
        case .churchResources:  return "Search churches, devotionals…"
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PickerTab.allCases) { tab in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        Label(tab.rawValue, systemImage: tab.systemImage)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedTab == tab
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            loadingState
        } else {
            let results = filteredResults
            if results.isEmpty {
                emptyState
            } else {
                resultsList(results)
            }
        }
    }

    private var filteredResults: [ContentAttachment] {
        let source: [ContentAttachment]
        switch selectedTab {
        case .songs:            source = mockMusicResults
        case .sermons:          source = mockSermonResults
        case .playlists:        source = mockPlaylistResults
        case .churchResources:  source = mockChurchResourceResults
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return source }

        return source.filter { attachment in
            attachment.displayTitle.lowercased().contains(query) ||
            (attachment.displaySubtitle?.lowercased().contains(query) ?? false)
        }
    }

    private func resultsList(_ results: [ContentAttachment]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(results) { attachment in
                    Button {
                        onSelect(attachment)
                        dismiss()
                    } label: {
                        LiquidGlassAttachmentCard(
                            attachment: attachment,
                            mode: .compact
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Double-tap to select")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: emptyStateIcon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(emptyStateBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateIcon: String {
        searchText.isEmpty ? "tray" : "magnifyingglass"
    }

    private var emptyStateTitle: String {
        searchText.isEmpty ? "Nothing Here Yet" : "No Results"
    }

    private var emptyStateBody: String {
        if searchText.isEmpty {
            return "There are no \(selectedTab.rawValue.lowercased()) to attach right now."
        } else {
            return "No \(selectedTab.rawValue.lowercased()) matched "\(searchText)". Try a different search."
        }
    }

    // MARK: - Search Simulation

    private func simulateSearch() {
        guard !searchText.isEmpty else { return }
        isLoading = true
        // Simulate async fetch — clear loading flag after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview("Music Attachment Picker") {
    MusicAttachmentPickerView { selected in
        print("Selected: \(selected.displayTitle)")
    }
}
