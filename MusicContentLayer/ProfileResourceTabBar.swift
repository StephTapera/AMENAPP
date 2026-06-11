// ProfileResourceTabBar.swift
// AMENAPP — MusicContentLayer
// Smart adaptive profile tab bar — shows only tabs with content

import SwiftUI

// MARK: - Data Models

enum ProfileTabType: String, Codable, Sendable, CaseIterable {
    case posts         = "Posts"
    case music         = "Music"
    case sermons       = "Sermons"
    case notes         = "Notes"
    case events        = "Events"
    case playlists     = "Playlists"
    case courses       = "Courses"
    case prayer        = "Prayer Requests"
    case communityPosts = "Community"
    case about         = "About"
    case store         = "Store"
    case giving        = "Giving"
    case members       = "Members"
    case liveRooms     = "Live Rooms"

    var systemImage: String {
        switch self {
        case .posts:          return "square.grid.2x2.fill"
        case .music:          return "music.note"
        case .sermons:        return "mic.fill"
        case .notes:          return "note.text"
        case .events:         return "calendar"
        case .playlists:      return "music.note.list"
        case .courses:        return "graduationcap.fill"
        case .prayer:         return "hands.and.sparkles.fill"
        case .communityPosts: return "person.3.fill"
        case .about:          return "info.circle.fill"
        case .store:          return "bag.fill"
        case .giving:         return "heart.fill"
        case .members:        return "person.2.fill"
        case .liveRooms:      return "waveform"
        }
    }

    var shortLabel: String {
        switch self {
        case .prayer:         return "Prayer"
        case .communityPosts: return "Community"
        case .liveRooms:      return "Live"
        default:              return rawValue
        }
    }
}

enum ProfileAccountType: String, Codable, Sendable {
    case personal
    case creator
    case church
    case organization
    case artist
    case pastor

    /// Suggested default tab ordering for this account type.
    var defaultTabOrder: [ProfileTabType] {
        switch self {
        case .church:
            return [.posts, .sermons, .music, .notes, .events, .members, .giving, .about]
        case .artist:
            return [.music, .playlists, .events, .posts, .store, .about]
        case .personal:
            return [.posts, .notes, .playlists, .communityPosts, .about]
        case .creator:
            return [.posts, .music, .playlists, .courses, .store, .about]
        case .organization:
            return [.posts, .events, .courses, .members, .giving, .about]
        case .pastor:
            return [.posts, .sermons, .notes, .prayer, .about]
        }
    }
}

// MARK: - Tab Pill Button

private struct TabPillButton: View {
    let tab: ProfileTabType
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text(tab.shortLabel)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    if reduceTransparency {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemBackground))
                    } else {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(Color.white.opacity(0.12)))
                    }
                } else {
                    Capsule().fill(Color.clear)
                }
            }
            .overlay {
                if isSelected {
                    Capsule()
                        .strokeBorder(
                            contrast == .increased
                                ? Color.primary.opacity(0.55)
                                : Color.white.opacity(0.3),
                            lineWidth: contrast == .increased ? 1.5 : 1
                        )
                }
            }
            .shadow(
                color: isSelected ? Color.black.opacity(0.1) : .clear,
                radius: 4,
                y: 2
            )
        }
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Main View

struct ProfileResourceTabBar: View {
    let accountType: ProfileAccountType
    let availableTabs: [ProfileTabType]
    @Binding var selectedTab: ProfileTabType

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// Tabs ordered by account type's default ordering, but only those present in `availableTabs`.
    private var orderedTabs: [ProfileTabType] {
        let preferred = accountType.defaultTabOrder
        let preferredFiltered = preferred.filter { availableTabs.contains($0) }
        let remaining = availableTabs.filter { !preferred.contains($0) }
        return preferredFiltered + remaining
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(orderedTabs, id: \.self) { tab in
                    TabPillButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectTab(tab)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background {
            if reduceTransparency {
                Color(uiColor: .systemBackground)
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Rectangle().fill(Color.white.opacity(0.04)))
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(contrast == .increased ? 1 : 0.35)
        }
    }

    private func selectTab(_ tab: ProfileTabType) {
        guard tab != selectedTab else { return }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                selectedTab = tab
            }
        }
    }
}

// MARK: - Preview Harness

private struct ProfileTabBarPreview: View {
    let accountType: ProfileAccountType
    let availableTabs: [ProfileTabType]
    @State private var selected: ProfileTabType

    init(accountType: ProfileAccountType, tabs: [ProfileTabType]) {
        self.accountType = accountType
        self.availableTabs = tabs
        self._selected = State(initialValue: tabs.first ?? .posts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(accountType.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ProfileResourceTabBar(
                accountType: accountType,
                availableTabs: availableTabs,
                selectedTab: $selected
            )
            HStack {
                Image(systemName: selected.systemImage)
                    .foregroundStyle(.purple)
                Text(selected.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview("Church Account") {
    ProfileTabBarPreview(
        accountType: .church,
        tabs: [.posts, .sermons, .music, .notes, .events, .members, .giving, .about]
    )
}

#Preview("Artist Account") {
    ProfileTabBarPreview(
        accountType: .artist,
        tabs: [.music, .playlists, .events, .posts, .store, .about]
    )
}

#Preview("Personal Account") {
    ProfileTabBarPreview(
        accountType: .personal,
        tabs: [.posts, .notes, .playlists, .communityPosts, .about]
    )
}
