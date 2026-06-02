// AmenMinistryRoomShellView.swift
// AMEN Connect + Spaces — Living Ministry Rooms
// Agent 3 — built 2026-06-01

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Tab Enum

enum AmenMinistryRoomTab: String, CaseIterable, Identifiable {
    case chat       = "Chat"
    case prayer     = "Prayer"
    case tasks      = "Tasks"
    case decisions  = "Decisions"
    case care       = "Care"
    case files      = "Files"
    case history    = "History"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat:      return "bubble.left.and.bubble.right"
        case .prayer:    return "hands.sparkles"
        case .tasks:     return "checkmark.circle"
        case .decisions: return "scale.3d"
        case .care:      return "heart"
        case .files:     return "folder"
        case .history:   return "clock"
        }
    }
}

// MARK: - Main Shell

struct AmenMinistryRoomShellView: View {
    let space: AmenConnectSpacesSpace

    @State private var selectedTab: AmenMinistryRoomTab = .chat
    @State private var autoPanelExpanded: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animationStyle: Animation {
        reduceMotion ? .easeInOut(duration: 0.01) : .easeInOut(duration: 0.22)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Matte page background
            Color(red: 0.027, green: 0.024, blue: 0.031)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Glass top bar
                glassTopBar

                // Spiritual OS — Spaces Hero Card (Agent D, gated by AppStorage flag)
                AmenSpacesHeroCardSection(
                    spaceId: space.id,
                    userId: Auth.auth().currentUser?.uid ?? ""
                )

                // Glass tab switcher
                glassTabSwitcher

                // Collapsible auto-state panel (glass drawer)
                AmenMinistryRoomAutoStatePanel(
                    spaceId: space.id,
                    isExpanded: $autoPanelExpanded
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // Matte content area
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Glass Top Bar

    private var glassTopBar: some View {
        HStack(spacing: 12) {
            AmenMinistryRoomHeaderView(space: space)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.3)
                }
        }
    }

    // MARK: - Glass Tab Switcher

    private var glassTabSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(AmenMinistryRoomTab.allCases) { tab in
                    tabChip(tab)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.25)
                }
        }
    }

    private func tabChip(_ tab: AmenMinistryRoomTab) -> some View {
        let isActive = selectedTab == tab
        return Button {
            withAnimation(animationStyle) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isActive
                          ? Color.white.opacity(0.16)
                          : Color.clear)
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isActive
                                ? Color.white.opacity(0.32)
                                : Color.clear,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.rawValue) tab")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    // MARK: - Tab Content (matte)

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .chat:
            AmenMinistryRoomChatView(spaceId: space.id)
        case .prayer:
            AmenMinistryRoomPrayerTab(spaceId: space.id)
        case .tasks:
            AmenMinistryRoomTasksTab(spaceId: space.id)
        case .decisions:
            AmenMinistryRoomDecisionsTab(spaceId: space.id)
        case .care:
            AmenMinistryRoomCareTab(spaceId: space.id)
        case .files:
            AmenMinistryRoomFilesTab(spaceId: space.id)
        case .history:
            AmenMinistryRoomHistoryTab(spaceId: space.id)
        }
    }
}

// MARK: - Placeholder Tab (matte, used for non-Chat tabs)

struct AmenMinistryRoomPlaceholderTabView: View {
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color(red: 0.851, green: 0.643, blue: 0.255).opacity(0.7))
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.027, green: 0.024, blue: 0.031))
    }
}
