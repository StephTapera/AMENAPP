import SwiftUI

struct AmenDiscoverView: View {
    @StateObject private var viewModel = AmenDiscoverViewModel()
    @Namespace private var tileNamespace
    @State private var showReasonSheet = false
    @State private var showFeedbackSheet = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showDiscussionDiscovery = false

    // Disambiguation routing state
    @State private var showBereanSheet = false
    @State private var bereanInitialQuery: String = ""
    @State private var showScriptureSearch = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            ScrollView {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: DiscoverOffsetKey.self, value: proxy.frame(in: .named("amen_discover")).minY)
                }
                .frame(height: 0)

                VStack(spacing: 12) {
                    AmenDiscoverSearchCapsule(
                        searchQuery: $viewModel.searchQuery,
                        compactProgress: min(max(-scrollOffset / 160, 0), 1),
                        onBereanAI: { query in
                            bereanInitialQuery = query
                            showBereanSheet = true
                        },
                        onFindScripture: {
                            showScriptureSearch = true
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    AmenDiscoverTopicRail(filters: viewModel.filters, selected: viewModel.selectedFilter) { filter in
                        Task { await viewModel.applyFilter(filter) }
                    }

                    if viewModel.isLoading {
                        AmenDiscoverSkeletonGrid()
                    } else if viewModel.errorMessage != nil {
                        AmenDiscoverEmptyState {
                            Task { await viewModel.loadInitial() }
                        }
                    } else if viewModel.items.isEmpty {
                        AmenDiscoverEmptyState {
                            Task { await viewModel.loadInitial() }
                        }
                    } else {
                        AmenDiscoverGridView(
                            items: viewModel.items,
                            onTap: { item in
                                viewModel.logTap(item)
                                viewModel.openDetail(item)
                            },
                            onAppear: { item in
                                Task { await viewModel.loadMoreIfNeeded(current: item) }
                            },
                            namespace: tileNamespace
                        )
                    }

                    // Discussions Discovery entry point (album-style groups browse)
                    if AMENFeatureFlags.shared.discussionDiscoveryHomeEnabled {
                        Button {
                            showDiscussionDiscovery = true
                        } label: {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.44, green: 0.26, blue: 0.80))
                                Text("Browse Groups")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(AmenPressStyle(scale: 0.985))
                        .accessibilityLabel("Browse Groups")
                        .accessibilityHint("Opens the groups discovery page")
                    }

                    // Organization Experiences section
                    if AMENFeatureFlags.shared.organizationExperiencesEnabled {
                        OrganizationExperienceDiscoverySection()
                    }
                }
                .padding(.bottom, 90)
            }
            .coordinateSpace(name: "amen_discover")
            .onPreferenceChange(DiscoverOffsetKey.self) { scrollOffset = $0 }

            // AmenDiscoverGlassTabBar retired — AmenDiscoverTopicRail at top is the canonical filter.
            // AmenDiscoverGlassTabBar(selected: $viewModel.selectedFilter, tabs: ["For You", "Churches", "Sermons", "Selah"])
            //     .padding(.bottom, 12)
            //     .opacity(max(0.72, min(1, 1 - (-scrollOffset / 900))))
        }
        .task {
            AMENAnalyticsService.shared.track(.discoverView)
            await viewModel.loadInitial()
        }
        .sheet(isPresented: $showBereanSheet) {
            if bereanInitialQuery.isEmpty {
                BereanChatView()
            } else {
                BereanChatView(initialQuery: bereanInitialQuery)
                    .onAppear { bereanInitialQuery = "" }
            }
        }
        .sheet(isPresented: $showScriptureSearch) {
            BereanScriptureSearchSheet { _ in
                showScriptureSearch = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $viewModel.selectedItem) { item in
            AmenDiscoverDetailView(
                item: item,
                namespace: tileNamespace,
                onWhyThis: {
                    Task {
                        await viewModel.loadWhyThis(for: item)
                        showReasonSheet = true
                    }
                },
                onFeedback: {
                    showFeedbackSheet = true
                }
            )
            .sheet(isPresented: $showReasonSheet) {
                AmenDiscoverReasonSheet(reason: viewModel.reasonText)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showFeedbackSheet) {
                AmenDiscoverSafetyFeedbackSheet { feedback in
                    Task { await viewModel.submitFeedback(item, feedback: feedback) }
                }
            }
        }
        // "Near Me" filter chip → NearbyPeopleView (privacy-gated)
        .sheet(isPresented: $viewModel.showNearbyPeopleSheet) {
            NearbyPeopleView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDiscussionDiscovery) {
            DiscussionDiscoveryHomeView()
                .presentationDragIndicator(.visible)
        }
    }
}

private struct DiscoverOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AmenDiscoverErrorState: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.secondary)

            VStack(spacing: 6) {
                Text("Couldn't load your feed")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: onRetry) {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed failed to load. Tap Retry to try again.")
    }
}

private struct AmenDiscoverEmptyState: View {
    var onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            AmenGlass3DIcon(systemName: "sparkles", tint: AmenTheme.Colors.amenGold, size: 72)

            VStack(spacing: 6) {
                Text("Your AMEN Flow is warming up")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("We're curating faith content just for you.\nCheck back shortly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: onRefresh) {
                Text("Refresh")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed is empty. Tap Refresh to check for new content.")
    }
}

private struct AmenDiscoverSkeletonGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 170)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct OrganizationExperienceDiscoverySection: View {
    @State private var showOrgSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Organizations")
                    .font(AMENFont.bold(17))
                    .foregroundStyle(.primary)
                Spacer()
                Button("Browse") {
                    HapticManager.impact(style: .light)
                    showOrgSearch = true
                }
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Browse all organizations")
            }
            .padding(.horizontal, 16)

            Text("Churches, schools, and ministries active on Amen")
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
        .sheet(isPresented: $showOrgSearch) {
            NavigationStack {
                ChurchSearchView()
                    .navigationTitle("Find Organizations")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

#Preview {
    AmenDiscoverView()
}
