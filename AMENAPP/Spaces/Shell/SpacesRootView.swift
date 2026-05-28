// SpacesRootView.swift
// AMENAPP — Spaces v2 Navigation Shell (Agent C)
//
// Top-level Spaces entry point, inserted as the Spaces tab in ContentView.
// iPhone: NavigationStack with community switcher in a leading sidebar-style sheet.
// iPad: NavigationSplitView with community sidebar.
// Animates community switch with spring.

import SwiftUI
import FirebaseAuth

// MARK: - SpacesRootView

@MainActor
struct SpacesRootView: View {

    // MARK: - State

    @State private var communities: [SpacesCommunity] = []
    @State private var selectedCommunityId: String = ""
    @State private var isLoadingCommunities: Bool = true
    @State private var showCommunitySwitcherSheet: Bool = false
    @State private var showCreationWizard: Bool = false

    // Badge counts — keyed by communityId (populated from notification layer)
    // Callers can inject this via environment or direct binding in the future.
    @State private var unreadByCommunity: [String: Int] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isIPad: Bool { horizontalSizeClass == .regular }

    // MARK: - Body

    var body: some View {
        Group {
            if isIPad {
                ipadLayout
            } else {
                iphoneLayout
            }
        }
        .task { await loadCommunities() }
        .sheet(isPresented: $showCreationWizard) {
            SpaceCreationWizard(communityId: selectedCommunityId)
        }
    }

    // MARK: - iPhone layout

    private var iphoneLayout: some View {
        NavigationStack {
            communityContent
                .navigationTitle(communities.first(where: { $0.id == selectedCommunityId })?.name ?? "Spaces")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        communityAvatarButton
                    }
                }
        }
        .sheet(isPresented: $showCommunitySwitcherSheet) {
            communitySwitcherSheet
        }
    }

    // MARK: - iPad layout

    private var ipadLayout: some View {
        NavigationSplitView {
            CommunitySwitcherView(
                selectedCommunityId: $selectedCommunityId,
                communities: communities,
                unreadByCommunity: unreadByCommunity
            )
            .navigationSplitViewColumnWidth(64)
        } detail: {
            communityContent
        }
    }

    // MARK: - Community content

    @ViewBuilder
    private var communityContent: some View {
        if isLoadingCommunities {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading your communities")
        } else if communities.isEmpty {
            emptyCommunitiesView
        } else {
            SpacesListView(
                communityId: selectedCommunityId,
                onStartSomething: { showCreationWizard = true }
            )
            .id(selectedCommunityId) // force re-mount on community switch
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(), value: selectedCommunityId)
        }
    }

    // MARK: - Community avatar button (iPhone toolbar)

    private var communityAvatarButton: some View {
        Button {
            showCommunitySwitcherSheet = true
        } label: {
            let current = communities.first(where: { $0.id == selectedCommunityId })
            SpaceAvatarView(
                avatarURL: current?.avatarURL,
                title: current?.name ?? "C",
                size: 32,
                isShared: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch community")
        .accessibilityHint("Opens the community switcher.")
    }

    // MARK: - Community switcher sheet (iPhone)

    private var communitySwitcherSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(communities) { community in
                        let communityId = community.id ?? ""
                        let isSelected = communityId == selectedCommunityId
                        let unread = unreadByCommunity[communityId] ?? 0

                        Button {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring()) {
                                selectedCommunityId = communityId
                            }
                            showCommunitySwitcherSheet = false
                        } label: {
                            HStack(spacing: 14) {
                                SpaceAvatarView(
                                    avatarURL: community.avatarURL,
                                    title: community.name,
                                    size: 44,
                                    isShared: false
                                )
                                .overlay {
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(AmenTheme.Colors.amenPurple, lineWidth: 2)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(community.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                                    Text("@\(community.handle)")
                                        .font(.caption)
                                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                                }

                                Spacer(minLength: 0)

                                if unread > 0 {
                                    Circle()
                                        .fill(AmenTheme.Colors.amenPurple)
                                        .frame(width: 10, height: 10)
                                }

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AmenTheme.Colors.amenPurple)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(community.name)\(isSelected ? ", selected" : "")\(unread > 0 ? ", \(unread) unread" : "")")
                        .accessibilityHint("Double-tap to switch to this community.")
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showCommunitySwitcherSheet = false
                    }
                    .foregroundStyle(AmenTheme.Colors.amenPurple)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Empty state

    private var emptyCommunitiesView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(AmenTheme.Colors.textTertiary)

            Text("No Communities Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AmenTheme.Colors.textPrimary)

            Text("Create or join a community to get started with Spaces.")
                .font(.body)
                .foregroundStyle(AmenTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            AmenLiquidGlassPillButton(
                title: "Create a Community",
                systemImage: "plus",
                isLoading: false,
                isDisabled: false,
                hint: "Opens the community creation sheet."
            ) {
                showCommunitySwitcherSheet = true
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmenTheme.Colors.backgroundPrimary)
    }

    // MARK: - Data loading

    private func loadCommunities() async {
        isLoadingCommunities = true
        do {
            let loaded = try await SpacesService.shared.fetchMyCommunities()
            communities = loaded
            // Default to first community if none selected
            if selectedCommunityId.isEmpty || !loaded.contains(where: { $0.id == selectedCommunityId }) {
                selectedCommunityId = loaded.first?.id ?? ""
            }
        } catch {
            // Non-fatal — empty state shown; user can create a community.
        }
        isLoadingCommunities = false
    }
}

#if DEBUG
#Preview("SpacesRootView") {
    SpacesRootView()
}
#endif
